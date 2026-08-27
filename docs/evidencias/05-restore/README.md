# Evidência 05 — restore do RDS por point-in-time (2026-08-27)

Procedimento do runbook [ops/runbooks/db-restore.md](../../../ops/runbooks/db-restore.md) executado de ponta a ponta contra o banco real: restaurar em uma **instância nova**, validar os dados de dentro do cluster, medir RPO/RTO, apagar. Saída completa em [restore-pitr.txt](restore-pitr.txt).

## Resultado

| | Valor |
|---|---|
| Origem | `comments-api-dev` (PostgreSQL 16, `db.t4g.micro`, backup automático 1 d) |
| Ponto de restauração escolhido | **03:05:30 UTC** (5 min antes do `LatestRestorableTime`, que era 03:10:30) |
| `restore-db-instance-to-point-in-time` → `available` | **22 min 23 s** |
| Validação (psql em pod efêmero, `sslmode=require`) | restaurado: **43 linhas, última em 02:53:43** — exatamente o conteúdo do banco às 03:05:30 (o teste de carga k6 começou a inserir às 03:10, por isso a origem já mostrava 3 315 → 7 065 linhas durante o restore) |
| **RPO** | qualquer instante dentro da retenção (1 dia) com granularidade de segundos — PITR usa o WAL contínuo |
| **RTO** | ≈ **22 min** (instância) + ~2 min (trocar `database.host` no values e rollout) ≈ **25 min** |
| Limpeza | `delete-db-instance … --skip-final-snapshot` → `deleting` |

## Leitura

- A contagem confirma a **consistência do PITR**: nenhuma linha posterior a 03:05:30 apareceu na instância restaurada, e todas as anteriores estão lá.
- O RTO de 22 min ficou acima da faixa típica de 8–12 min do runbook (ajustado). Fatores: `t4g.micro` (burstable), PITR precisa aplicar WAL desde o último snapshot (~7 h de log), e a AWS executa um backup inicial da instância nova antes de liberá-la (`backing-up`). Para RTO menor: snapshots manuais antes de operações arriscadas (restore de snapshot é mais rápido que PITR) ou Multi-AZ (failover em ~1–2 min, que cobre falha de infraestrutura, não corrupção lógica).
- Custo do teste: ~25 min de `db.t4g.micro` + 20 GiB → centavos.

## Como foi executado (resumo)

```sh
aws rds restore-db-instance-to-point-in-time --source-db-instance-identifier comments-api-dev \
  --target-db-instance-identifier comments-api-dev-restore --restore-time 2026-08-27T03:05:30Z \
  --db-instance-class db.t4g.micro --db-subnet-group-name comments-api-dev \
  --vpc-security-group-ids <sg> --db-parameter-group-name <pg> --no-publicly-accessible --no-multi-az
aws rds wait db-instance-available --db-instance-identifier comments-api-dev-restore
kubectl -n monitoring run psql --rm -i --restart=Never --image=postgres:16-alpine --env=PGPASSWORD=… -- \
  psql "host=<endpoint-restore> dbname=commentsdb user=comments_admin sslmode=require" -tAc 'select count(*), max(created_at) from comments'
aws rds delete-db-instance --db-instance-identifier comments-api-dev-restore --skip-final-snapshot --delete-automated-backups
```
