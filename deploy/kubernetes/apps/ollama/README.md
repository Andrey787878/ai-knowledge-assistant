# deploy/kubernetes/apps/ollama

## Назначение слоя

Этот слой разворачивает `Ollama` как локальный LLM-runtime внутри кластера.
Помимо основного deployment сюда входят PVC для моделей, сетевые правила и
опциональный job-контур для предзагрузки модели.

`Ollama` в этом проекте используется как внутренняя модель для `n8n`, поэтому
слой ориентирован не на публичный API-доступ, а на стабильный сервисный доступ
из прикладного контура.

## Что применяет Helmfile

Runtime ставится локальным chart из `./chart`, а служебные ресурсы вокруг него
собираются через `../../../vendor_charts/raw`.

Основной deployment находится в `releases/ollama.yaml`. Сетевые правила
задаются в `releases/networkpolicy.yaml`. Предзагрузка модели вынесена в
`releases/model-pull-job.yaml`. Рабочие параметры runtime лежат в
`environments/prod/app.values.yaml`, а параметры model pull — в
`environments/prod/model.values.yaml`.

## Что должно быть готово до применения

До этого слоя уже должен быть применен `deploy/kubernetes/platform`, чтобы в
кластере существовал namespace `ollama`. Если планируется предзагрузка модели,
значения для model pull должны быть заранее согласованы с runtime-параметрами
самого `Ollama`.

## Особенности runtime

`Ollama` использует persistent volume и в текущем контуре живет как
single-replica workload. Из-за этого слой ориентирован на предсказуемый
локальный inference-runtime, а не на горизонтальное масштабирование. Если
меняется модель, сначала имеет смысл проверить параметры `model-pull job`, а
потом уже разбирать runtime deployment.

## Как применять

```bash
cd deploy/kubernetes/apps/ollama

helm lint chart
helmfile -e prod build > /tmp/ollama-build.yaml
helmfile -e prod sync
```

Локальный chart здесь лучше прогонять через `helm lint`, потому что слой
содержит собственные шаблоны для deployment, PVC и runtime-конфигурации.

## Как проверять после выкладки

Базовая проверка начинается с deployment, pod-ов, PVC и model-pull job:

```bash
kubectl -n ollama get deploy,pods,svc,pvc,networkpolicy,job
kubectl -n ollama rollout status deploy/ollama
```

После этого можно отдельно проверить сам API `Ollama` через локальный
`port-forward`:

```bash
kubectl -n ollama port-forward svc/ollama-svc 11434:11434
curl -sSf http://127.0.0.1:11434/api/version
curl -sSf http://127.0.0.1:11434/api/tags
```

Если deployment `Ready`, но нужной модели нет в `api/tags`, причина обычно не
в runtime deployment, а в том, что model-pull job не выполнился или был
запущен с другими параметрами.
