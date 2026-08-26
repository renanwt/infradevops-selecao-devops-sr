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
