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
