# Evidência 01 — primeiro deploy na nuvem (2026-08-26)

Pipeline completo executado no GitHub Actions e aplicação respondendo pelo ALB.

| Item | Valor |
|---|---|
| Cluster | `comments-api-dev` (EKS 1.35, us-east-1, 2 nós t3.small em 2 AZs) |
| Imagem | `208597681536.dkr.ecr.us-east-1.amazonaws.com/comments-api:sha-8db5104` |
| Release Helm | `comments-api` rev 1, namespace `comments` |
| Endpoint | `http://k8s-comments-comments-2c7257dc2d-274715840.us-east-1.elb.amazonaws.com` |
| Run `ci` (lint → build → scan → package) | https://github.com/renanwt/infradevops-selecao-devops-sr/actions/runs/33023299339 |
| Run `deploy` (helm --atomic → smoke → evidência) | https://github.com/renanwt/infradevops-selecao-devops-sr/actions/runs/33023531518 |

## Arquivos

- [pipeline-deploy.txt](pipeline-deploy.txt) — artefato gerado **pelo próprio workflow** `deploy`: `helm history`, pods, HPA/PDB/ExternalSecret, ingress, `/health`.
- [kubectl.txt](kubectl.txt) — estado do cluster capturado localmente: nós, pods, objetos do namespace, probes/securityContext efetivos, plataforma (ESO, ALB Controller, metrics-server).
- [smoke.txt](smoke.txt) — chamadas manuais via ALB: `/health`, `/ready`, `POST` (201), `GET` (200), payload inválido (422), `/metrics`.

## O que fica provado

- **Pods `Running`** em nós de AZs distintas (topologySpread), 1/1 Ready — probes `startup`/`liveness` (`/health`) e `readiness` (`/ready`) passando.
- **Endpoint acessível** pela internet via ALB (Ingress class `alb`, targets `healthy`).
- **Persistência no RDS**: `POST` grava e `GET` lê; `/ready` confirma `SELECT 1` no banco privado.
- **Segredo sem passar pelo repo/pipeline**: `ExternalSecret` `SecretSynced` — credencial lida do Secrets Manager via IRSA e montada como `DATABASE_URL`.
- **Migração como hook**: `alembic upgrade head` rodou antes do Deployment (Job `pre-install`).
- **Pipeline**: OIDC (sem chaves), Trivy + Checkov verdes, imagem escaneada = imagem publicada, `helm --atomic`.
- **Segurança efetiva**: container `runAsUser=10001`, `readOnlyRootFilesystem=true`, namespace com PSS `restricted`.
- **HPA** ativo (`cpu: 2%/60%`, 2–5 réplicas), **PDB** `minAvailable=1`, **NetworkPolicy** aplicada.

## Problemas encontrados no caminho (detalhes no COMMENTS.md)

1. `sub` do OIDC do GitHub mudou para o formato imutável (`owner@id/repo@id`) → trust policy ajustada.
2. Webhook do ALB Controller intercepta `Service`s → ESO precisa de `depends_on`.
3. `AmazonEKSAdminPolicy` não cobre CRDs → grupo `comments-deployers` + Role para `externalsecrets`.
4. Primeiro smoke do runner viu `000` por propagação de DNS do ALB → loop de espera resolveu.
