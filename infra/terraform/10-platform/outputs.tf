output "cluster_name" {
  value = local.cluster_name
}

output "app_namespace" {
  value = kubernetes_namespace_v1.app.metadata[0].name
}

output "cluster_secret_store" {
  description = "Nome do ClusterSecretStore para usar nos ExternalSecrets."
  value       = "aws-secrets-manager"
}

output "grafana_access" {
  description = "Como acessar o Grafana (ClusterIP, sem custo de LB)."
  value       = <<-EOT
    kubectl -n monitoring port-forward svc/kps-grafana 3000:80
    # http://localhost:3000  user: admin
    kubectl -n monitoring get secret grafana-admin -o jsonpath='{.data.admin-password}' | base64 -d
  EOT
}

output "prometheus_access" {
  value = "kubectl -n monitoring port-forward svc/kps-prometheus 9090:9090"
}
