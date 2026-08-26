locals {
  name = "${var.project}-${var.environment}"
}

data "aws_availability_zones" "available" {
  state = "available"
  # evita AZs sem suporte a alguns tipos de instancia
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

module "network" {
  source = "../modules/network"

  name               = local.name
  vpc_cidr           = var.vpc_cidr
  azs                = slice(data.aws_availability_zones.available.names, 0, var.az_count)
  single_nat_gateway = var.single_nat_gateway
  cluster_name       = local.name
}

module "ecr" {
  source = "../modules/ecr"

  name = var.project
}

module "eks" {
  source = "../modules/eks"

  name               = local.name
  kubernetes_version = var.kubernetes_version
  vpc_id             = module.network.vpc_id
  vpc_cidr           = module.network.vpc_cidr
  private_subnet_ids = module.network.private_subnet_ids

  public_access_cidrs = var.eks_public_access_cidrs
  node_instance_type  = var.node_instance_type
  node_min_size       = var.node_min_size
  node_max_size       = var.node_max_size
  node_desired_size   = var.node_desired_size
}
