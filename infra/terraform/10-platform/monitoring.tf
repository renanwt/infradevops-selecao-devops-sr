# ---------------------------------------------------------------------------
# kube-prometheus-stack: Prometheus Operator + Prometheus + Alertmanager +
# Grafana + kube-state-metrics + node-exporter.
#
# Dimensionado para 2x t3.small: 1 replica de tudo, retencao curta, PVC pequeno.
# Dashboards e alertas da aplicacao sao versionados em ops/ e entram pelo chart
# da app (ConfigMap com label grafana_dashboard / PrometheusRule).
# ---------------------------------------------------------------------------

resource "kubernetes_namespace_v1" "monitoring" {
  metadata {
    name = "monitoring"
    labels = {
      # node-exporter usa hostNetwork/hostPID: nao cabe em "restricted"
      "pod-security.kubernetes.io/enforce" = "privileged"
      "pod-security.kubernetes.io/warn"    = "baseline"
    }
  }
}

# StorageClass gp3 (mais barato e rapido que o gp2 padrao do EKS) para os PVCs.
resource "kubernetes_storage_class_v1" "gp3" {
  metadata {
    name = "gp3"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
  }
  storage_provisioner    = "ebs.csi.aws.com"
  reclaim_policy         = "Delete"
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = true
  parameters = {
    type      = "gp3"
    encrypted = "true"
  }
}

# Remove o "default" do gp2 legado para o gp3 ser o unico padrao.
resource "kubernetes_annotations" "gp2_not_default" {
  api_version = "storage.k8s.io/v1"
  kind        = "StorageClass"
  metadata {
    name = "gp2"
  }
  annotations = {
    "storageclass.kubernetes.io/is-default-class" = "false"
  }
  force = true
}

resource "random_password" "grafana_admin" {
  length  = 24
  special = false
}

resource "kubernetes_secret_v1" "grafana_admin" {
  metadata {
    name      = "grafana-admin"
    namespace = kubernetes_namespace_v1.monitoring.metadata[0].name
  }
  data = {
    admin-user     = "admin"
    admin-password = random_password.grafana_admin.result
  }
}

resource "helm_release" "kube_prometheus_stack" {
  name       = "kube-prometheus-stack"
  namespace  = kubernetes_namespace_v1.monitoring.metadata[0].name
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = var.kube_prometheus_stack_chart_version

  wait    = true
  timeout = 900

  depends_on = [
    kubernetes_storage_class_v1.gp3,
    helm_release.alb_controller, # webhook de Services
  ]

  values = [yamlencode({
    fullnameOverride = "kps"

    # --- componentes do control plane que o EKS nao expoe: desliga scrape e alertas ---
    kubeEtcd              = { enabled = false }
    kubeControllerManager = { enabled = false }
    kubeScheduler         = { enabled = false }
    kubeProxy             = { enabled = false } # metrics bind em 127.0.0.1 no EKS

    defaultRules = {
      rules = {
        etcd                   = false
        kubeControllerManager  = false
        kubeSchedulerAlerting  = false
        kubeSchedulerRecording = false
        kubeProxy              = false
      }
    }

    # --- Prometheus ---
    prometheus = {
      prometheusSpec = {
        replicas           = 1
        retention          = "2d"
        retentionSize      = "4GB"
        scrapeInterval     = "30s"
        evaluationInterval = "30s"

        # Descobre ServiceMonitor/PodMonitor/PrometheusRule de QUALQUER namespace,
        # sem exigir o label de release do Helm (padrao do chart e restritivo).
        serviceMonitorSelectorNilUsesHelmValues = false
        podMonitorSelectorNilUsesHelmValues     = false
        ruleSelectorNilUsesHelmValues           = false
        probeSelectorNilUsesHelmValues          = false

        resources = {
          requests = { cpu = "150m", memory = "400Mi" }
          limits   = { memory = "900Mi" }
        }

        storageSpec = {
          volumeClaimTemplate = {
            spec = {
              storageClassName = "gp3"
              accessModes      = ["ReadWriteOnce"]
              resources        = { requests = { storage = "5Gi" } }
            }
          }
        }
      }
    }

    # --- Alertmanager ---
    alertmanager = {
      alertmanagerSpec = {
        replicas  = 1
        retention = "48h"
        resources = {
          requests = { cpu = "10m", memory = "32Mi" }
          limits   = { memory = "96Mi" }
        }
        storage = {
          volumeClaimTemplate = {
            spec = {
              storageClassName = "gp3"
              accessModes      = ["ReadWriteOnce"]
              resources        = { requests = { storage = "1Gi" } }
            }
          }
        }
      }
      # Receiver "null": alertas ficam visiveis na UI; plugar Slack/PagerDuty
      # e trocar o receiver (documentado em ops/runbooks).
      config = {
        global = { resolve_timeout = "5m" }
        route = {
          receiver        = "null"
          group_by        = ["alertname", "namespace"]
          group_wait      = "30s"
          group_interval  = "5m"
          repeat_interval = "12h"
          routes = [
            { receiver = "null", matchers = ["alertname = Watchdog"] },
          ]
        }
        receivers = [{ name = "null" }]
      }
    }

    # --- Grafana ---
    grafana = {
      replicas = 1
      admin = {
        existingSecret = kubernetes_secret_v1.grafana_admin.metadata[0].name
        userKey        = "admin-user"
        passwordKey    = "admin-password"
      }
      persistence = { enabled = false } # dashboards vem de ConfigMap versionado
      service     = { type = "ClusterIP" }

      # Exposto no MESMO ALB da API (IngressGroup comments-api) em /grafana.
      # group.order menor = regra avaliada antes do "/" da API.
      ingress = {
        enabled          = true
        ingressClassName = "alb"
        path             = "/grafana"
        pathType         = "Prefix"
        annotations = {
          "alb.ingress.kubernetes.io/group.name"       = "comments-api"
          "alb.ingress.kubernetes.io/group.order"      = "10"
          "alb.ingress.kubernetes.io/scheme"           = "internet-facing"
          "alb.ingress.kubernetes.io/target-type"      = "ip"
          "alb.ingress.kubernetes.io/healthcheck-path" = "/grafana/api/health"
          "alb.ingress.kubernetes.io/listen-ports"     = "[{\"HTTP\": 80}]"
        }
      }
      # probes no sub-path
      livenessProbe = {
        httpGet             = { path = "/grafana/api/health", port = 3000 }
        initialDelaySeconds = 60
        periodSeconds       = 10
        timeoutSeconds      = 10
        failureThreshold    = 10
      }
      readinessProbe = {
        httpGet          = { path = "/grafana/api/health", port = 3000 }
        periodSeconds    = 10
        timeoutSeconds   = 10
        failureThreshold = 6
      }
      resources = {
        requests = { cpu = "100m", memory = "256Mi" }
        limits   = { memory = "512Mi" }
      }
      sidecar = {
        dashboards = {
          enabled          = true
          label            = "grafana_dashboard"
          labelValue       = "1"
          searchNamespace  = "ALL" # ConfigMaps do namespace da app
          folderAnnotation = "grafana_folder"
          provider         = { foldersFromFilesStructure = true }
        }
        datasources = { enabled = true }
      }
      "grafana.ini" = {
        analytics = { check_for_updates = false, reporting_enabled = false }
        users     = { default_theme = "dark" }
        server = {
          root_url            = "%(protocol)s://%(domain)s/grafana/"
          serve_from_sub_path = true
        }
        # Leitura anonima (Viewer): o avaliador abre o dashboard sem login.
        # Edicao/admin continuam exigindo a senha do Secret grafana-admin.
        "auth.anonymous" = {
          enabled  = true
          org_role = "Viewer"
        }
      }
    }

    # --- exporters ---
    kube-state-metrics = {
      resources = {
        requests = { cpu = "10m", memory = "32Mi" }
        limits   = { memory = "128Mi" }
      }
    }
    prometheus-node-exporter = {
      resources = {
        requests = { cpu = "10m", memory = "24Mi" }
        limits   = { memory = "64Mi" }
      }
    }
    prometheusOperator = {
      resources = {
        requests = { cpu = "50m", memory = "64Mi" }
        limits   = { memory = "192Mi" }
      }
    }
  })]
}
