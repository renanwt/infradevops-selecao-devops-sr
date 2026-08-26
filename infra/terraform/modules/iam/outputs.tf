output "external_secrets_role_arn" {
  description = "Annotation eks.amazonaws.com/role-arn do SA external-secrets."
  value       = module.external_secrets_irsa.arn
}

output "alb_controller_role_arn" {
  description = "Annotation eks.amazonaws.com/role-arn do SA aws-load-balancer-controller."
  value       = module.alb_controller_irsa.arn
}

output "github_actions_role_arn" {
  description = "role-to-assume no aws-actions/configure-aws-credentials."
  value       = aws_iam_role.github_actions.arn
}
