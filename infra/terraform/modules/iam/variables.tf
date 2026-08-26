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

variable "github_owner_id" {
  description = "ID numerico do owner no GitHub (gh api users/<owner> --jq .id). Necessario para o sub imutavel."
  type        = number
  default     = null
}

variable "github_repository_id" {
  description = "ID numerico do repositorio (gh api repos/<owner>/<repo> --jq .id)."
  type        = number
  default     = null
}

variable "app_namespace" {
  description = "Namespace onde o pipeline pode fazer deploy."
  type        = string
  default     = "comments"
}

variable "github_actions_can_apply" {
  description = "Anexa AdministratorAccess a role do CI para terraform apply via pipeline."
  type        = bool
  default     = false
}

variable "tags" {
  type    = map(string)
  default = {}
}
