variable "name" {
  description = "Nome do repositorio."
  type        = string
}

variable "keep_last_images" {
  description = "Quantidade de imagens mantidas pela lifecycle policy."
  type        = number
  default     = 10
}

variable "force_delete" {
  description = "Permite destruir o repositorio com imagens dentro."
  type        = bool
  default     = true
}

variable "tags" {
  type    = map(string)
  default = {}
}
