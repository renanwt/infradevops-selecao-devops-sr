variable "name" {
  description = "Nome do cluster."
  type        = string
}

variable "kubernetes_version" {
  description = "Versao do Kubernetes (usar STANDARD_SUPPORT: aws eks describe-cluster-versions)."
  type        = string
  default     = "1.35"
}

variable "vpc_id" {
  type = string
}

variable "vpc_cidr" {
  type = string
}

variable "private_subnet_ids" {
  description = "Subnets privadas para nos e ENIs do control plane."
  type        = list(string)
}

variable "public_access_cidrs" {
  description = "CIDRs com acesso ao endpoint publico da API do Kubernetes."
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

variable "tags" {
  type    = map(string)
  default = {}
}
