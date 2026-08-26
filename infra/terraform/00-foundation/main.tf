locals {
  name = "${var.project}-${var.environment}"
}

data "aws_availability_zones" "available" {
  state = "available"
  # evita AZs sem suporte a alguns tipos de instancia
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

module "network" {
  source = "../modules/network"

  name               = local.name
  vpc_cidr           = var.vpc_cidr
  azs                = slice(data.aws_availability_zones.available.names, 0, var.az_count)
  single_nat_gateway = var.single_nat_gateway
  cluster_name       = local.name
}

module "ecr" {
  source = "../modules/ecr"

  name = var.project
}

module "eks" {
  source = "../modules/eks"

  name               = local.name
  kubernetes_version = var.kubernetes_version
  vpc_id             = module.network.vpc_id
  vpc_cidr           = module.network.vpc_cidr
  private_subnet_ids = module.network.private_subnet_ids

  public_access_cidrs = var.eks_public_access_cidrs
  node_instance_type  = var.node_instance_type
  node_min_size       = var.node_min_size
  node_max_size       = var.node_max_size
  node_desired_size   = var.node_desired_size
}

module "rds" {
  source = "../modules/rds"

  name                      = local.name
  vpc_id                    = module.network.vpc_id
  db_subnet_group_name      = module.network.database_subnet_group_name
  allowed_security_group_id = module.eks.node_security_group_id

  instance_class        = var.db_instance_class
  multi_az              = var.db_multi_az
  backup_retention_days = var.db_backup_retention_days
  deletion_protection   = var.db_deletion_protection
  skip_final_snapshot   = var.db_skip_final_snapshot
}

module "iam" {
  source = "../modules/iam"

  name              = local.name
  oidc_provider_arn = module.eks.oidc_provider_arn
  secret_arns       = [module.rds.master_user_secret_arn]

  ecr_repository_arn = module.ecr.repository_arn
  eks_cluster_name   = module.eks.cluster_name
  eks_cluster_arn    = module.eks.cluster_arn
  tfstate_bucket     = var.tfstate_bucket
  github_repository  = var.github_repository
  app_namespace      = var.app_namespace
}
