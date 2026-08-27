# Evidência 04 — rollback (2026-08-27)

Dois tipos de rollback provados no mesmo `helm history` ([rollback.txt](rollback.txt)):

## 1. Rollback automático (`--atomic`) em falha real

Revisão **5** (`02:21`): `Upgrade failed: pre-upgrade hooks failed` — o Job de migração quebrou (senha url-encoded × `configparser` do Alembic, ver `COMMENTS.md` E-09). O Helm criou sozinho a revisão **6 — "Rollback to 4"** em 44 s; a API nunca saiu do ar (o Deployment só é tocado depois dos hooks). Outras duas falhas anteriores (RBAC de CRDs) também foram revertidas pelo `--atomic` antes de o release existir (`has been uninstalled due to atomic`).

## 2. Rollback manual deliberado

| Passo | Comando | Resultado |
|---|---|---|
| estado inicial | rev **10** `deployed`, imagem `sha-cdb0fa1` | 2 pods Running |
| rollback | `helm rollback comments-api 9 --wait` | **38 s**; rev **11 "Rollback to 9"**; imagem `sha-96baa4d`; pods novos `1/1`; `/health` 200 e `GET list` 200 pelo ALB durante e após |
| roll-forward | `helm rollback comments-api 10 --wait` | **38 s**; rev **12 "Rollback to 10"**; imagem de volta a `sha-cdb0fa1` |

Rolling update com `maxUnavailable: 0` + PDB `minAvailable: 1` → sem indisponibilidade em nenhum dos sentidos.

## Observações

- O rollback do Helm **não reexecuta hooks**: o schema fica na versão mais nova. Por isso as migrações do projeto são aditivas (compatíveis com o código anterior). Procedimento e cuidados em [ops/runbooks/rollback.md](../../../ops/runbooks/rollback.md).
- Depois de um rollback manual, o próximo push na `main` reimplanta a versão com problema se ela não for revertida no Git — o runbook cobre isso.
- `kubectl rollout undo` funcionaria, mas deixaria o `helm history` inconsistente; a via Helm é a adotada.
