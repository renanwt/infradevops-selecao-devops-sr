# ---------------------------------------------------------------------------
# Dashboards Grafana versionados em ops/grafana/*.json.
# O sidecar do Grafana (kube-prometheus-stack) observa ConfigMaps com o label
# grafana_dashboard=1 em qualquer namespace e provisiona automaticamente.
# Fonte da verdade e o arquivo no repo: editar no Grafana e nao salvar aqui = perde.
# ---------------------------------------------------------------------------

locals {
  dashboards_dir = "${path.module}/../../../ops/grafana"
  dashboards     = fileset(local.dashboards_dir, "*.json")
}

resource "kubernetes_config_map_v1" "grafana_dashboards" {
  for_each = local.dashboards

  metadata {
    name      = "grafana-dashboard-${trimsuffix(each.value, ".json")}"
    namespace = kubernetes_namespace_v1.monitoring.metadata[0].name
    labels = {
      grafana_dashboard = "1"
    }
    annotations = {
      grafana_folder = "Comments API"
    }
  }

  data = {
    (each.value) = file("${local.dashboards_dir}/${each.value}")
  }
}
