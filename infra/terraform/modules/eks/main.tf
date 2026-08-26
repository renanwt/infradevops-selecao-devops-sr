# ---------------------------------------------------------------------------
# EKS: cluster + 1 managed node group + addons essenciais.
#
# Decisoes:
#  - Versao em STANDARD_SUPPORT (extended support custa 6x no control plane).
#  - Nos EC2 (nao Fargate): DaemonSets (node-exporter) e metrics-server p/ HPA.
#  - VPC CNI com prefix delegation: t3.small nativo aceita 11 pods; com
#    prefixos /28 sobe para 110 -> viabiliza monitoring + app em nos pequenos.
#  - Endpoint publico do control plane restrito por CIDR (kubectl do dev/CI);
#    nos falam com o control plane pelo endpoint privado.
#  - IRSA habilitado (OIDC provider) para roles por workload.
# ---------------------------------------------------------------------------

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name               = var.name
  kubernetes_version = var.kubernetes_version

  vpc_id                   = var.vpc_id
  subnet_ids               = var.private_subnet_ids
  control_plane_subnet_ids = var.private_subnet_ids

  endpoint_public_access       = true
  endpoint_public_access_cidrs = var.public_access_cidrs
  endpoint_private_access      = true

  # quem roda o terraform vira cluster-admin (access entries API)
  enable_cluster_creator_admin_permissions = true
  authentication_mode                      = "API"

  enable_irsa = true

  # Logs do control plane: so audit/authenticator (custo CloudWatch)
  enabled_log_types                      = ["audit", "authenticator"]
  cloudwatch_log_group_retention_in_days = 7

  # KMS para secrets do etcd: desligado (evita custo de chave); documentar
  create_kms_key    = false
  encryption_config = null

  addons = {
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent    = true
      before_compute = true # precisa existir antes dos nos p/ max-pods correto
      configuration_values = jsonencode({
        env = {
          ENABLE_PREFIX_DELEGATION = "true"
          WARM_PREFIX_TARGET       = "1"
        }
      })
    }
    eks-pod-identity-agent = {
      most_recent = true
    }
    aws-ebs-csi-driver = {
      most_recent              = true
      service_account_role_arn = module.ebs_csi_irsa.arn
    }
  }

  eks_managed_node_groups = {
    default = {
      name           = "${var.name}-ng"
      ami_type       = "AL2023_x86_64_STANDARD"
      capacity_type  = "ON_DEMAND"
      instance_types = [var.node_instance_type]

      min_size     = var.node_min_size
      max_size     = var.node_max_size
      desired_size = var.node_desired_size

      metadata_options = {
        http_tokens                 = "required" # IMDSv2
        http_put_response_hop_limit = 1          # pods nao alcancam a role do no
      }

      labels = {
        role = "general"
      }
    }
  }

  # Permite ALB (na VPC) alcancar os pods nas portas altas e trafego intra-cluster
  node_security_group_additional_rules = {
    ingress_vpc_ephemeral = {
      description = "Ingress da VPC (ALB para pods) em portas efemeras"
      protocol    = "tcp"
      from_port   = 1024
      to_port     = 65535
      type        = "ingress"
      cidr_blocks = [var.vpc_cidr]
    }
  }

  tags = var.tags
}

# IRSA para o EBS CSI driver (PVC do Prometheus/Grafana)
module "ebs_csi_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
  version = "~> 6.0"

  name = "${var.name}-ebs-csi"

  attach_ebs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }

  tags = var.tags
}
