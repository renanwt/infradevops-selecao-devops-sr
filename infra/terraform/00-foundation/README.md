# 00-foundation

Rede, EKS, RDS, ECR e IAM. Tudo que muda raramente e não depende do cluster existir.

```sh
cd infra/terraform/00-foundation
cp terraform.tfvars.example terraform.tfvars   # ajuste budget_email etc.
terraform init
terraform plan
terraform apply                                # ~15-20 min (EKS)

aws eks update-kubeconfig --name comments-api-dev --region us-east-1
kubectl get nodes
```

## Módulos

| Módulo | Cria |
|---|---|
| `network` | VPC, subnets public/private/database em 2 AZs, 1 NAT, tags EKS/ALB |
| `ecr` | repositório da imagem (imutável, scan on push, lifecycle) |
| `eks` | cluster 1.35, node group t3.small x2, IRSA, addons (vpc-cni c/ prefix delegation, ebs-csi) |
| `rds` | PostgreSQL 16 db.t4g.micro privado, senha gerenciada no Secrets Manager |
| `iam` | roles IRSA (External Secrets, ALB Controller) e role OIDC do GitHub Actions |

## Outputs usados adiante

- `10-platform`: `cluster_name`, `oidc_provider_arn`, `external_secrets_role_arn`, `alb_controller_role_arn`, `vpc_id`
- Helm chart da app: `rds_address`, `rds_db_name`, `rds_master_user_secret_arn`, `ecr_repository_url`
- GitHub Actions: `github_actions_role_arn`, `ecr_repository_url`, `cluster_name`

## Custo estimado (us-east-1, ligado)

| Recurso | USD/h |
|---|---|
| EKS control plane | 0,10 |
| 2x t3.small | 0,042 |
| NAT Gateway | 0,045 (+ dados) |
| RDS db.t4g.micro | 0 (free tier) / 0,016 |
| EBS, EIP, logs | ~0,01 |
| **Total** | **~0,20/h ≈ 4,80/dia** |

Desligue ao terminar cada sessão de testes: `terraform destroy`.

## Destroy

```sh
# 1) destrua o 10-platform antes (ALBs criados pelo controller ficariam órfãos)
# 2) depois:
terraform destroy
```
