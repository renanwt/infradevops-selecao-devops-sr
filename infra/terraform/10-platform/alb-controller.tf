# ---------------------------------------------------------------------------
# AWS Load Balancer Controller: transforma Ingress (class alb) em ALB real.
# Autentica na AWS via IRSA (role criada no 00-foundation).
# ---------------------------------------------------------------------------

resource "helm_release" "alb_controller" {
  name       = "aws-load-balancer-controller"
  namespace  = "kube-system"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = var.alb_controller_chart_version

  wait    = true
  timeout = 600

  values = [yamlencode({
    clusterName = local.cluster_name
    region      = var.region
    vpcId       = local.foundation.vpc_id

    serviceAccount = {
      create = true
      name   = "aws-load-balancer-controller" # bate com a trust policy IRSA
      annotations = {
        "eks.amazonaws.com/role-arn" = local.foundation.alb_controller_role_arn
      }
    }

    replicaCount = 1 # cluster pequeno; producao: 2

    resources = {
      requests = { cpu = "50m", memory = "128Mi" }
      limits   = { memory = "256Mi" }
    }

    # IngressClass "alb" (o Ingress da app usa ingressClassName: alb)
    createIngressClassResource = true
    ingressClass               = "alb"
    ingressClassParams = {
      create = true
      spec = {
        scheme = "internet-facing"
      }
    }
    enableShield = false
    enableWaf    = false
    enableWafv2  = false
  })]
}

# ---------------------------------------------------------------------------
# metrics-server: CPU/memoria por pod para o HPA e `kubectl top`.
# ---------------------------------------------------------------------------

resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  namespace  = "kube-system"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  version    = var.metrics_server_chart_version

  wait    = true
  timeout = 300

  values = [yamlencode({
    replicas = 1

    resources = {
      requests = { cpu = "20m", memory = "64Mi" }
      limits   = { memory = "128Mi" }
    }

    # HPA reage mais rapido com scrape de 15s (padrao 60s)
    args = ["--metric-resolution=15s"]
  })]
}
