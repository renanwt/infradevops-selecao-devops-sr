output "state_bucket" {
  description = "Bucket S3 do state remoto."
  value       = aws_s3_bucket.tfstate.bucket
}

output "region" {
  value = var.region
}

output "backend_config_example" {
  description = "Bloco backend para os demais stacks."
  value       = <<-EOT
    terraform {
      backend "s3" {
        bucket       = "${aws_s3_bucket.tfstate.bucket}"
        key          = "<stack>/terraform.tfstate"
        region       = "${var.region}"
        encrypt      = true
        use_lockfile = true
      }
    }
  EOT
}
