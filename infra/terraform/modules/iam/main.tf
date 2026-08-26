# ---------------------------------------------------------------------------
# IAM: uma role por identidade, cada uma com o minimo necessario.
#
#  - external-secrets (IRSA): ler o secret do RDS no Secrets Manager.
#  - aws-load-balancer-controller (IRSA): criar/gerir ALBs (policy oficial).
#  - github-actions (OIDC): push no ECR, describe do cluster, plan do Terraform.
#
# A aplicacao NAO tem role: ela le a DATABASE_URL de um Secret do Kubernetes
# (materializado pelo ESO) e nao chama nenhuma API da AWS.
# ---------------------------------------------------------------------------

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# --- External Secrets Operator ---------------------------------------------
module "external_secrets_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
  version = "~> 6.0"

  name = "${var.name}-external-secrets"

  oidc_providers = {
    main = {
      provider_arn               = var.oidc_provider_arn
      namespace_service_accounts = ["external-secrets:external-secrets"]
    }
  }

  policies = {
    secrets = aws_iam_policy.external_secrets.arn
  }

  tags = var.tags
}

resource "aws_iam_policy" "external_secrets" {
  name        = "${var.name}-external-secrets"
  description = "Leitura dos secrets da aplicacao"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadAppSecrets"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
        ]
        Resource = var.secret_arns
      },
    ]
  })

  tags = var.tags
}

# --- AWS Load Balancer Controller ------------------------------------------
module "alb_controller_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
  version = "~> 6.0"

  name = "${var.name}-alb-controller"

  attach_load_balancer_controller_policy = true

  oidc_providers = {
    main = {
      provider_arn               = var.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }

  tags = var.tags
}

# --- GitHub Actions (OIDC, sem chaves estaticas) ---------------------------
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  # AWS valida o certificado do GitHub pela raiz confiavel; o thumbprint e
  # obrigatorio na API mas nao e mais usado para validacao.
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]

  tags = var.tags
}

data "aws_iam_policy_document" "github_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Apenas este repositorio: branch main (deploy/apply) e pull requests (plan).
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "repo:${var.github_repository}:ref:refs/heads/main",
        "repo:${var.github_repository}:pull_request",
        "repo:${var.github_repository}:environment:infra-apply",
      ]
    }
  }
}

resource "aws_iam_role" "github_actions" {
  name                 = "${var.name}-github-actions"
  assume_role_policy   = data.aws_iam_policy_document.github_trust.json
  max_session_duration = 3600

  tags = var.tags
}

data "aws_iam_policy_document" "github_actions" {
  # ECR: login + push somente no repositorio da API
  statement {
    sid       = "EcrAuth"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"] # a acao nao suporta restricao por recurso
  }
  statement {
    sid    = "EcrPush"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage",
      "ecr:DescribeImages",
    ]
    resources = [var.ecr_repository_arn]
  }

  # EKS: gerar kubeconfig
  statement {
    sid       = "EksDescribe"
    effect    = "Allow"
    actions   = ["eks:DescribeCluster"]
    resources = [var.eks_cluster_arn]
  }

  # Terraform plan em PR: state (leitura + lockfile) no bucket
  statement {
    sid    = "TfState"
    effect = "Allow"
    actions = [
      "s3:ListBucket",
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    resources = [
      "arn:aws:s3:::${var.tfstate_bucket}",
      "arn:aws:s3:::${var.tfstate_bucket}/*",
    ]
  }
}

resource "aws_iam_policy" "github_actions" {
  name   = "${var.name}-github-actions"
  policy = data.aws_iam_policy_document.github_actions.json
  tags   = var.tags
}

resource "aws_iam_role_policy_attachment" "github_actions" {
  role       = aws_iam_role.github_actions.name
  policy_arn = aws_iam_policy.github_actions.arn
}

# ReadOnly para o `terraform plan` conseguir refrescar o state
resource "aws_iam_role_policy_attachment" "github_actions_readonly" {
  role       = aws_iam_role.github_actions.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

# Opcional: permite `terraform apply` pelo pipeline. Desligado por padrao -
# a role fica somente-leitura + ECR/EKS e o apply e feito pelo operador.
resource "aws_iam_role_policy_attachment" "github_actions_apply" {
  count      = var.github_actions_can_apply ? 1 : 0
  role       = aws_iam_role.github_actions.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# Acesso ao cluster para `helm upgrade`. Escopo: namespace da aplicacao.
resource "aws_eks_access_entry" "github_actions" {
  cluster_name  = var.eks_cluster_name
  principal_arn = aws_iam_role.github_actions.arn
  type          = "STANDARD"

  tags = var.tags
}

resource "aws_eks_access_policy_association" "github_actions" {
  cluster_name  = var.eks_cluster_name
  principal_arn = aws_iam_role.github_actions.arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSAdminPolicy"

  access_scope {
    type       = "namespace"
    namespaces = [var.app_namespace]
  }

  depends_on = [aws_eks_access_entry.github_actions]
}
