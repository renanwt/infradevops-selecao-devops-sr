# ---------------------------------------------------------------------------
# External Secrets Operator: sincroniza Secrets Manager -> Secret Kubernetes.
# Autentica na AWS via IRSA (role criada no 00-foundation).
# ---------------------------------------------------------------------------

resource "kubernetes_namespace_v1" "external_secrets" {
  metadata {
    name = "external-secrets"
    labels = {
      "pod-security.kubernetes.io/enforce" = "restricted"
    }
  }
}

resource "helm_release" "external_secrets" {
  name       = "external-secrets"
  namespace  = kubernetes_namespace_v1.external_secrets.metadata[0].name
  repository = "https://charts.external-secrets.io"
  chart      = "external-secrets"
  version    = var.external_secrets_chart_version

  wait    = true
  timeout = 600

  # O webhook mutating do ALB Controller intercepta a criacao de Services; se o
  # controller ainda nao estiver Ready, a instalacao falha ("no endpoints").
  depends_on = [helm_release.alb_controller]

  values = [yamlencode({
    installCRDs = true

    serviceAccount = {
      name = "external-secrets" # deve bater com a trust policy da role IRSA
      annotations = {
        "eks.amazonaws.com/role-arn" = local.foundation.external_secrets_role_arn
      }
    }

    # 1 replica de cada componente: cluster pequeno, sem HA
    replicaCount   = 1
    webhook        = { replicaCount = 1 }
    certController = { replicaCount = 1 }

    resources = {
      requests = { cpu = "20m", memory = "64Mi" }
      limits   = { memory = "128Mi" }
    }

    # exige PSS restricted
    securityContext = {
      runAsNonRoot             = true
      allowPrivilegeEscalation = false
      readOnlyRootFilesystem   = true
      capabilities             = { drop = ["ALL"] }
      seccompProfile           = { type = "RuntimeDefault" }
    }
  })]
}

# ClusterSecretStore via mini-chart local: `kubernetes_manifest` exigiria o
# CRD existir no momento do plan (falha no primeiro apply); Helm nao exige.
resource "helm_release" "cluster_secret_store" {
  name      = "cluster-secret-store"
  namespace = kubernetes_namespace_v1.external_secrets.metadata[0].name
  chart     = "${path.module}/charts/cluster-secret-store"

  values = [yamlencode({
    name   = "aws-secrets-manager"
    region = var.region
    serviceAccount = {
      name      = "external-secrets"
      namespace = kubernetes_namespace_v1.external_secrets.metadata[0].name
    }
  })]

  depends_on = [helm_release.external_secrets]
}
