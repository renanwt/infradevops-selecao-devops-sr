variable "region" {
  type    = string
  default = "us-east-1"
}

variable "project" {
  type    = string
  default = "comments-api"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "tfstate_bucket" {
  description = "Bucket onde esta o state do 00-foundation."
  type        = string
  default     = "comments-api-tfstate-208597681536"
}

variable "app_namespace" {
  type    = string
  default = "comments"
}

variable "external_secrets_chart_version" {
  description = "Versao do chart external-secrets/external-secrets."
  type        = string
  default     = "2.9.0"
}

variable "alb_controller_chart_version" {
  description = "Versao do chart eks/aws-load-balancer-controller."
  type        = string
  default     = "3.5.0"
}

variable "metrics_server_chart_version" {
  description = "Versao do chart metrics-server/metrics-server."
  type        = string
  default     = "3.14.0"
}
