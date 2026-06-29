# deploy/kubernetes/apps/n8n

## Назначение слоя

Этот слой разворачивает `n8n` в `queue mode` и собирает вокруг него весь
прикладной контур внутри Kubernetes: `web`, `worker`, ingress, импорт
workflow, native `/metrics` и сетевые правила доступа к `postgres`, `redis`
и `ollama`.

Здесь `n8n` рассматривается не как один deployment, а как сервис с
эксплуатационным окружением. Поэтому вместе с runtime-ресурсами применяются
`NetworkPolicy`, middleware для HTTP -> HTTPS, import job для workflow-файлов и
`ServiceMonitor`, который подключает `n8n-web` к общему контуру
наблюдаемости.

## Что применяет Helmfile

Точкой входа служит `helmfile.yaml`. Runtime ставится локальным chart из
`./chart`, а служебные объекты собираются через
`../../../vendor_charts/raw`.

Основной runtime описан в `releases/n8n.yaml`. Сетевые правила вынесены в
`releases/networkpolicy.yaml`. Redirect middleware для Traefik задается в
`releases/http-redirect-middleware.yaml`. Импорт workflow и credential bootstrap
собираются через `releases/workflows.yaml`.

Рабочие параметры runtime лежат в `environments/prod/app.values.yaml`.
Параметры import job и workflow bootstrap лежат в
`environments/prod/workflows.values.yaml`. Секреты `n8n` хранятся в
`environments/prod/secrets.values.enc.yaml` и читаются через `SOPS` и
`helm-secrets`.

## Что должно быть готово до применения

До этого слоя уже должен быть применен `deploy/kubernetes/platform`, чтобы в
кластере существовал namespace `n8n`, ingress-контур, `cert-manager` и базовые
CRD. Отдельно должны быть подняты `apps/postgres`, `apps/redis` и
`apps/ollama`, потому что `n8n` использует `postgres` как хранилище,
`redis` как backend для `queue mode`, а `ollama` как локальную модель.

Файлы workflow должны существовать в `n8n/workflows/*.json`. На машине, с
которой выполняется деплой, должны быть доступны `sops` и плагин
`helm-secrets`.

## Особенности runtime

`n8n` в этом контуре работает за `Traefik ingress`, поэтому приложение должно
доверять одному proxy hop. Это задается через `n8n.proxyHops: 1`, который
рендерится в `N8N_PROXY_HOPS`. Без этого `n8n` получает
`X-Forwarded-*`-заголовки от ingress, но не считает их доверенными и начинает
неправильно определять исходную схему и адрес клиента.

Workflow bootstrap всегда повторно импортирует workflow-файлы через CLI `n8n`,
затем публикует их и переводит нужные workflow в активное состояние.
Принудительный `kubectl rollout restart` после import job здесь намеренно
убран. Если `Deployment spec` меняется, `helm upgrade` и так инициирует
rolling update. Второй restart только удлиняет rollout и добавляет шум в
observability-слое.

## Как применять

```bash
cd deploy/kubernetes/apps/n8n

helm lint chart
helmfile -e prod build > /tmp/n8n-build.yaml
helmfile -e prod sync
```

`helm lint` здесь полезен не только для шаблонов chart. Он быстро ловит
ошибки в `values`, probe-конфигурации и схеме локального chart до фактической
синхронизации с кластером.

## Как проверять после выкладки

Сначала стоит проверить базовые ресурсы Kubernetes и результат import job:

```bash
kubectl -n n8n get deploy,pods,svc,ingress,job,networkpolicy
kubectl -n n8n get servicemonitor
kubectl -n n8n rollout status deploy/n8n-web
kubectl -n n8n rollout status deploy/n8n-worker
kubectl -n n8n logs job/n8n-import-workflows --tail=200
```

После этого имеет смысл проверить пользовательский путь и native metrics:

```bash
curl -I http://n8n.poluyanov.net
curl -I https://n8n.poluyanov.net

kubectl -n n8n port-forward svc/n8n-web-svc 5678:5678
curl -sSf http://127.0.0.1:5678/metrics
```

Если `/metrics` отвечает локально через `port-forward`, а в Prometheus по
прежнему нет scrape target, дальше смотреть нужно в labels сервиса и в
селекторы `ServiceMonitor`.

## Как проверить состояние workflow

Import job может завершиться успешно, но оператору иногда нужно отдельно
проверить, что нужные workflow действительно активированы. Для этого можно
выполнить:

```bash
kubectl -n n8n exec deploy/n8n-web -- \
  n8n list:workflow --only-active
```

Список активных workflow должен совпадать с ожидаемым набором из
`n8n/workflows/*.json`. Если нужный workflow импортирован, но не активирован,
его можно включить вручную через `n8n update:workflow --id=<id> --active=true`
или повторно применить слой так, чтобы изменился `Deployment spec`.

## Быстрая smoke-проверка

Для короткой прикладной проверки можно убедиться, что CLI `n8n` видит
workflow-хранилище и способен экспортировать уже загруженный workflow:

```bash
kubectl -n n8n exec deploy/n8n-web -- \
  n8n export:workflow --id=2d9f4b6a-1e44-4a71-8d52-b1c6f7a9d404 --output=/tmp/smoke.json
```
