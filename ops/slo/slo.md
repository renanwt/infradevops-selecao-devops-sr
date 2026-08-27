# SLO / SLI — Comments API

Documento formal dos objetivos de nível de serviço. Todos os números abaixo são medidos pelo Prometheus com as *recording rules* em [`ops/alerts/comments-api.rules.yaml`](../alerts/comments-api.rules.yaml) e exibidos na linha "Visão SLO" do dashboard [`ops/grafana/comments-api.json`](../grafana/comments-api.json).

## 1. Escopo

- **Serviço:** `comments-api` (endpoints `POST /api/comment/new`, `GET /api/comment/list/{id}`).
- **Ponto de medição:** métricas da própria aplicação (`http_requests_total`, `http_request_duration_seconds`), coletadas via ServiceMonitor. Mede o que o ALB entrega ao pod; **não** inclui latência de rede até o cliente nem falhas do ALB antes de chegar ao pod (evolução: SLI a partir dos logs/métricas do ALB).
- **Excluídos do SLI:** `/health`, `/ready`, `/metrics` (tráfego de probes) e respostas `4xx` (erro do cliente, não do serviço).
- **Janela:** 30 dias corridos (*rolling*).

## 2. SLIs e SLOs

| SLI | Definição (PromQL simplificado) | SLO | Error budget (30d) |
|---|---|---|---|
| **Disponibilidade** | `1 − (req 5xx em /api/*) / (req totais em /api/*)` | **≥ 99,5 %** | 0,5 % das requisições ≈ **3 h 36 min** de indisponibilidade total equivalente |
| **Latência** | fração de req em `/api/*` com duração `< 300 ms` (bucket `le="0.3"`) | **≥ 95 %** | 5 % das requisições podem exceder 300 ms |
| **Latência de escrita** | p99 de `POST /api/comment/new` | **< 800 ms** | — (indicador secundário, sem alerta) |

Por que esses valores: a API é um backend de comentários de conteúdo editorial — não é caminho crítico de receita; 99,5 % dá folga para deploys e manutenção do RDS single-AZ (janela semanal) sem quebrar o SLO. 300 ms cobre 1 round-trip ao RDS (~5–20 ms) com margem para pico; um p95 acima disso indica pool esgotado, query lenta ou CPU throttling.

## 3. Error budget e política

**Orçamento** = 1 − SLO. Para disponibilidade: 0,5 % × 30 d = 216 min.

| Budget restante | Política |
|---|---|
| > 50 % | Operação normal. Deploys livres (pipeline). |
| 10–50 % | Deploys só com revisão de par; priorizar itens de confiabilidade no backlog. |
| < 10 % | **Congelar** deploys de feature; só correções. Postmortem obrigatório do incidente que consumiu o budget. |
| Esgotado | Além do acima: revisar se o SLO está correto ou se falta investimento estrutural (Multi-AZ, réplicas de leitura). |

O painel "Error budget restante (30d)" do dashboard mostra o valor atual; `clamp_min(..., 0)` evita valores negativos.

## 4. Alertas baseados em burn rate

*Burn rate* = velocidade de consumo do error budget relativa ao ritmo "exato" (1× = esgota em 30 dias).

| Alerta | Burn rate | Janelas | Consome | Esgota em | Severidade |
|---|---|---|---|---|---|
| `CommentsApiSLOBurnRateFast` | 14,4× | 1 h **e** 5 min | 2 % do budget/h | ~2 dias | critical (acordar alguém) |
| `CommentsApiSLOBurnRateSlow` | 6× | 6 h **e** 30 min | 5 % do budget/6 h | ~5 dias | warning (próximo dia útil) |

**Por que multi-window:** a janela longa garante que o problema é relevante (não um pico de 30 s); a janela curta garante que **ainda está acontecendo** — o alerta resolve minutos após a correção, em vez de ficar 1 h ativo por inércia. Referência: Google SRE Workbook, cap. 5 "Alerting on SLOs".

Alertas de **causa** (`PodCrashLooping`, `DbPoolExhausted`, `HpaAtMax`, `RdsConnectionsHigh`) existem para diagnóstico e capacidade, mas a severidade *critical* é reservada a sintomas que afetam o usuário (SLO) ou indisponibilidade total (`CommentsApiDown`).

## 5. Como verificar

```promql
# disponibilidade 30d
1 - (sum(increase(http_requests_total{job="comments-api",route=~"/api/.*",status_class="5xx"}[30d])) or vector(0))
    / sum(increase(http_requests_total{job="comments-api",route=~"/api/.*"}[30d]))

# fração < 300 ms (5m)
sum(rate(http_request_duration_seconds_bucket{job="comments-api",route=~"/api/.*",le="0.3"}[5m]))
/ sum(rate(http_request_duration_seconds_count{job="comments-api",route=~"/api/.*"}[5m]))

# burn rate 1h
comments_api:http_5xx_ratio:rate1h / 0.005
```

## 6. Limitações conhecidas e evolução

- Retenção do Prometheus é **2 dias** (custo em t3.small): o painel de 30 d só é fiel após a retenção ser ampliada (ou com Thanos/Mimir/AMP para longo prazo).
- SLI medido no pod, não na borda: falhas no ALB/DNS aparecem como `NoTraffic`, não como 5xx. Evolução: métricas do ALB (CloudWatch → `cloudwatch-exporter`) ou logs de acesso do ALB.
- Sem SLO de *freshness* / consistência: o serviço é síncrono com o banco; não há fila.
- Revisão do SLO: trimestral, ou após qualquer mês com budget esgotado.
