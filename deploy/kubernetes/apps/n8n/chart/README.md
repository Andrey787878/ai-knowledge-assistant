# Helm Chart: n8n

## Назначение
Chart разворачивает `n8n` в queue-режиме:

- `web` (`n8n start`) для UI/API/webhook.
- `worker` (`n8n worker`) для фонового выполнения задач.

Chart отвечает только за runtime n8n. Импорт workflow и дополнительные ops-джобы находятся в отдельных release-файлах Helmfile.

## Что создается

- `Deployment` web
- `Deployment` worker
- `Service` web
- `Ingress` web (если `web.ingress.enabled=true`)
- `ConfigMap` с non-secret переменными окружения
- `Secret` с secret переменными окружения
- `helm test` pod (`templates/tests/test-connection.yaml`)

## Требования

- Helm 3.12+
- Kubernetes 1.27+
- Валидные значения по `values.schema.json`

## Контракт имен

Chart использует стабильные имена на базе `nameOverride` (а не `Release.Name`), например при `nameOverride: n8n`:

- `n8n-cm`
- `n8n-secret`
- `n8n-web`
- `n8n-worker`
- `n8n-web-svc`
- `n8n-web-ingress`

Это упрощает ссылки между release и ops-job.

## Обязательные значения для production

- `nameOverride`
- `web.ingress.host` (если ingress включен)
- `n8n.host`
- `n8n.editorBaseUrl`
- `n8n.webhookUrl`
- `postgres.host`
- `redis.host`
- `secrets.dbPassword`
- `secrets.wikiDbPassword`
- `secrets.redisPassword`
- `secrets.encryptionKey`

## Best Practices

- Хранить секреты только в encrypted values (например SOPS), не в открытом `app.values.yaml`.
- Фиксировать `image.tag` + `image.digest` для повторяемых деплоев.
- Проверять изменения через `helm lint` и `helm template` до `sync`.
- Не выключать `web/worker` probes в production.
- Менять schema/paths для agent memory только вместе с миграциями и smoke-проверками.

## Проверка chart локально

```bash
cd deploy/kubernetes/apps/n8n

helm lint chart
helm template n8n chart \
  -f environments/prod/app.values.yaml \
  --set secrets.dbPassword='dummy12345' \
  --set secrets.wikiDbPassword='dummy12345' \
  --set secrets.redisPassword='dummy12345' \
  --set secrets.encryptionKey='dummy123456789012345678901234567890' \
  > /tmp/n8n-chart-render.yaml
```

## Деплой

Рекомендуемый способ (через Helmfile):

```bash
cd deploy/kubernetes/apps/n8n
helmfile -e prod sync
```

Прямой Helm (если нужен отдельно от Helmfile):

```bash
cd deploy/kubernetes/apps/n8n

helm upgrade --install n8n ./chart \
  --namespace n8n \
  --create-namespace \
  -f environments/prod/app.values.yaml \
  --set secrets.dbPassword='CHANGE_ME_DB_PASSWORD' \
  --set secrets.wikiDbPassword='CHANGE_ME_WIKI_DB_PASSWORD' \
  --set secrets.redisPassword='CHANGE_ME_REDIS_PASSWORD' \
  --set secrets.encryptionKey='CHANGE_ME_LONG_RANDOM_ENCRYPTION_KEY'
```

## Проверка после деплоя

```bash
kubectl -n n8n get deploy,pods,svc,ingress
kubectl -n n8n rollout status deploy/n8n-web
kubectl -n n8n rollout status deploy/n8n-worker
helm test n8n -n n8n
```

## Обновление и удаление

```bash
# Upgrade
helm upgrade n8n ./chart -n n8n -f environments/prod/app.values.yaml

# Uninstall
helm uninstall n8n -n n8n
```
