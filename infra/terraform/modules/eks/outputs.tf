output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  value     = module.eks.cluster_certificate_authority_data
  sensitive = true
}

output "cluster_version" {
  value = module.eks.cluster_version
}

output "oidc_provider_arn" {
  description = "ARN do OIDC provider (base do IRSA)."
  value       = module.eks.oidc_provider_arn
}

output "oidc_provider" {
  description = "URL do issuer sem https:// (para conditions de trust policy)."
  value       = module.eks.oidc_provider
}

output "node_security_group_id" {
  description = "SG dos nos - usado pelo SG do RDS para liberar 5432."
  value       = module.eks.node_security_group_id
}

output "cluster_security_group_id" {
  value = module.eks.cluster_security_group_id
}

output "cluster_arn" {
  value = module.eks.cluster_arn
}
