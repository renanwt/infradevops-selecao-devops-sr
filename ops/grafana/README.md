# Dashboards Grafana

JSON versionado é a fonte da verdade. Provisionamento: `infra/terraform/10-platform/dashboards.tf` cria um ConfigMap (label `grafana_dashboard=1`) por arquivo desta pasta; o sidecar do Grafana importa na pasta **Comments API**.

| Arquivo | uid | Conteúdo |
|---|---|---|
| `comments-api.json` | `comments-api` | SLO (disponibilidade 30d, error budget, p95, burn rate 1h/6h) · tráfego (RPS por rota/status) · latência p50/p95/p99 · erros 5xx/4xx/DB · saturação (CPU/mem vs requests/limits, HPA) · banco (pool da app + `numbackends`/commits do RDS) · deploys (anotações por `app_info`) |

Variáveis: `namespace`, `route`. Datasource: `prometheus` (uid padrão do kube-prometheus-stack).

## Acesso

```sh
kubectl -n monitoring port-forward svc/kps-grafana 3000:80
kubectl -n monitoring get secret grafana-admin -o jsonpath='{.data.admin-password}' | base64 -d
# http://localhost:3000  (admin)
```

## Editar

1. Ajuste no Grafana → *Share → Export → Save to file* (ou *JSON model*).
2. Substitua o arquivo aqui, mantendo `uid`.
3. `terraform apply` no `10-platform` — o sidecar recarrega em segundos.
