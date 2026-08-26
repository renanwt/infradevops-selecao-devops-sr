variable "name" {
  description = "Identificador da instancia e prefixo de recursos."
  type        = string
}

variable "vpc_id" {
  type = string
}

variable "db_subnet_group_name" {
  description = "Subnet group das subnets 'database' (sem rota para internet)."
  type        = string
}

variable "allowed_security_group_id" {
  description = "SG autorizado a conectar na 5432 (nos do EKS)."
  type        = string
}

variable "engine_version" {
  description = "Major do PostgreSQL; minor e escolhido/atualizado pela AWS."
  type        = string
  default     = "16"
}

variable "instance_class" {
  type    = string
  default = "db.t4g.micro"
}

variable "db_name" {
  type    = string
  default = "comments"
}

variable "master_username" {
  type    = string
  default = "comments_admin"
}

variable "allocated_storage" {
  description = "GiB iniciais (20 e o minimo/free tier)."
  type        = number
  default     = 20
}

variable "max_allocated_storage" {
  description = "Teto do autoscaling de storage (0 desliga)."
  type        = number
  default     = 50
}

variable "multi_az" {
  type    = bool
  default = false
}

variable "backup_retention_days" {
  description = "Dias de backup automatico (0 desliga; 1 e o minimo com PITR)."
  type        = number
  default     = 1
}

variable "deletion_protection" {
  type    = bool
  default = false
}

variable "skip_final_snapshot" {
  type    = bool
  default = true
}

variable "tags" {
  type    = map(string)
  default = {}
}
