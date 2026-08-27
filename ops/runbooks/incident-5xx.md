# Runbook — Incidente: erros 5xx / latência

**Alertas:** `CommentsApiHighErrorRate` (5xx > 1 %, critical), `CommentsApiSLOBurnRateFast/Slow`, `CommentsApiHighLatencyP95` (> 300 ms, warning).

## 1. Triagem (2 min)

```sh
kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80   # dashboard "Comments API"
kubectl -n comments get pods -o wide                                            # todos Running/Ready? restarts?
helm history comments-api -n comments | tail -3                                 # houve deploy recente?
kubectl -n comments logs deploy/comments-api --since=10m | grep -E '"status": 5' | tail -20
```

Perguntas na ordem:
1. **Começou logo após um deploy?** → [rollback.md](rollback.md). Não investigue com o usuário sofrendo.
2. **Todos os pods ou um só?** Um só → `kubectl delete pod <pod>` (o Deployment recria); depois investigar o log dele.
3. **Erros de banco junto?** (`db_errors_total` no dashboard, log `asyncpg`) → seção 3.
4. **Latência alta sem 5xx?** → seção 4.

## 2. 5xx na aplicação

| Log / sinal | Causa | Ação |
|---|---|---|
| `asyncpg.exceptions.*ConnectionDoesNotExistError` / `could not connect` | RDS indisponível, SG, senha rotacionada | `aws rds describe-db-instances … --query 'DBInstances[0].DBInstanceStatus'`; ver [db-restore.md](db-restore.md) |
| `TimeoutError` / `QueuePool limit … reached` | pool esgotado | `CommentsApiDbPoolExhausted` também disparou? → queries lentas; escalar HPA não ajuda |
| `OOMKilled` em `describe pod` | memória | subir `resources.limits.memory` (256 Mi hoje) |
| 5xx só em `POST` | constraint/migração | `kubectl logs job/comments-api-migrate`; schema vs código |

## 3. Banco

```sh
aws rds describe-events --source-identifier comments-api-dev --source-type db-instance --duration 120
aws logs tail /aws/rds/instance/comments-api-dev/postgresql --since 15m | grep -iE "error|duration"
```
- Janela de manutenção é domingo 04:00–05:00 UTC (single-AZ = indisponibilidade curta esperada). Se o incidente coincide, é isso.
- Storage: autoscaling até 50 GiB; `FreeStorageSpace` no CloudWatch.
- CPU do `t4g.micro` (2 vCPU burstable): `CPUCreditBalance` baixo = throttling → queries lentas → pool cheio → 5xx. Mitigação: `db.t4g.small`.

## 4. Latência (p95 > 300 ms) sem erros

1. Dashboard → linha **Saturação**: CPU dos pods perto do request (100m)? HPA no máximo (`CommentsApiHpaAtMax`)?
   - HPA ainda tem margem → esperar escalar (15 s de resolução do metrics-server + 15 s policy).
   - HPA no máximo → subir `autoscaling.maxReplicas` (refazer conta de conexões) ou `resources.requests.cpu`.
2. Linha **Banco**: `db_query_duration_seconds` p95 subiu junto? → problema é o banco (seção 3), não a API.
3. Só `GET list` lento com `content_id` grande → paginação/índice; `EXPLAIN ANALYZE` da query.
4. Nada disso → rede/ALB: `aws elbv2 describe-target-health`, latência do ALB no CloudWatch (`TargetResponseTime`).

## 5. Encerramento

- Confirmar alerta resolvido no Alertmanager e error budget no dashboard.
- Postmortem se consumiu > 10 % do error budget ([ops/slo/slo.md](../slo/slo.md)).
- Registrar em `COMMENTS.md`: linha do tempo, causa, detecção (qual alerta, em quanto tempo), correção, ação preventiva.
