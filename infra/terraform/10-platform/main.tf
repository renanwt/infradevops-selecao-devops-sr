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

# ---------------------------------------------------------------------------
# RBAC extra para o pipeline (grupo do access entry do GitHub Actions).
# AmazonEKSAdminPolicy (= ClusterRole admin) nao inclui CRDs; o chart cria um
# ExternalSecret, entao concedemos so esse recurso, so neste namespace.
# ---------------------------------------------------------------------------
resource "kubernetes_role_v1" "deployer_crds" {
  metadata {
    name      = "deployer-crds"
    namespace = kubernetes_namespace_v1.app.metadata[0].name
  }

  rule {
    api_groups = ["external-secrets.io"]
    resources  = ["externalsecrets"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }
}

resource "kubernetes_role_binding_v1" "deployer_crds" {
  metadata {
    name      = "deployer-crds"
    namespace = kubernetes_namespace_v1.app.metadata[0].name
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role_v1.deployer_crds.metadata[0].name
  }

  subject {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Group"
    name      = "${var.app_namespace}-deployers"
  }
}
