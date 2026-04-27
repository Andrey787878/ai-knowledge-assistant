# deploy/kubernetes/apps/redis

## Что это
Слой Redis для очередей `n8n` (queue mode).

## Что ставится

- Redis StatefulSet
- Secret с паролем Redis (из SOPS)
- NetworkPolicy (доступ к Redis только от `n8n`)

## Какие chart используются

- `../../../vendor_charts/redis` (upstream `bitnami/redis`) для runtime
- `../../../vendor_charts/raw` (upstream `bedag/raw`) для secret и networkpolicy

## Основные файлы

- `helmfile.yaml` — точка входа
- `releases/redis.yaml` — runtime redis
- `releases/auth-secret.yaml` — пароль
- `releases/networkpolicy.yaml` — сетевые правила
- `environments/prod/app.values.yaml` — runtime параметры
- `environments/prod/secrets.values.enc.yaml` — пароль Redis

## Зависимости

- `deploy/kubernetes/platform` уже применен (namespace `n8n` существует)
- настроены `sops` и `helm-secrets`

## Как применять

```bash
cd deploy/kubernetes/apps/redis

# Проверка рендера
helmfile -e prod build > /tmp/redis-build.yaml

# Применение
helmfile -e prod sync
```

## Проверка

```bash
kubectl -n n8n get sts,pods,svc,secret,networkpolicy
kubectl -n n8n rollout status sts/redis-master
```
