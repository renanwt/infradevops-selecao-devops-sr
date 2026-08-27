# COMMENTS.md — Decisões, experimentos e testes

Registro do que de fato aconteceu durante o desafio: decisões técnicas e seus porquês, o que foi tentado e abandonado, o que quebrou, como foi diagnosticado, o que foi testado e o que faria com mais tempo. Complementa o [README.md](README.md) (como usar) e as [evidências](docs/evidencias/).

---

## 1. Decisões técnicas

| # | Decisão | Alternativas | Motivo | Trade-off aceito |
|---|---|---|---|---|
| D-01 | **AWS + EKS + RDS PostgreSQL** | GCP/GKE; ECS Fargate | EKS é o preferencial do desafio; os bônus (HPA, Helm rollback, PrometheusRule) são nativos de Kubernetes | control plane USD 0,10/h — mitigado com `terraform destroy` fora das janelas |
| D-02 | **Python 3.12 + FastAPI + SQLAlchemy async + Alembic** | Flask; Go; Node | validação Pydantic (`EmailStr`), OpenAPI automático, migrações versionadas | — |
| D-03 | **`/health` (liveness) separado de `/ready` (readiness com `SELECT 1`)** | um único `/health` checando DB | liveness acoplado ao banco derruba todos os pods numa oscilação do RDS | um endpoint a mais |
| D-04 | **Métricas com label `route` = template da rota** (`/api/comment/list/{content_id}`), rota inexistente = `unmatched` | path real | evita explosão de cardinalidade no Prometheus | perde granularidade por `content_id` (intencional) |
| D-05 | **Sem CPU limit** nos pods; só requests + limit de memória | limits em tudo | CPU limit causa throttling mesmo com CPU ociosa no nó; HPA usa requests | Checkov CKV_K8S_11 ignorado com justificativa |
| D-06 | **Terraform em 3 stacks** (`bootstrap` → `00-foundation` → `10-platform`) | stack único | providers `kubernetes`/`helm` precisam do cluster existir no `plan`; separa ciclos de vida | 3 `apply` |
| D-07 | **Lock do state nativo do S3** (`use_lockfile`, TF ≥ 1.10) | DynamoDB | um recurso a menos | — |
| D-08 | **Kubernetes 1.35** (não 1.30 do plano) | 1.30–1.33 | consultei `describe-cluster-versions`: 1.30–1.33 já em *extended support* = 6× o custo do control plane | módulo EKS v21 exigiu AWS provider 6.x |
| D-09 | **t3.small + VPC CNI prefix delegation** | t3.medium; Fargate | t3.small aceita 11 pods nativamente; com prefixos /28, 110 — cabe app + monitoring; Fargate não roda DaemonSets | nós em ~80 % de memória com o stack de monitoring |
| D-10 | **Senha do RDS gerenciada pela AWS** (`manage_master_user_password`) + **ESO via IRSA** | `random_password` no Terraform; Secrets Store CSI | senha nunca passa pelo state; rotação nativa; app recebe env var e fica agnóstica de nuvem | ESO como componente extra |
| D-11 | **Sem role IAM para a aplicação** | IRSA na app | ela só lê um Secret K8s e não chama APIs AWS — menos uma identidade | — |
| D-12 | **GitHub Actions + OIDC**; role do CI restrita a ECR push, `eks:DescribeCluster`, state S3, ReadOnly | access keys | sem credencial de longa duração | `terraform apply` pelo pipeline desligado (`github_actions_can_apply=false`) — apply é do operador |
| D-13 | **Acesso do CI ao cluster = `AmazonEKSAdminPolicy` no namespace + Role para 3 CRDs** | cluster-admin | least privilege real | precisou de 2 iterações (ver experimentos) |
| D-14 | **Migração como Helm hook `pre-install/pre-upgrade`**; ConfigMap/SA/ExternalSecret como hooks de peso −10 | initContainer; Job manual | schema sempre à frente do código; falha aborta o release (`--atomic`) | recursos-hook não são removidos por `helm uninstall` |
| D-15 | **Chart não vai para OCI no ECR** | `helm push` | o `deploy.yml` usa o chart do mesmo commit da imagem — amarrados pelo SHA | um repositório ECR a menos |
| D-16 | **Dashboard e alertas em `ops/`, aplicados pelo Terraform do `10-platform`** | ConfigMap dentro do chart | `ops/grafana`/`ops/alerts` são os caminhos exigidos e ficam como fonte única (Helm não lê `../ops`) | mudar dashboard exige `terraform apply`, não push |
| D-17 | **kube-prometheus-stack** com 1 réplica, retenção 2 d, sem scrape de etcd/scheduler/kube-proxy | AMP + AMG | gratuito; EKS não expõe esses componentes (targets down eternos) | painéis de 30 d só fiéis com retenção maior |
| D-18 | **Alertas por burn rate multi-window** (14,4× 1h+5m; 6× 6h+30m) | "erro > 1 %" simples | alerta quando o SLO está em risco, resolve rápido, poucos falsos positivos (SRE Workbook) | mais difícil de explicar |
| D-19 | **postgres_exporter com a credencial master** via ESO | usuário `pg_monitor` dedicado | tempo | registrado como evolução |
| D-20 | **KMS para secrets do etcd ligado** (revertendo decisão inicial) | sem KMS | Trivy/Checkov apontaram; ~USD 1/mês | ligar depois da criação custou 45 min de re-criptografia — deveria ter sido na criação |
| D-21 | **Grafana/Prometheus via `port-forward`** (ClusterIP) | Ingress/ALB | sem custo extra e sem exposição pública | sem URL para o avaliador — comandos no README |

---

## 2. Log de experimentos e problemas

Formato: o que aconteceu → como diagnostiquei → o que fiz.

| # | Problema | Diagnóstico | Correção |
|---|---|---|---|
| E-01 | `terraform apply` do RDS: `DBName comments cannot be used. It is a reserved word` | `comments` é palavra reservada no Postgres; o `createdb` local aceitava | `db_name = commentsdb` |
| E-02 | Módulo `terraform-aws-modules/eks` v21: `eks_managed_node_group_defaults` não existe; exige AWS provider ≥ 6 | erro no `init`/`validate` | inline no node group; provider `~> 6.0` |
| E-03 | Pipeline: `Not authorized to perform sts:AssumeRoleWithWebIdentity` com trust policy aparentemente correta | **CloudTrail** mostrou `principalId … repo:renanwt@107125053/…@1346344251`; `gh api …/actions/oidc/customization/sub` confirmou: GitHub emite `sub` no **formato imutável** (owner@id/repo@id) | trust policy aceita ambos os formatos, sem wildcard no nome; IDs em variáveis |
| E-04 | `helm_release.external_secrets` falhou: `failed calling webhook mservice.elbv2.k8s.aws … no endpoints available` | o webhook mutating do ALB Controller intercepta todo `Service`; o controller ainda não estava Ready | `depends_on = [helm_release.alb_controller]` |
| E-05 | Primeiro deploy: `externalsecrets … is forbidden … cannot delete` | `AmazonEKSAdminPolicy` = ClusterRole `admin`, que **não inclui CRDs** | access entry com `kubernetes_groups = [comments-deployers]` + Role/RoleBinding para `externalsecrets` |
| E-06 | Deploy seguinte: mesmo erro para `servicemonitors` | idem | Role estendido para `servicemonitors` e `prometheusrules` (antecipando o commit dos alertas) |
| E-07 | Smoke test no runner via `000` por ~1 min após o ALB nascer | propagação de DNS do ALB | loop de espera de até ~6 min antes do smoke |
| E-08 | `pg_up 0` no postgres_exporter: `could not parse DATA_SOURCE_NAME` | senha gerenciada do RDS contém `$ ! ( >` — inválidos numa URL | `DATA_SOURCE_URI/USER/PASS` separados (exporter faz o encoding); na API, `urlquery` na senha |
| E-09 | Após o fix, migração falhou: `invalid interpolation syntax` no Alembic | `%24`, `%21`… da senha url-encoded × `configparser` do `alembic.ini` | `.replace("%", "%%")` no `env.py` + **teste de regressão** com senha `comment%73` (falha sem o fix) |
| E-10 | Exporter continuou `pg_up 0` mesmo com o Secret corrigido | o Secret é materializado pelo ESO, fora do Helm: mudou o Secret, o Deployment não mudou → nenhum rollout | `rollout restart` + anotação `checksum/dsn` no pod template |
| E-11 | Exporter (e depois Alembic) **logaram a senha** no traceback | inerente às ferramentas | registrado; rotação do secret é 1 clique no Secrets Manager (ver runbook) |
| E-12 | Trivy: 3 HIGH no OpenSSL da base `python:3.12-slim` | patch existia no Debian, imagem oficial atrasada | `apt-get upgrade` no stage runtime |
| E-13 | Checkov: 17 falhas Terraform, 14 Kubernetes | triagem: 6 corrigidas (KMS EKS, `force_ssl`, IAM auth RDS, logs RDS, namespace explícito nos manifests, TLS), 15 aceitas com justificativa | `.checkov.yaml` / `.trivyignore` comentados |
| E-14 | Trivy `config` reportava falhas em `.terraform/modules/*/examples` | módulos baixados incluem exemplos | `--skip-dirs "**/.terraform"` |
| E-15 | **Alerta `CommentsApiDown` (`up == 0`) não disparava com a API a 0 pods** | sem endpoints o Prometheus **remove o target**: a série `up` some em vez de valer 0; `PodNotReady` compara com `spec.replicas`, que `scale 0` zera | `up == 0 or absent(up{job=…})`; método de teste = quebrar o seletor do Service. **Só descobri porque testei o alerta.** |
| E-16 | `kubernetes_manifest` para o `ClusterSecretStore` falharia no primeiro `apply` (CRD inexistente no `plan`) | limitação conhecida do provider | mini-chart Helm local |
| E-17 | Porta 5432/5433 locais ocupadas por outros projetos | `netstat`/`docker ps` | compose em 5432 após desligar o outro stack |
| E-18 | `ci` cancelado pelo push seguinte deixou `upload-sarif` com erro "path does not exist" | `concurrency` + arquivos não gerados | upload condicional a `hashFiles()` |

### Arquiteturas/abordagens abandonadas

- **DynamoDB para lock do state** → lock nativo do S3.
- **`random_password` + secret próprio para o RDS** → senha gerenciada pela AWS.
- **Role IAM para a aplicação** → desnecessária.
- **Chart OCI no ECR** → chart do próprio commit.
- **Dashboard como ConfigMap no chart** → Terraform lendo `ops/grafana`.
- **KMS desligado no EKS "por custo"** → religado após scan; custo real ~USD 1/mês.
- **Teste de alerta com `scale --replicas=0`** → quebrar seletor do Service.

---

## 3. Testes realizados

| Etapa | Tipo | Ferramenta | Resultado | Evidência |
|---|---|---|---|---|
| App | unitário + integração (Postgres real) | pytest, 25 testes, cobertura 95 % (gate 80 %) | ✅ local e no CI (service container) | `ci` runs |
| App | contrato manual | Postman/newman, 10 requests, 20 assertions | ✅ | `docs/postman/` |
| Container | vulnerabilidades + misconfig | Trivy | ✅ 0 HIGH/CRITICAL após patch | `ci` scan |
| IaC / K8s / Dockerfile | misconfig | Checkov (100 + 176 + 63 checks) | ✅ 0 falhas (15 skips justificados) | `.checkov.yaml` |
| Chart | lint + schema (K8s 1.35 + CRDs) | `helm lint --strict`, kubeconform (16 recursos) | ✅ | `ci` chart |
| Deploy | pipeline completo → pods Running, ALB, smoke (POST/GET/422/metrics) | GitHub Actions | ✅ | [01-deploy](docs/evidencias/01-deploy) |
| Probes | `/ready` 503 com Postgres parado e 200 ao voltar | curl local; k8s | ✅ | — |
| Observabilidade | dashboard provisionado, painéis SLO com dados, alerta `CommentsApiDown` firing em 179 s e resolvido em 32 s | Grafana/Prometheus/Alertmanager API | ✅ | [02-observabilidade](docs/evidencias/02-observabilidade) |
| HPA | k6 in-cluster (60→120 VUs, 5 min): 69 675 req, 232 req/s, 0 erros, p95 521 ms | k6 2.2.0 como Job | ✅ 2 → 5 em ~1 min, 5 → 2 em 454 s; gargalo no pico = CPU dos t3.small + pool 49/50 (alertas em pending) | [03-hpa](docs/evidencias/03-hpa) |
| Rollback | `helm rollback` para a rev anterior e roll-forward (38 s cada, sem indisponibilidade) + rollback automático `--atomic` na rev 5 (falha real) | Helm | ✅ | [04-rollback](docs/evidencias/04-rollback) |
| Restore | PITR do RDS (03:05:30Z) em instância temporária; contagem de linhas confere com o ponto escolhido | AWS CLI + psql in-cluster | ✅ RTO 22 min (instância) + ~2 min (rollout); RPO = segundos (WAL) | [05-restore](docs/evidencias/05-restore) |
| Regressão | senha com `%` na URL do Alembic | pytest | ✅ falha sem o fix, passa com | `tests/test_db.py` |

---

## 4. Registro de tempo (aprox.)

| Etapa | Atividade | Tempo |
|---|---|---|
| Planejamento | leitura, arquitetura, roteiro de commits | 1h30 |
| A — aplicação | scaffolding, API, DB/Alembic, testes, métricas, Dockerfile/compose | 4h |
| B — Terraform foundation | bootstrap, VPC, ECR, EKS, RDS, IAM, primeiro apply (+45 min de KMS) | 4h |
| C — plataforma + chart | ESO, ALB Controller, metrics-server, chart, hooks, HPA/PDB/NetPol | 3h |
| D — CI/CD + primeiro deploy | workflows, scans e triagem, OIDC/RBAC/DSN (E-03…E-10) | 4h |
| E — observabilidade | kube-prometheus-stack, exporter, dashboard, alertas, SLO, teste de alerta | 3h |
| F — resiliência | k6/HPA, rollback, runbooks, restore | 2h |
| G — documentação | README, COMMENTS, apresentação, custos | 1h30 |
| **Total** | | **≈ 23h** em 2 dias |

---

## 5. Uso de IA, templates e referências

- **IA:** Claude Code (Anthropic) como par durante todo o projeto — plano, código, IaC, diagnóstico (ex.: leitura de CloudTrail e logs), documentação. Toda decisão foi discutida; todo `terraform apply`, `git commit` e `git push` foi executado pelo autor. Um `CLAUDE.md` local (não versionado) proíbe o agente de comitar.
- **Templates/módulos:** `terraform-aws-modules/{vpc,eks,iam}`; charts `external-secrets`, `aws-load-balancer-controller`, `metrics-server`, `kube-prometheus-stack`; `quay.io/prometheuscommunity/postgres-exporter`; `grafana/k6`. Sem boilerplate de aplicação.
- **Referências:** AWS EKS Best Practices Guide; Google SRE Workbook cap. 5; docs FastAPI/SQLAlchemy/Alembic/prometheus-client; External Secrets; Prometheus Operator; GitHub OIDC (`sub` imutável).

---

## 6. Ideias de evolução (com mais tempo)

| Ideia | Como |
|---|---|
| Tracing distribuído | `opentelemetry-instrumentation-fastapi` + asyncpg → OTel Collector (DaemonSet) → Grafana Tempo; correlacionar `request_id` dos logs |
| GitOps | Argo CD observando `deploy/helm`; pipeline só publica imagem e abre PR de bump de tag |
| Supply chain | `cosign sign` no `package`; Kyverno `verifyImages` no cluster; SBOM (syft) como artefato |
| Banco | Multi-AZ (`db_multi_az=true`), read replica para o `GET list`, usuário `pg_monitor` para o exporter, rotação automática do secret com `force-sync` do ESO |
| SLO fiel a 30 d | retenção longa (Thanos/Mimir ou AMP) em vez de 2 d; SLI na borda com métricas do ALB |
| Nós | Karpenter + Spot para não-prod; `t3.medium` se o monitoring crescer |
| Segurança | `eks_public_access_cidrs` restrito; WAF no ALB; Pod Identity no lugar de IRSA |
| Portabilidade | account id / bucket / endpoints hoje hardcoded em `versions.tf`, `variables.tf`, `values-dev.yaml` → `-backend-config` + tfvars + GitHub Variables para outra conta rodar sem editar código |
| Testes | schemathesis (contrato/fuzz), teste de caos (`kubectl delete pod` sob carga), teste do restore automatizado |
