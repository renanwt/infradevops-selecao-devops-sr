variable "name" {
  description = "Prefixo de nome dos recursos."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR da VPC (/16 recomendado)."
  type        = string
}

variable "azs" {
  description = "Lista de AZs."
  type        = list(string)

  validation {
    condition     = length(var.azs) >= 2
    error_message = "EKS e RDS subnet group exigem ao menos 2 AZs."
  }
}

variable "single_nat_gateway" {
  description = "true = 1 NAT compartilhado; false = 1 por AZ."
  type        = bool
  default     = true
}

variable "cluster_name" {
  description = "Nome do cluster EKS (para tags de descoberta de subnets)."
  type        = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
