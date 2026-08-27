# Custos

## Estimativa (us-east-1, ambiente ligado)

| Recurso | Dimensionamento | USD/h | USD/dia |
|---|---|---|---|
| EKS control plane | 1 cluster (versão em standard support) | 0,100 | 2,40 |
| EC2 node group | 2× t3.small on-demand | 0,042 | 1,00 |
| NAT Gateway | 1 (compartilhado pelas 2 AZs) + dados | 0,045 | 1,08 |
| ALB | 1 (criado pelo Ingress) + LCU | 0,023 | 0,54 |
| RDS PostgreSQL | db.t4g.micro single-AZ, 20 GiB gp3 | 0 (free tier 750 h/mês) — 0,016 fora dele | 0–0,38 |
| EBS | 2× 20 GiB (nós) + 5 GiB + 1 GiB (PVCs) gp3 | ~0,005 | 0,12 |
| KMS | 1 chave (secrets do EKS) | ~0,001 | 0,03 |
| CloudWatch Logs | audit/authenticator EKS (7 d) + logs do RDS | ~0,005 | 0,12 |
| Secrets Manager | 1 secret gerenciado (RDS) | 0,0006 | 0,01 |
| ECR / S3 (state) | < 1 GB | ~0 | ~0 |
| **Total** | | **≈ 0,22** | **≈ 5,30** |

Itens sem custo: IAM, OIDC, Budgets (2 primeiros), ESO/ALB Controller/metrics-server/Prometheus (rodam nos nós).

## Medidas de economia adotadas

| Medida | Economia | Trade-off (e como reverter) |
|---|---|---|
| Kubernetes em *standard support* (1.35) | evita 6× no control plane (USD 0,60/h em extended) | — |
| 1 NAT Gateway em vez de 1/AZ | ~USD 32/mês | perda de saída se a AZ do NAT cair; `single_nat_gateway=false` |
| t3.small + VPC CNI prefix delegation | metade do t3.medium | ~80 % de memória em uso com monitoring; `node_instance_type` |
| RDS single-AZ, sem Enhanced Monitoring / Performance Insights | ~USD 15/mês + CloudWatch | failover manual; `db_multi_az=true` |
| Prometheus retenção 2 d / 4 GB, PVCs pequenos | EBS | painéis de 30 d só fiéis com retenção maior (Thanos/AMP) |
| Grafana/Prometheus via `port-forward` (ClusterIP) | 1 ALB a menos (~USD 16/mês) | sem URL pública para dashboards |
| Sem Container Insights, sem AMP/AMG, sem WAF | dezenas de USD/mês | menos telemetria gerenciada |
| ECR lifecycle (10 imagens), logs 7 d, state lifecycle 30 d | storage | — |
| `terraform destroy` fora das janelas de teste | ~USD 5/dia | recriar leva ~25 min |
| AWS Budget USD 15 com alerta em 80 %/100 % | — | requer e-mail no tfvars |

## Custo real (Cost Explorer)

O Cost Explorer consolida com ~24 h de atraso. Comando para atualizar esta seção:

```sh
aws ce get-cost-and-usage --time-period Start=2026-08-25,End=2026-08-29 --granularity DAILY \
  --metrics UnblendedCost --group-by Type=DIMENSION,Key=SERVICE --output table
```

| Data | USD | Observação |
|---|---|---|
| 2026-08-25 | 0,01 | bootstrap (S3) |
| 2026-08-26 | *(pendente — CE)* | foundation + platform criados ~19:30 UTC; cluster ligado desde então |
| 2026-08-27 | *(pendente — CE)* | testes de HPA, rollback, restore (instância RDS temporária ~15 min) |

Estimativa do período total do desafio (≈ 2 dias de ambiente ligado): **≈ USD 10–12**, dentro do orçamento-alvo.
