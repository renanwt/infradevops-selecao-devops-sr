# Evidência 02 — observabilidade (2026-08-27)

Stack kube-prometheus-stack no cluster, dashboard e alertas versionados em `ops/` e provisionados pelo Terraform (`10-platform`).

## Arquivos

| Arquivo | O que prova |
|---|---|
| [grafana.txt](grafana.txt) | Grafana 13.2 saudável; datasource `prometheus` (default); dashboard `comments-api` **provisionado pelo sidecar** (`provisioned=True`) na pasta "Comments API", 7 linhas / 21 painéis — importado a partir de `ops/grafana/comments-api.json` sem intervenção manual |
| [prometheus-slo.txt](prometheus-slo.txt) | Valores reais das expressões dos painéis após 4 min de tráfego sintético via ALB: 2,5 RPS, p95 16 ms, p99 25 ms, 100 % < 300 ms, disponibilidade 30d = 100 %, burn rate 0, 4xx aparecendo (validação), pool de conexões, HPA em 2 réplicas, 25 comentários criados |
| [alerta-teste-controlado.txt](alerta-teste-controlado.txt) | `CommentsApiDown` disparou (Prometheus `firing` → Alertmanager `active`) em 179 s após o Prometheus perder o target, e **resolveu em 32 s** após a restauração. Pods e endpoint público intactos durante todo o teste |

## Dois achados do teste (registrados em `ops/alerts/`)

1. **`up == 0` não detecta "API sumiu".** Sem pods Ready o Service perde os endpoints e o Prometheus **remove o target** — a série `up` deixa de existir em vez de valer 0. A regra passou a `up == 0 or absent(up{job="comments-api"})`. Sem o teste, o alerta mais importante estaria silenciosamente inútil.
2. **`kubectl scale --replicas=0` é um teste ruim** para esses alertas: além do ponto acima, `PodNotReady` compara com `spec.replicas`, que o scale também zera. O método adotado — quebrar o seletor do Service — reproduz a perda de coleta sem tocar no Deployment e é reversível em 1 comando.

## Um achado operacional

O `postgres_exporter` continuou com `pg_up=0` (alerta `RdsExporterDown` real disparando) mesmo após o fix do DSN, porque o Secret é materializado pelo ESO **fora do Helm**: mudou o Secret, o Deployment não mudou, nenhum rollout aconteceu. Corrigido com uma anotação `checksum/dsn` no pod template — mudança de host/db/formato do DSN agora força rollout.

## Como reproduzir

```sh
kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80   # dashboard
kubectl -n monitoring port-forward svc/kps-prometheus 9090:9090                # /alerts, /rules
kubectl -n monitoring port-forward svc/kps-alertmanager 9093:9093
# teste do alerta: ver ops/alerts/README.md
```
