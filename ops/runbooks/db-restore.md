# Runbook — Banco de dados (RDS): restore, conexões, credenciais

**Instância:** `comments-api-dev` (PostgreSQL 16, `db.t4g.micro`, single-AZ, backup automático 1 dia com PITR).

## Restore

O RDS não restaura "por cima": ele cria **uma instância nova** a partir do backup. O caminho é: restaurar → validar → apontar a aplicação para a nova → remover a antiga.

### Opção A — Point-in-time (qualquer instante dentro da retenção)

```sh
aws rds describe-db-instances --db-instance-identifier comments-api-dev \
  --query 'DBInstances[0].LatestRestorableTime'

aws rds restore-db-instance-to-point-in-time \
  --source-db-instance-identifier comments-api-dev \
  --target-db-instance-identifier comments-api-dev-restore \
  --restore-time 2026-08-27T02:30:00Z \
  --db-instance-class db.t4g.micro \
  --db-subnet-group-name comments-api-dev \
  --vpc-security-group-ids <sg-do-rds> \
  --db-parameter-group-name <parameter-group-atual> \
  --no-publicly-accessible --no-multi-az
aws rds wait db-instance-available --db-instance-identifier comments-api-dev-restore   # medido: 22 min (PITR em t4g.micro); snapshot e mais rapido
```

### Opção B — Snapshot (automático diário ou manual)

```sh
aws rds describe-db-snapshots --db-instance-identifier comments-api-dev \
  --query 'DBSnapshots[].[DBSnapshotIdentifier,SnapshotCreateTime,Status]' --output table
aws rds create-db-snapshot --db-instance-identifier comments-api-dev --db-snapshot-identifier pre-migracao-$(date +%Y%m%d)   # manual, antes de algo arriscado

aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier comments-api-dev-restore \
  --db-snapshot-identifier <snapshot> \
  --db-instance-class db.t4g.micro --db-subnet-group-name comments-api-dev \
  --vpc-security-group-ids <sg-do-rds> --no-publicly-accessible
```

### Validar e promover

1. A instância restaurada tem o **mesmo usuário e senha** do momento do backup — o secret gerenciado (`rds!db-…`) continua válido se a senha não rotacionou desde então. Se rotacionou, redefinir: `aws rds modify-db-instance --db-instance-identifier comments-api-dev-restore --master-user-password …` ou `--manage-master-user-password`.
2. Validar dados a partir de um pod no cluster (o RDS é privado):
   ```sh
   kubectl -n comments run psql --rm -it --image=postgres:16-alpine --restart=Never -- \
     psql "host=<endpoint-restore> dbname=commentsdb user=comments_admin sslmode=require" -c 'select count(*) from comments;'
   ```
3. Apontar a aplicação: `database.host` em `deploy/helm/comments-api/values-dev.yaml` → novo endpoint → commit → pipeline (ou `helm upgrade` manual). O ESO monta a nova `DATABASE_URL`; pods reiniciam pelo checksum.
4. Depois de estável: `terraform state mv`/`import` para o Terraform passar a gerenciar a nova instância **ou** (mais simples) renomear: apagar a antiga, `modify-db-instance --new-db-instance-identifier comments-api-dev` na restaurada (o endpoint volta ao original) e `terraform import`.
5. Apagar a instância que não for usada: `aws rds delete-db-instance --db-instance-identifier … --skip-final-snapshot`.

**RPO/RTO observados:** ver `docs/evidencias/05-restore/`.

## Conexões (`CommentsApiDbPoolExhausted`, `RdsConnectionsHigh`)

- Limite prático do `db.t4g.micro`: ~85 conexões. Orçamento: 5 pods × (5 + 5 overflow) = 50 + exporter 1.
- Ver do lado do servidor: `pg_stat_database_numbackends{datname="commentsdb"}` (dashboard, linha Banco).
- Ver quem segura conexão:
  ```sql
  select pid, state, now()-query_start as age, left(query,80) from pg_stat_activity where datname='commentsdb' order by age desc;
  select pg_terminate_backend(<pid>);   -- último recurso
  ```
- Pool cheio com poucas requisições = query lenta. Log de queries > 500 ms está no CloudWatch (`/aws/rds/instance/comments-api-dev/postgresql`).
- Ajustes: `DB_POOL_SIZE`/`DB_MAX_OVERFLOW` (ConfigMap via values) ou `maxReplicas` do HPA — sempre refazendo a conta acima.

## Credenciais

- Senha do master é **gerenciada pela AWS** (Secrets Manager `rds!db-…`). Rotação: console → *Rotate immediately* (ou `rotation_rules` no Terraform).
- Após rotação, forçar o ESO a resincronizar antes de 1 h: `kubectl -n comments annotate externalsecret comments-api-db comments-api-postgres-exporter force-sync=$(date +%s) --overwrite`; os pods reiniciam quando o Secret muda? **Não** — a API lê env no start: `kubectl -n comments rollout restart deploy/comments-api deploy/comments-api-postgres-exporter`.
- Nunca colocar a senha em values/tfvars/pipeline. Se vazou em log (ex.: traceback do Alembic), rotacionar.
