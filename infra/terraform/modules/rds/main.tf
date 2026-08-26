# ---------------------------------------------------------------------------
# RDS PostgreSQL privado.
#
# Decisoes:
#  - db.t4g.micro single-AZ: free tier; Multi-AZ documentado como evolucao.
#  - Subnets "database" sem rota para internet + publicly_accessible=false.
#  - SG aceita 5432 apenas do SG dos nos do EKS (nao de CIDR).
#  - Senha do master gerenciada pela AWS (manage_master_user_password):
#    nasce direto no Secrets Manager, nunca passa pelo state do Terraform,
#    e suporta rotacao nativa.
# ---------------------------------------------------------------------------

resource "aws_security_group" "this" {
  name        = "${var.name}-rds"
  description = "RDS PostgreSQL - acesso apenas dos nos do EKS"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = "${var.name}-rds" })
}

resource "aws_vpc_security_group_ingress_rule" "from_eks_nodes" {
  security_group_id            = aws_security_group.this.id
  description                  = "PostgreSQL a partir dos nos do EKS"
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  referenced_security_group_id = var.allowed_security_group_id
}

# Sem egress: o RDS nao inicia conexoes.

resource "aws_db_parameter_group" "this" {
  name_prefix = "${var.name}-pg16-"
  family      = "postgres16"
  description = "Parametros da ${var.name}"

  # log de queries lentas (> 500ms) para diagnostico via CloudWatch/psql
  parameter {
    name  = "log_min_duration_statement"
    value = "500"
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = var.tags
}

resource "aws_db_instance" "this" {
  identifier = var.name

  engine                     = "postgres"
  engine_version             = var.engine_version
  auto_minor_version_upgrade = true
  instance_class             = var.instance_class

  db_name  = var.db_name
  username = var.master_username

  manage_master_user_password = true

  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage # autoscaling de storage
  storage_type          = "gp3"
  storage_encrypted     = true

  db_subnet_group_name   = var.db_subnet_group_name
  vpc_security_group_ids = [aws_security_group.this.id]
  publicly_accessible    = false
  multi_az               = var.multi_az
  port                   = 5432

  parameter_group_name = aws_db_parameter_group.this.name

  backup_retention_period  = var.backup_retention_days
  backup_window            = "03:00-04:00"
  maintenance_window       = "sun:04:00-sun:05:00"
  copy_tags_to_snapshot    = true
  delete_automated_backups = true

  # Desafio: destruicao limpa ao final. Producao: deletion_protection=true,
  # skip_final_snapshot=false.
  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${var.name}-final"

  performance_insights_enabled = false # nao suportado em t4g.micro
  monitoring_interval          = 0     # enhanced monitoring custa CloudWatch

  apply_immediately = true

  tags = var.tags
}
