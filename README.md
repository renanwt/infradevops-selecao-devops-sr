# Comments API — desafio DevOps Sr (AWS · EKS · FastAPI · RDS)

API REST de comentários com persistência em RDS PostgreSQL, rodando em EKS, provisionada por Terraform, entregue por GitHub Actions (build → scan → package → deploy) e observada por Prometheus/Grafana com SLOs formais.

> Enunciado original: [docs/desafio.md](docs/desafio.md) · Decisões, experimentos e testes: [COMMENTS.md](COMMENTS.md) · Evidências: [docs/evidencias/](docs/evidencias/)

## Arquitetura

```
GitHub Actions --OIDC--> AWS us-east-1
  ci:     lint/test > build > Trivy+Checkov > push ECR
  deploy: helm upgrade --atomic > smoke > evidência

                +- VPC 10.0.0.0/16 · 2 AZs -------------------------------------------------------------+
                |                                                                                       |
                |            +------------------------+   +------------------+                          |
 Internet ----->| public     | ALB (Ingress class)    |   | NAT Gateway x1   |                          |
                |            +-----------+------------+   +------------------+                          |
                |                        |                                                              |
                | private    +-----------v- EKS 1.35 · 2x t3.small -----------------------------------+ |
                |            | ns comments          comments-api x2..5 (HPA) · PDB · NetworkPolicy    | |
                |            |                      ExternalSecret -> Secret(DATABASE_URL)            | |
                |            |                      postgres_exporter                                 | |
                |            | ns monitoring        Prometheus · Grafana · Alertmanager               | |
                |            | ns external-secrets  ESO (IRSA) --> Secrets Manager                    | |
                |            | kube-system          ALB Controller (IRSA) · metrics-server            | |
                |            +----------------------------+-------------------------------------------+ |
                |                                         | 5432 · SG dos nós > SG do RDS               |
                | database   +----------------------------v- RDS PostgreSQL 16 · db.t4g.micro --------+ |
                |            | privado (subnet sem rota p/ internet) · TLS · KMS                      | |
                |            | senha gerenciada pela AWS > Secrets Manager                            | |
                |            +------------------------------------------------------------------------+ |
                |                                                                                       |
                +---------------------------------------------------------------------------------------+
```

| Camada | Escolha | Por quê (resumo; detalhes em COMMENTS.md) |
|---|---|---|
| API | Python 3.12 · FastAPI · SQLAlchemy async · Alembic | validação Pydantic, OpenAPI, migrações versionadas como Helm hook |
| Container | `python:3.12-slim` multi-stage, uid 10001, rootfs read-only | 300 MB, sem pip/compiladores, Trivy limpo |
| Compute | EKS 1.35, 2× t3.small, VPC CNI prefix delegation | preferencial no desafio; 110 pods/nó em vez de 11 |
| Banco | RDS PostgreSQL 16 `db.t4g.micro`, senha gerenciada pela AWS | free tier; credencial nunca passa pelo Terraform |
| Segredos | Secrets Manager → External Secrets Operator (IRSA) → Secret K8s | app agnóstica de nuvem; uma única identidade lê o secret |
| Rede | 3 camadas de subnets; RDS sem rota para internet; NetworkPolicy aplicada | menor superfície: só o ALB é público |
| IaC | Terraform em 3 stacks (`bootstrap`, `00-foundation`, `10-platform`) | providers k8s/helm precisam do cluster existir |
| CI/CD | GitHub Actions + OIDC; ECR imutável; `helm --atomic` | sem chaves estáticas; imagem escaneada = publicada; rollback automático |
| Observabilidade | kube-prometheus-stack; dashboard e alertas em `ops/` | SLO 99,5 % / p95 < 300 ms; alertas por burn rate multi-window |

## Endpoints

| Método | Rota | Descrição |
|---|---|---|
| `POST` | `/api/comment/new` | cria comentário `{email, comment, content_id}` → 201 |
| `GET` | `/api/comment/list/{content_id}?limit=&offset=` | lista por matéria (mais recente primeiro) |
| `GET` | `/health` | liveness (processo vivo) |
| `GET` | `/ready` | readiness (`SELECT 1` no banco → 503 se indisponível) |
| `GET` | `/metrics` | Prometheus text format |
| `GET` | `/docs` | OpenAPI |

Collection Postman com testes: [docs/postman/](docs/postman/).

## Rodar localmente

Pré-requisitos: Docker. (Python 3.11+ só para desenvolver.)

```sh
docker compose up --build            # postgres → migração → api em http://localhost:8000
curl -X POST localhost:8000/api/comment/new -H 'content-type: application/json' \
     -d '{"email":"ana@example.com","comment":"Ótimo artigo!","content_id":"materia-42"}'
curl localhost:8000/api/comment/list/materia-42
```

Desenvolvimento (venv):

```sh
python -m venv .venv && . .venv/Scripts/activate      # Windows; Linux/mac: . .venv/bin/activate
pip install -e ".[dev]"
docker compose up -d postgres && alembic -c app/alembic.ini upgrade head
uvicorn app.main:app --reload                          # ou: make run
pytest                                                 # 25 testes, cobertura ≥ 80 % (gate)
ruff check . && mypy                                   # ou: make lint typecheck
```

## Provisionar e implantar na AWS

Pré-requisitos: AWS CLI autenticada (usuário IAM admin), Terraform ≥ 1.10, kubectl, Helm.

```sh
# 1) state remoto (uma vez)
cd infra/terraform/bootstrap && terraform init && terraform apply

# 2) rede, EKS, RDS, ECR, IAM  (~20 min)
cd ../00-foundation
cp terraform.tfvars.example terraform.tfvars   # budget_email, github_repository/ids, CIDRs de acesso
terraform init && terraform apply
aws eks update-kubeconfig --name comments-api-dev --region us-east-1

# 3) ESO, ALB Controller, metrics-server, kube-prometheus-stack, dashboards, alertas (~5 min)
cd ../10-platform && terraform init && terraform apply

# 4) GitHub: Settings → Variables → AWS_ROLE_ARN = output github_actions_role_arn
#    Settings → Environments → infra-apply (required reviewers)
#    values-dev.yaml: database.host / secretArn = outputs rds_address / rds_master_user_secret_arn
git push   # ci → deploy. Endpoint: kubectl -n comments get ingress
```

Pipeline: [`ci.yml`](.github/workflows/ci.yml) (lint+test · chart · build · **scan** Trivy+Checkov · **package** ECR) → [`deploy.yml`](.github/workflows/deploy.yml) (helm `--atomic` · smoke · evidência) · [`infra.yml`](.github/workflows/infra.yml) (terraform plan em PR, apply manual aprovado).

Desligar: `terraform destroy` em `10-platform`, depois em `00-foundation` (ordem importa: o ALB Controller precisa remover o ALB).

## Métricas, dashboard e alertas

```sh
kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80   # dashboard "Comments API"
kubectl -n monitoring get secret grafana-admin -o jsonpath='{.data.admin-password}' | base64 -d   # user admin
kubectl -n monitoring port-forward svc/kps-prometheus 9090:9090                 # /alerts /rules /targets
kubectl -n monitoring port-forward svc/kps-alertmanager 9093:9093
```

- Métricas da app: `http_requests_total{route,status_class}`, `http_request_duration_seconds` (p50/p95/p99), `http_requests_in_progress`, `db_pool_connections`, `db_query_duration_seconds`, `db_errors_total`, `comments_created_total`, `app_info{version}`. RDS via `postgres_exporter` (`pg_stat_database_numbackends`, commits, tamanho).
- Dashboard: [ops/grafana/comments-api.json](ops/grafana/comments-api.json) (SLO · tráfego · latência · erros · saturação/HPA · banco · deploys).
- Alertas: [ops/alerts/comments-api.rules.yaml](ops/alerts/comments-api.rules.yaml) — 12 regras (burn rate 14,4×/6×, 5xx > 1 %, p95 > 300 ms, down, crash loop, HPA no máximo, pool, RDS).
- SLO/SLI: [ops/slo/slo.md](ops/slo/slo.md). Runbooks: [ops/runbooks/](ops/runbooks/).

## Gestão de segredos

1. Terraform cria o RDS com `manage_master_user_password`: a AWS gera a senha e a grava no **Secrets Manager**. Ela não existe no código, no state nem no pipeline.
2. **External Secrets Operator** (role IRSA com `GetSecretValue` só nesse ARN) lê o secret e monta um Secret Kubernetes com `DATABASE_URL` (template, senha url-encoded).
3. O pod recebe `DATABASE_URL` como variável de ambiente — o mesmo contrato do `docker compose`.
4. Sem chaves AWS em lugar nenhum: GitHub Actions usa **OIDC** (role com trust restrita ao repositório), pods usam **IRSA**. Grafana: senha em Secret gerado pelo Terraform (`random_password`).

Scans: Trivy (imagem, Dockerfile, Terraform, Helm) e Checkov (Terraform, manifests renderizados, Dockerfile) com gate HIGH/CRITICAL; exceções justificadas em [.trivyignore](.trivyignore) e [.checkov.yaml](.checkov.yaml).

## Evidências

| | Pasta |
|---|---|
| Deploy pelo pipeline, pods Running, endpoint no ALB, smoke | [docs/evidencias/01-deploy](docs/evidencias/01-deploy) |
| Dashboard provisionado, SLO com dados, alerta disparando/resolvendo | [docs/evidencias/02-observabilidade](docs/evidencias/02-observabilidade) |
| HPA 2 → 5 → 2 sob carga k6 | [docs/evidencias/03-hpa](docs/evidencias/03-hpa) |
| Rollback com `helm rollback` | [docs/evidencias/04-rollback](docs/evidencias/04-rollback) |
| Restore do RDS (PITR) com RPO/RTO | [docs/evidencias/05-restore](docs/evidencias/05-restore) |

## Custos

Ambiente ligado ≈ **USD 0,20/h** (EKS 0,10 · 2× t3.small 0,04 · NAT 0,045 · ALB 0,02 · RDS free tier · EBS/KMS/logs ~0,01). Medidas: 1 NAT, single-AZ, retenção de logs/métricas curta, sem Container Insights/AMP, `terraform destroy` fora das janelas. Detalhes e custo real: [docs/custos.md](docs/custos.md).

## Transparência

- **IA:** Claude Code (Anthropic) foi usado como par de programação durante todo o projeto — planejamento, escrita de código/IaC, diagnóstico de falhas e documentação. Toda decisão foi discutida e cada comando com efeito na conta AWS ou no Git foi executado pelo autor. Configuração do agente em `CLAUDE.md` (não versionado) impede commits automáticos.
- **Templates/módulos:** `terraform-aws-modules/{vpc,eks,iam}`; charts `external-secrets`, `aws-load-balancer-controller`, `metrics-server`, `kube-prometheus-stack`; imagem `quay.io/prometheuscommunity/postgres-exporter`; `grafana/k6`. Nenhum boilerplate de aplicação.
- **Referências:** AWS EKS Best Practices Guide; Google SRE Workbook (cap. 5, Alerting on SLOs); docs FastAPI, SQLAlchemy, Alembic, prometheus-client, External Secrets, Prometheus Operator.
- **Tempo:** ~2 dias de trabalho (registro por etapa em [COMMENTS.md](COMMENTS.md)).
