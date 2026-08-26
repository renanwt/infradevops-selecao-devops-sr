variable "region" {
  description = "Regiao AWS."
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Nome do projeto, usado em nomes e tags."
  type        = string
  default     = "comments-api"
}

variable "environment" {
  description = "Ambiente logico (dev/prod)."
  type        = string
  default     = "dev"
}

# --- rede -------------------------------------------------------------------
variable "vpc_cidr" {
  description = "CIDR da VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "az_count" {
  description = "Quantidade de AZs (min 2 para EKS e RDS subnet group)."
  type        = number
  default     = 2
}

variable "single_nat_gateway" {
  description = "1 NAT para todas as AZs (custo) vs 1 por AZ (HA)."
  type        = bool
  default     = true
}

# --- eks --------------------------------------------------------------------
variable "kubernetes_version" {
  description = "Versao do EKS em STANDARD_SUPPORT."
  type        = string
  default     = "1.35"
}

variable "eks_public_access_cidrs" {
  description = "CIDRs autorizados no endpoint publico da API do cluster."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "node_instance_type" {
  type    = string
  default = "t3.small"
}

variable "node_min_size" {
  type    = number
  default = 2
}

variable "node_max_size" {
  type    = number
  default = 3
}

variable "node_desired_size" {
  type    = number
  default = 2
}

# --- rds --------------------------------------------------------------------
variable "db_instance_class" {
  type    = string
  default = "db.t4g.micro"
}

variable "db_multi_az" {
  description = "Multi-AZ dobra o custo; false no desafio."
  type        = bool
  default     = false
}

variable "db_backup_retention_days" {
  type    = number
  default = 1
}

variable "db_deletion_protection" {
  type    = bool
  default = false
}

variable "db_skip_final_snapshot" {
  type    = bool
  default = true
}

# --- iam / ci ---------------------------------------------------------------
variable "github_repository" {
  description = "owner/repo do fork (trust policy do OIDC do GitHub Actions)."
  type        = string
  default     = "renanwt/infradevops-selecao-devops-sr"
}

variable "tfstate_bucket" {
  type    = string
  default = "comments-api-tfstate-208597681536"
}

variable "app_namespace" {
  type    = string
  default = "comments"
}

variable "github_actions_can_apply" {
  description = "true = pipeline pode rodar terraform apply (AdministratorAccess na role do CI)."
  type        = bool
  default     = false
}

# --- custo ------------------------------------------------------------------
variable "budget_limit_usd" {
  description = "Limite mensal do AWS Budget."
  type        = number
  default     = 15
}

variable "budget_email" {
  description = "E-mail para alertas de orcamento. Vazio desliga o budget."
  type        = string
  default     = ""
}
