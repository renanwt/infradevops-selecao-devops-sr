# ---------------------------------------------------------------------------
# 10-platform: componentes que rodam DENTRO do cluster (Helm releases).
#
# Separado do 00-foundation porque os providers kubernetes/helm precisam de um
# cluster existente para inicializar - no mesmo stack o primeiro apply falha.
# ---------------------------------------------------------------------------

# Outputs do foundation (cluster, roles IRSA, VPC, RDS).
data "terraform_remote_state" "foundation" {
  backend = "s3"
  config = {
    bucket = var.tfstate_bucket
    key    = "foundation/terraform.tfstate"
    region = var.region
  }
}

locals {
  foundation   = data.terraform_remote_state.foundation.outputs
  cluster_name = local.foundation.cluster_name
}

data "aws_eks_cluster" "this" {
  name = local.cluster_name
}

# Namespace da aplicacao com Pod Security Standards "restricted":
# rejeita pods root, privilegiados ou sem drop de capabilities.
resource "kubernetes_namespace_v1" "app" {
  metadata {
    name = var.app_namespace
    labels = {
      "pod-security.kubernetes.io/enforce" = "restricted"
      "pod-security.kubernetes.io/warn"    = "restricted"
    }
  }
}
