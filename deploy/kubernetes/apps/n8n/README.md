# deploy/kubernetes/apps/n8n

## Что это
Слой `n8n` в queue mode: web + worker + импорт workflow.

## Что ставится

- n8n runtime (web/worker) через локальный chart
- Traefik Middleware для HTTP->HTTPS redirect
- NetworkPolicy
- ConfigMap c workflow JSON + import Job

## Какие chart используются

- локальный chart `./chart` для runtime n8n
- `../../../vendor_charts/raw` (upstream `bedag/raw`) для networkpolicy и workflows release

## Основные файлы

- `helmfile.yaml` — точка входа
- `releases/n8n.yaml` — runtime
- `releases/networkpolicy.yaml` — сетевые правила
- `releases/http-redirect-middleware.yaml` — redirect HTTP->HTTPS
- `releases/workflows.yaml` — импорт workflow/credentials
- `environments/prod/app.values.yaml` — runtime и endpoint-пути
- `environments/prod/workflows.values.yaml` — параметры import job
- `environments/prod/secrets.values.enc.yaml` — SOPS-секреты n8n

## Зависимости

- `deploy/kubernetes/platform` уже применен (namespace `n8n`)
- `apps/postgres`, `apps/redis`, `apps/ollama` уже применены
- workflow файлы существуют в `n8n/workflows/*.json`
- настроены `sops` и `helm-secrets`

## Как применять

```bash
cd deploy/kubernetes/apps/n8n

# Проверка рендера
helm lint chart
helmfile -e prod build > /tmp/n8n-build.yaml

# Применение
helmfile -e prod sync
```

## Проверка

```bash
kubectl -n n8n get deploy,pods,svc,ingress,job,networkpolicy
kubectl -n n8n rollout status deploy/n8n-web
kubectl -n n8n rollout status deploy/n8n-worker
kubectl -n n8n logs job/n8n-import-workflows --tail=200
curl -I http://n8n.poluyanov.net
curl -I https://n8n.poluyanov.net
```

## Smoke

```bash
kubectl -n n8n exec deploy/n8n-web -- \
  n8n export:workflow --id=2d9f4b6a-1e44-4a71-8d52-b1c6f7a9d404 --output=/tmp/smoke.json
```
