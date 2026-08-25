output "repository_url" {
  description = "URL para docker push/pull (<account>.dkr.ecr.<region>.amazonaws.com/<name>)."
  value       = aws_ecr_repository.this.repository_url
}

output "repository_arn" {
  value = aws_ecr_repository.this.arn
}

output "repository_name" {
  value = aws_ecr_repository.this.name
}
