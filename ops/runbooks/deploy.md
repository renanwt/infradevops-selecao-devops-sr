# Runbook — Deploy

**Quando usar:** publicar uma nova versão da API; investigar um deploy que falhou; alertas `CommentsApiDown`, `CommentsApiPodNotReady`.

## Fluxo normal (pipeline)

1. Merge/push na `main` → workflow `ci` (lint → test → build → scan → package) publica `sha-<7>` no ECR.
2. `ci` verde → workflow `deploy` dispara sozinho: `helm upgrade --install --atomic --wait --timeout 5m`.
3. Verificar no run: passo **smoke test** verde e artefato `evidencia-deploy-<tag>`.

Deploy manual de uma tag específica: GitHub → Actions → **deploy** → *Run workflow* → `tag=sha-…`.

## Deploy manual (fora do pipeline)

```sh
aws eks update-kubeconfig --name comments-api-dev --region us-east-1
helm upgrade --install comments-api deploy/helm/comments-api -n comments \
  -f deploy/helm/comments-api/values-dev.yaml --set image.tag=sha-XXXXXXX \
  --atomic --wait --timeout 5m
```

## O que acontece por dentro (ordem)

| Fase | Objeto | Falha típica |
|---|---|---|
| hook -10 | ServiceAccount, ConfigMap, **ExternalSecret** | ESO sem permissão / ARN errado → Secret não aparece, Job fica `ContainerCreating` |
| hook 0 | **Job `comments-api-migrate`** (`alembic upgrade head`) | migração inválida, banco inacessível, `%` na URL → `BackoffLimitExceeded` |
| release | Deployment (rolling, `maxUnavailable=0`), Service, Ingress, HPA, PDB, NetworkPolicy | imagem inexistente (`ImagePullBackOff`), probe falhando → `--atomic` reverte |

## Diagnóstico

```sh
helm history comments-api -n comments                       # revisões e status
kubectl -n comments get pods -o wide                        # Running? restarts?
kubectl -n comments describe pod <pod> | sed -n '/Events/,$p'
kubectl -n comments logs deploy/comments-api --tail=100     # JSON estruturado
kubectl -n comments logs job/comments-api-migrate           # Job com falha fica para inspeção
kubectl -n comments get externalsecret                      # STATUS SecretSynced / READY True
kubectl -n comments get ingress                             # ADDRESS = hostname do ALB
```

| Sintoma | Causa provável | Ação |
|---|---|---|
| `--atomic` reverteu com `pre-upgrade hooks failed` | migração | `kubectl logs job/comments-api-migrate`; corrigir migração; novo commit |
| pods `CrashLoopBackOff` | config/env inválida | `kubectl logs --previous`; conferir `DATABASE_URL` no Secret |
| pods `Running` mas `0/1 Ready` | `/ready` 503 → banco inacessível | SG do RDS, NetworkPolicy, senha rotacionada sem sync do ESO (`kubectl annotate externalsecret comments-api-db force-sync=$(date +%s)`) |
| `ImagePullBackOff` | tag não existe no ECR | `aws ecr describe-images --repository-name comments-api --image-ids imageTag=sha-…` |
| Ingress sem ADDRESS | ALB Controller | `kubectl -n kube-system logs deploy/aws-load-balancer-controller` |
| Deploy ok mas `curl` no ALB dá 000/503 | targets ainda registrando | esperar 1–3 min; `aws elbv2 describe-target-health` |
| pipeline: `cannot create resource X` | RBAC do CI (CRD novo) | adicionar ao `Role deployer-crds` em `10-platform/main.tf` |

## Se nada resolve

→ [rollback.md](rollback.md).
