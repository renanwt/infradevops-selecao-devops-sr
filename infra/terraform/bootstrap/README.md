# bootstrap

Cria o bucket S3 do state remoto. Roda **uma vez**, com state local (o `terraform.tfstate` deste diretório é ignorado pelo git, mas é pequeno e pode ser recriado com `terraform import` se perdido).

```sh
cd infra/terraform/bootstrap
terraform init
terraform apply
terraform output backend_config_example   # cole nos outros stacks
```

Lock de state usa o mecanismo nativo do S3 (`use_lockfile = true`, Terraform ≥ 1.10) — sem DynamoDB.

Custo: ~USD 0 (state tem poucos KB).
