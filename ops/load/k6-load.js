// Teste de carga da Comments API com k6.
// Objetivo: gerar CPU suficiente para o HPA escalar (2 -> 5) e medir p95/erros sob carga.
//
// Execucao dentro do cluster (Job): ver k6-job.yaml. Alvo padrao = Service interno.
//   kubectl -n comments create configmap k6-script --from-file=ops/load/k6-load.js
//   kubectl -n comments apply -f ops/load/k6-job.yaml
// Local: k6 run -e BASE_URL=http://<alb> ops/load/k6-load.js

import http from "k6/http";
import { check, sleep } from "k6";
import { Trend, Rate } from "k6/metrics";

const BASE_URL = __ENV.BASE_URL || "http://comments-api.comments.svc.cluster.local";
const CONTENT_IDS = ["materia-1", "materia-2", "materia-3", "materia-42"];

const listLatency = new Trend("list_latency", true);
const createLatency = new Trend("create_latency", true);
const errors5xx = new Rate("errors_5xx");

export const options = {
  scenarios: {
    ramp: {
      executor: "ramping-vus",
      startVUs: 0,
      stages: [
        { duration: "1m", target: 60 },   // aquece
        { duration: "3m", target: 120 },  // pico sustentado -> HPA deve escalar
        { duration: "1m", target: 0 },    // rampa de descida
      ],
      gracefulRampDown: "10s",
    },
  },
  // Espelham o SLO. abortOnFail=false: queremos o relatorio completo, nao parar.
  thresholds: {
    http_req_failed: ["rate<0.01"],
    http_req_duration: ["p(95)<300"],
    errors_5xx: ["rate<0.01"],
  },
};

export default function () {
  const id = CONTENT_IDS[Math.floor(Math.random() * CONTENT_IDS.length)];

  // 90% leitura, 10% escrita
  if (Math.random() < 0.1) {
    const res = http.post(
      `${BASE_URL}/api/comment/new`,
      JSON.stringify({ email: `k6-${__VU}@example.com`, comment: `carga iter ${__ITER}`, content_id: id }),
      { headers: { "Content-Type": "application/json" }, tags: { name: "POST /api/comment/new" } },
    );
    createLatency.add(res.timings.duration);
    errors5xx.add(res.status >= 500);
    check(res, { "POST 201": (r) => r.status === 201 });
  } else {
    const res = http.get(`${BASE_URL}/api/comment/list/${id}?limit=20`, {
      tags: { name: "GET /api/comment/list/{id}" },
    });
    listLatency.add(res.timings.duration);
    errors5xx.add(res.status >= 500);
    check(res, { "GET 200": (r) => r.status === 200 });
  }

  sleep(0.1);
}

export function handleSummary(data) {
  const m = data.metrics;
  const q = (name, p) => (m[name] && m[name].values[p] !== undefined ? m[name].values[p].toFixed(1) : "n/a");
  const lines = [
    "",
    "==== resumo k6 ====",
    `requisicoes: ${m.http_reqs.values.count}  (${m.http_reqs.values.rate.toFixed(1)} req/s)`,
    `falhas http: ${(m.http_req_failed.values.rate * 100).toFixed(3)}%   5xx: ${(m.errors_5xx.values.rate * 100).toFixed(3)}%`,
    `latencia total  p50=${q("http_req_duration", "med")}ms p95=${q("http_req_duration", "p(95)")}ms p99=${q("http_req_duration", "p(99)")}ms`,
    `GET list        p95=${q("list_latency", "p(95)")}ms`,
    `POST new        p95=${q("create_latency", "p(95)")}ms`,
    `thresholds: ${Object.entries(data.metrics).filter(([, v]) => v.thresholds).map(([k, v]) => `${k}=${Object.values(v.thresholds).every((t) => t.ok) ? "OK" : "FALHOU"}`).join(", ")}`,
    "",
  ];
  return { stdout: lines.join("\n") };
}
