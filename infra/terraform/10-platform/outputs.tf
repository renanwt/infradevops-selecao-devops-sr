output "cluster_name" {
  value = local.cluster_name
}

output "app_namespace" {
  value = kubernetes_namespace_v1.app.metadata[0].name
}
