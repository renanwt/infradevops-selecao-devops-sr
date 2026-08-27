# ---------------------------------------------------------------------------
# Alert rules versionadas em ops/alerts/*.yaml (PrometheusRule).
# O Prometheus Operator carrega qualquer PrometheusRule do cluster
# (ruleSelectorNilUsesHelmValues=false no kube-prometheus-stack).
# ---------------------------------------------------------------------------

locals {
  alerts_dir  = "${path.module}/../../../ops/alerts"
  alert_files = fileset(local.alerts_dir, "*.yaml")
  alert_rules = { for f in local.alert_files : f => yamldecode(file("${local.alerts_dir}/${f}")) }
}

resource "kubernetes_manifest" "prometheus_rules" {
  for_each = local.alert_rules
  manifest = each.value

  depends_on = [helm_release.kube_prometheus_stack] # CRD PrometheusRule
}
