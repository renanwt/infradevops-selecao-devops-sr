# Evidência 03 — HPA sob carga (2026-08-27)

Carga gerada por **k6 2.2.0 rodando como Job dentro do cluster** ([ops/load/k6-job.yaml](../../../ops/load/k6-job.yaml), script [ops/load/k6-load.js](../../../ops/load/k6-load.js)) contra o Service interno da API — mede a aplicação, não a borda. Perfil: 0 → 60 VUs (1 min), 60 → 120 VUs (3 min), → 0 (1 min); 90 % `GET list`, 10 % `POST new`.

## Resultado

| Métrica | Valor |
|---|---|
| Requisições | **69 675** em 5 min (**232 req/s** médio; ~290 req/s no pico) |
| Erros HTTP / 5xx | **0,000 %** |
| Latência | p50 168 ms · **p95 521 ms** · GET p95 508 ms · POST p95 616 ms |
| HPA | **2 → 4 → 5 réplicas em ~1 min** após o início da carga; **5 → 4 → 3 → 2** em 454 s após o fim (janela de estabilização 300 s + 1 pod/min) |
| CPU dos pods | até **935 m por pod** (request 100 m → 675 % do alvo de 60 %); ~3,4 cores somados |
| Pool de conexões | **49 de 50** em uso no pico (5 pods × 10); RDS `numbackends` 48 |
| Alertas | `HpaAtMax`, `HighLatencyP95`, `DbPoolExhausted` chegaram a **pending** (os `for` de 5–15 min são maiores que o pico de 3 min — comportamento esperado) |

Threshold `p(95)<300` do k6 **falhou** (por isso o Job saiu com `failed=1`); `http_req_failed<1%` e `errors_5xx<1%` passaram.

## Arquivos

- [hpa-timeline.txt](hpa-timeline.txt) — `kubectl get hpa` + pods Ready + `kubectl top pods` a cada 20–30 s, do início da carga ao scale-down completo; eventos do HPA (`SuccessfulRescale` 4, 5, depois 4, 3, 2).
- [k6-resultado.txt](k6-resultado.txt) — saída do Job k6 (resumo customizado + thresholds).
- [prometheus-carga.txt](prometheus-carga.txt) — séries do Prometheus minuto a minuto: RPS, p50/p95, réplicas, CPU total, pool, `numbackends`, e a série `ALERTS`.

## Leitura

O **HPA funcionou** como configurado: reagiu em ~1 min, foi ao máximo, e desceu de forma conservadora sem *flapping*. A latência acima do SLO no pico **não é limitação do HPA** — ele já estava em `maxReplicas`. O gargalo foi capacidade:

1. **CPU dos nós**: 5 pods a ~0,7–0,9 core cada ≈ 3,4 cores em 2× t3.small (4 vCPU no total, compartilhados com o sistema e o monitoring).
2. **Pool de conexões**: 49/50 — requisições passaram a esperar por conexão.

Para sustentar ~300 req/s dentro do SLO as opções são, em ordem de custo: `maxReplicas` maior **com** nó `t3.medium` (ou um 3.º nó), `DB_POOL_SIZE` maior (refazendo a conta contra as ~85 conexões do `t4g.micro`), ou cache da listagem. Registrado em `COMMENTS.md` como evolução — o dimensionamento atual é deliberadamente mínimo para o desafio.

O alerta `CommentsApiDbPoolExhausted` em *pending* prova que a métrica do pool detecta o gargalo real antes de virar 5xx.
