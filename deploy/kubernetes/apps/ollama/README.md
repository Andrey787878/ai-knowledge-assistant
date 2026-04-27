# deploy/kubernetes/apps/ollama

## Что это
Слой Ollama для локальной LLM в кластере.

## Что ставится

- Ollama Deployment/Service/PVC
- NetworkPolicy
- опциональный model-pull Job (предзагрузка модели)

## Какие chart используются

- локальный chart `./chart` для runtime Ollama
- `../../../vendor_charts/raw` (upstream `bedag/raw`) для networkpolicy и model-pull job

## Основные файлы

- `helmfile.yaml` — точка входа
- `releases/ollama.yaml` — runtime
- `releases/networkpolicy.yaml` — сетевые правила
- `releases/model-pull-job.yaml` — загрузка модели
- `environments/prod/app.values.yaml` — runtime параметры
- `environments/prod/model.values.yaml` — параметры model-pull

## Зависимости

- `deploy/kubernetes/platform` уже применен (namespace `ollama`)

## Как применять

```bash
cd deploy/kubernetes/apps/ollama

# Проверка рендера
helm lint chart
helmfile -e prod build > /tmp/ollama-build.yaml

# Применение
helmfile -e prod sync
```

## Проверка

```bash
kubectl -n ollama get deploy,pods,svc,pvc,networkpolicy,job
kubectl -n ollama rollout status deploy/ollama
```

## Быстрая API-проверка

```bash
kubectl -n ollama port-forward svc/ollama-svc 11434:11434
curl -sSf http://127.0.0.1:11434/api/version
curl -sSf http://127.0.0.1:11434/api/tags
```
