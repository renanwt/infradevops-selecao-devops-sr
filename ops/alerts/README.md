# Alert rules

`PrometheusRule`s versionados. Provisionamento: `infra/terraform/10-platform/alerts.tf` aplica cada arquivo desta pasta; o Prometheus Operator recarrega o Prometheus em segundos.

| Alerta | Condição | For | Severidade |
|---|---|---|---|
| `CommentsApiHighErrorRate` | 5xx / total > 1% | 5m | critical |
| `CommentsApiHighLatencyP95` | p95 > 300 ms | 10m | warning |
| `CommentsApiSLOBurnRateFast` | burn rate 14,4× em 1h **e** 5m | 2m | critical |
| `CommentsApiSLOBurnRateSlow` | burn rate 6× em 6h **e** 30m | 15m | warning |
| `CommentsApiDown` | `up == 0` | 2m | critical |
| `CommentsApiNoTraffic` | 0 req/s por 10m | 15m | info |
| `CommentsApiPodNotReady` | disponíveis < desejadas | 5m | warning |
| `CommentsApiPodCrashLooping` | > 3 restarts / 15m | — | critical |
| `CommentsApiHpaAtMax` | réplicas = máx | 15m | warning |
| `CommentsApiDbPoolExhausted` | ≥ 9/10 conexões em uso num pod | 5m | warning |
| `RdsConnectionsHigh` | `numbackends` > 70 | 10m | warning |
| `RdsExporterDown` | `pg_up == 0` | 5m | warning |

Recording rules `comments_api:*` pré-calculam as razões de erro (5m/30m/1h/6h) e o p95 — as mesmas expressões do dashboard.

## Por que burn rate multi-window

Um alerta simples "erro > 1%" dispara em qualquer pico curto e não diz se o SLO está em risco. Burn rate mede *quão rápido o error budget de 30 dias está sendo consumido*; exigir a janela longa **e** a curta acima do limiar evita falso positivo (a longa) e faz o alerta resolver logo que o problema para (a curta). Referência: Google SRE Workbook, cap. 5.

## Testar um alerta

```sh
# derruba a API -> CommentsApiDown (2 min) e CommentsApiPodNotReady (5 min)
kubectl -n comments scale deploy/comments-api --replicas=0
kubectl -n monitoring port-forward svc/kps-alertmanager 9093:9093   # http://localhost:9093
kubectl -n comments scale deploy/comments-api --replicas=2           # (HPA reassume)
```

## Notificações

Alertmanager está com receiver `null` (alertas visíveis na UI). Para Slack: criar Secret com o webhook e trocar `receivers` em `infra/terraform/10-platform/monitoring.tf`.
