output "endpoint" {
  description = "host:porta"
  value       = aws_db_instance.this.endpoint
}

output "address" {
  description = "Hostname do RDS."
  value       = aws_db_instance.this.address
}

output "port" {
  value = aws_db_instance.this.port
}

output "db_name" {
  value = aws_db_instance.this.db_name
}

output "master_username" {
  value = aws_db_instance.this.username
}

output "master_user_secret_arn" {
  description = "Secret (Secrets Manager) com username/password gerenciado pela AWS."
  value       = aws_db_instance.this.master_user_secret[0].secret_arn
}

output "security_group_id" {
  value = aws_security_group.this.id
}

output "instance_arn" {
  value = aws_db_instance.this.arn
}
