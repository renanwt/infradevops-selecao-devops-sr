# Runbook — Rollback

**Quando usar:** versão nova com erro funcional/5xx/latência que passou pelo smoke test; `CommentsApiHighErrorRate`, `CommentsApiSLOBurnRateFast`, `CommentsApiPodCrashLooping` logo após um deploy.

## Rollback automático (já acontece)

`helm upgrade --atomic` no pipeline: se a migração falhar ou os pods não ficarem `Ready` em 5 min, o Helm **volta sozinho** para a revisão anterior. Nenhuma ação necessária além de investigar ([deploy.md](deploy.md)).

## Rollback manual (Helm)

```sh
helm history comments-api -n comments
#  REVISION  STATUS      DESCRIPTION
#  7         superseded  Upgrade complete
#  8         deployed    Upgrade complete      <- versão com problema

helm rollback comments-api 7 -n comments --wait --timeout 5m
helm history comments-api -n comments          # nova revisão 9 = "Rollback to 7"
kubectl -n comments rollout status deploy/comments-api
kubectl -n comments get pods -o jsonpath='{.items[*].spec.containers[0].image}'   # tag antiga
curl -s http://<alb>/health && curl -s http://<alb>/api/comment/list/smoke?limit=1
```

**Atenção — migrações:** o rollback do Helm **não** desfaz o `alembic upgrade` (o hook `pre-upgrade` não roda em rollback). Regra do projeto: migrações são *backward-compatible* (só adicionam) para a versão anterior do código continuar funcionando com o schema novo. Se uma migração precisar ser desfeita: `alembic downgrade -1` via Job manual — avaliar perda de dados antes.

## Alternativa sem Helm

```sh
kubectl -n comments rollout history deploy/comments-api
kubectl -n comments rollout undo deploy/comments-api            # ou --to-revision=N
```
Prefira o Helm: mantém o `helm history` coerente e o próximo `helm upgrade` não briga com o estado.

## Depois do rollback

1. Abrir issue com a tag defeituosa e o `helm history`.
2. O pipeline continua apontando para a `main`: o **próximo push reimplanta a versão com problema** se ela não for revertida no Git → `git revert` do commit ou fix à frente.
3. Registrar em `COMMENTS.md` (o que quebrou, como foi detectado, tempo até rollback).

Evidência de um rollback real: `docs/evidencias/04-rollback/`.
