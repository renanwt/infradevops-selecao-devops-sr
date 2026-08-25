# ---------------------------------------------------------------------------
# Rede: VPC com 3 camadas de subnets por AZ.
#   public   -> IGW, ALB, NAT Gateway
#   private  -> nos do EKS (saida via NAT)
#   database -> RDS (sem rota para internet)
# ---------------------------------------------------------------------------

locals {
  # /20 por subnet: 4096 IPs, folga para o VPC CNI (1 IP por pod)
  public_subnets   = [for i, az in var.azs : cidrsubnet(var.vpc_cidr, 4, i)]
  private_subnets  = [for i, az in var.azs : cidrsubnet(var.vpc_cidr, 4, i + 4)]
  database_subnets = [for i, az in var.azs : cidrsubnet(var.vpc_cidr, 4, i + 8)]
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.16"

  name = var.name
  cidr = var.vpc_cidr
  azs  = var.azs

  public_subnets   = local.public_subnets
  private_subnets  = local.private_subnets
  database_subnets = local.database_subnets

  # NAT: 1 unico por padrao (custo); one_nat_gateway_per_az para HA
  enable_nat_gateway     = true
  single_nat_gateway     = var.single_nat_gateway
  one_nat_gateway_per_az = !var.single_nat_gateway

  enable_dns_hostnames = true
  enable_dns_support   = true

  # RDS: subnet group dedicado; sem rota para NAT/IGW
  create_database_subnet_group       = true
  create_database_subnet_route_table = true
  create_database_nat_gateway_route  = false

  # Flow logs desligados: custo de CloudWatch; documentado como evolucao
  enable_flow_log = false

  # Tags exigidas pelo EKS / AWS Load Balancer Controller para descobrir subnets
  public_subnet_tags = {
    "kubernetes.io/role/elb"                    = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"           = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }

  tags = var.tags
}
