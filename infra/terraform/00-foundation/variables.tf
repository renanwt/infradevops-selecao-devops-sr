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
