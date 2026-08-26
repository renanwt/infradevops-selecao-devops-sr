# 10-platform

Componentes instalados **dentro** do cluster via Helm: External Secrets Operator, AWS Load Balancer Controller, metrics-server, kube-prometheus-stack. Depende do `00-foundation` já aplicado (lê os outputs pelo state remoto).

```sh
cd infra/terraform/10-platform
terraform init
terraform apply
```

Autenticação no cluster usa `aws eks get-token` (token de 15 min), então o state não guarda credenciais do Kubernetes.

## Destroy

Destrua este stack **antes** do `00-foundation`: o ALB Controller precisa estar vivo para remover os load balancers que criou.
