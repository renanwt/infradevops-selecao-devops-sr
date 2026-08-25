# COMMENTS.md — Decisões, experimentos e testes

Registro vivo da execução do desafio. O plano original está em [plano.md](plano.md); este arquivo documenta o que de fato aconteceu, o que mudou em relação ao plano e por quê.

---

## 1. Decisões técnicas

Formato: **Decisão** · Alternativas · Motivo · Trade-off aceito.

| # | Decisão | Alternativas | Motivo | Trade-off aceito |
|---|---|---|---|---|
| D-01 | AWS + EKS + RDS PostgreSQL | GCP/GKE, ECS Fargate | EKS é o preferencial do README; bônus (HPA, Helm rollback, PrometheusRule) dependem de Kubernetes | Custo do control plane (USD 0,10/h) — mitigado com `terraform destroy` fora das janelas de teste |
| D-02 | Python 3.12 + FastAPI + SQLAlchemy async + Alembic | Flask, Go/Gin, Node/Fastify | Validação via Pydantic, OpenAPI automático, migrações versionadas | — |
| D-03 | `/health` (liveness) separado de `/ready` (readiness com `SELECT 1`) | Um único `/health` checando DB | Liveness que depende do DB derruba pods em massa em oscilação do banco | Um endpoint a mais para documentar |
| D-04 | Secrets Manager + External Secrets Operator via IRSA | SSM Parameter Store, Secrets Store CSI | Rotação nativa, app agnóstico de AWS (recebe `Secret` K8s) | Um operador adicional no cluster |
| D-05 | Terraform em 2 stacks (`00-foundation`, `10-platform`) | Stack único | Evita provider `kubernetes`/`helm` sem endpoint no primeiro apply; separa ciclos de vida | Dois `apply` em vez de um |
| D-06 | GitHub Actions com OIDC | Access keys em secrets do repo | Sem credenciais de longa duração; least privilege | — |
| D-07 | kube-prometheus-stack no cluster | Amazon Managed Prometheus/Grafana | Gratuito, dashboards/alertas versionados via ConfigMap/PrometheusRule | Consome recursos dos nós; retenção curta (2d) |

> Novas decisões são adicionadas aqui conforme surgem. Mudanças em relação ao desenho inicial são marcadas com **(revisão)**.

---

## 2. Log de experimentos

Formato: data · o que foi tentado · resultado · o que foi feito a partir disso.

| Data | Experimento | Resultado | Ação |
|---|---|---|---|
| 2026-08-25 | Elaboração do plano de arquitetura antes de qualquer código | Plano em `plano.md` com roteiro de 42 commits em etapas A–G | Seguir o roteiro; registrar desvios aqui |

---

## 3. Arquiteturas tentadas e abandonadas

_(nenhuma até o momento — a arquitetura inicial é a descrita em `plano.md`, seção 3)_

---

## 4. Testes realizados

| Etapa | Tipo | Ferramenta | Resultado | Evidência |
|---|---|---|---|---|
| — | — | — | — | — |

---

## 5. Registro de tempo

| Etapa | Atividade | Tempo aprox. |
|---|---|---|
| Planejamento | Leitura do desafio, definição da arquitetura, escrita do `plano.md` | 1h30 |

---

## 6. Uso de IA, templates e referências

- **IA**: Claude Code (Anthropic) — elaboração do plano, revisão de código e redação de documentação. Toda decisão e comando são revisados manualmente pelo autor antes de serem aplicados.
- **Templates / módulos**: `terraform-aws-modules/{vpc,eks,rds,iam}`, charts oficiais `external-secrets`, `aws-load-balancer-controller`, `kube-prometheus-stack`, `prometheus-postgres-exporter`.
- **Referências**: AWS EKS Best Practices Guide; Google SRE Workbook (Alerting on SLOs); documentação FastAPI, SQLAlchemy, Alembic, Prometheus client Python, External Secrets Operator.

---

## 7. Ideias de evolução (com mais tempo)

- OpenTelemetry tracing (FastAPI + asyncpg) → Grafana Tempo.
- Assinatura de imagens com cosign + admissão via Kyverno.
- GitOps com Argo CD.
- RDS Multi-AZ + read replica / Aurora Serverless v2.
- Karpenter e instâncias Spot para não-prod.
- Rate limiting e cache (ElastiCache) na listagem.
- Testes de contrato com schemathesis.
