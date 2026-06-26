# deploy/kubernetes/apps/n8n

## Что это
Слой `n8n` в queue mode: web + worker + импорт workflow.

## Что ставится

- n8n runtime (web/worker) через локальный chart
- Traefik Middleware для HTTP->HTTPS redirect
- NetworkPolicy
- ConfigMap c workflow JSON + import Job
- native `/metrics` endpoint + `ServiceMonitor` для `n8n-web`

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

## Reverse proxy

`n8n` в этом контуре работает за Traefik ingress, поэтому runtime должен доверять одному proxy hop. Это задается через `n8n.proxyHops: 1`, который рендерится в `N8N_PROXY_HOPS`. Без этого `n8n` получает `X-Forwarded-For` от ingress, но не считает proxy trusted и начинает ломать часть web/API логики.

## Workflows bootstrap

Import job для workflows всегда повторно импортирует, публикует и переактивирует workflow через CLI (`n8n import:workflow` → `n8n publish:workflow` → `n8n update:workflow --active=true`). Раньше поверх этого post-sync hook в `releases/workflows.yaml` дополнительно делал `kubectl rollout restart` для `n8n-web` и `n8n-worker`. Этот рестарт убран: при обновлении Deployment spec (image digest, env, secret) helm/helmfile и так выполнит rolling restart, а принудительный `rollout restart` делал второй rolling update поверх первого, удлинял окно недоступности во время deploy и порождал post-rollout `N8nDown` / `N8nPublicEndpointDown` / `N8nAvailabilityBurnRateFast` шум. Если n8n-версия, выбранная в `image`, действительно требует ручного рестарта для регистрации webhook-ов, helm-upgrade уже даёт rolling restart при обновлении digest-а.

Для контрольной проверки после deploy, что webhooks реально активны:

```bash
kubectl -n n8n exec deploy/n8n-web -- \
  n8n list:workflow --only-active
```

Если активных workflow-ов меньше, чем ожидалось из `n8n/workflows/*.json` с `active: true`, запустить `n8n update:workflow --id=<id> --active=true` вручную или инициировать helm-upgrade n8n-runtime так, чтобы изменился Deployment spec и K8s сделал rolling restart.

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
kubectl -n n8n get servicemonitor
kubectl -n n8n rollout status deploy/n8n-web
kubectl -n n8n rollout status deploy/n8n-worker
kubectl -n n8n logs job/n8n-import-workflows --tail=200
curl -I http://n8n.poluyanov.net
curl -I https://n8n.poluyanov.net
kubectl -n n8n port-forward svc/n8n-web-svc 5678:5678
curl http://127.0.0.1:5678/metrics
```

## Smoke

```bash
kubectl -n n8n exec deploy/n8n-web -- \
  n8n export:workflow --id=2d9f4b6a-1e44-4a71-8d52-b1c6f7a9d404 --output=/tmp/smoke.json
```
