# ---------------------------------------------------------------------------
# ECR: repositorio de imagens da API.
# ---------------------------------------------------------------------------

resource "aws_ecr_repository" "this" {
  name                 = var.name
  image_tag_mutability = "IMMUTABLE" # tag sha-<commit> nunca e sobrescrita

  image_scanning_configuration {
    scan_on_push = true # scan basico da AWS, complementa o Trivy do pipeline
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  # permite `terraform destroy` com imagens dentro (desafio); producao: false
  force_delete = var.force_delete

  tags = var.tags
}

# Mantem poucas imagens: custo de storage e higiene.
resource "aws_ecr_lifecycle_policy" "this" {
  repository = aws_ecr_repository.this.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Remove imagens sem tag apos 1 dia"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 1
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Mantem apenas as ultimas ${var.keep_last_images} imagens"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = var.keep_last_images
        }
        action = { type = "expire" }
      },
    ]
  })
}
