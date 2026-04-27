# Helm Chart: ollama

## Назначение
Chart разворачивает single-instance `Ollama` в Kubernetes для внутреннего API inference.

## Что создается

- `Deployment` ollama (`strategy: Recreate`)
- `Service` (`ClusterIP` по умолчанию)
- `ConfigMap` с runtime env
- `PersistentVolumeClaim` (если `persistence.enabled=true` и `persistence.existingClaim` пуст)
- `helm test` pod (`templates/tests/test-api.yaml`)

## Требования

- Helm 3.12+
- Kubernetes 1.27+
- Валидные значения по `values.schema.json`

## Контракт имен

Chart использует стабильные имена на базе `nameOverride`, например при `nameOverride: ollama`:

- `ollama` (Deployment)
- `ollama-svc`
- `ollama-cm`
- `ollama-pvc` (если PVC создается chart)

## Обязательные значения для production

- `nameOverride`
- `ollama.env.OLLAMA_HOST`
- `ollama.env.OLLAMA_KEEP_ALIVE`
- `persistence.enabled` и параметры storage (`existingClaim` или `storageClass/size/accessModes`)

## Best Practices

- Фиксировать `image.tag` + `image.digest`.
- Для production использовать persistent volume (не ephemeral storage).
- Проверять API через `helm test` после каждого обновления.
- Держать `securityContext` и `podSecurityContext` включенными.
- Не отключать probes без реальной причины (иначе сложнее автолечение pod).

## Проверка chart локально

```bash
cd deploy/kubernetes/apps/ollama

helm lint chart
helm template ollama chart \
  -f environments/prod/app.values.yaml \
  > /tmp/ollama-chart-render.yaml
```

## Деплой

Рекомендуемый способ (через Helmfile):

```bash
cd deploy/kubernetes/apps/ollama
helmfile -e prod sync
```

Прямой Helm:

```bash
cd deploy/kubernetes/apps/ollama

helm upgrade --install ollama ./chart \
  --namespace ollama \
  --create-namespace \
  -f environments/prod/app.values.yaml
```

## Проверка после деплоя

```bash
kubectl -n ollama get deploy,pods,svc,pvc
kubectl -n ollama rollout status deploy/ollama
helm test ollama -n ollama
```

Быстрая API-проверка:

```bash
kubectl -n ollama port-forward svc/ollama-svc 11434:11434
curl -sSf http://127.0.0.1:11434/api/version
curl -sSf http://127.0.0.1:11434/api/tags
```

## Обновление и удаление

```bash
# Upgrade
helm upgrade ollama ./chart -n ollama -f environments/prod/app.values.yaml

# Uninstall
helm uninstall ollama -n ollama
```
