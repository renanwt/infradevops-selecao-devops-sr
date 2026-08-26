variable "name" {
  description = "Prefixo dos nomes das roles/policies."
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN do OIDC provider do cluster EKS (IRSA)."
  type        = string
}

variable "secret_arns" {
  description = "ARNs dos secrets que o External Secrets pode ler."
  type        = list(string)
}

variable "ecr_repository_arn" {
  type = string
}

variable "eks_cluster_name" {
  type = string
}

variable "eks_cluster_arn" {
  type = string
}

variable "tfstate_bucket" {
  description = "Bucket do state remoto (plan no CI)."
  type        = string
}

variable "github_repository" {
  description = "owner/repo autorizado a assumir a role via OIDC."
  type        = string
}

variable "app_namespace" {
  description = "Namespace onde o pipeline pode fazer deploy."
  type        = string
  default     = "comments"
}

variable "tags" {
  type    = map(string)
  default = {}
}
