# deploy/kubernetes/apps/wiki

## Назначение слоя

Этот слой разворачивает `Wiki.js` в Kubernetes и подключает его к внешнему
`PostgreSQL`, который поднимается отдельно в `apps/postgres`. Внутри слоя
собираются runtime-ресурсы приложения, ingress, секрет с параметрами доступа к
базе и сетевые ограничения.

`Wiki.js` здесь остается пользовательским сервисом, а не встроенной частью
базы знаний `n8n`. Поэтому у него отдельный namespace, отдельный ingress и
отдельная observability-модель через внешние blackbox-пробы и ingress-метрики.

## Что применяет Helmfile

Точкой входа служит `helmfile.yaml`. Сам runtime `Wiki.js` ставится через
`../../../vendor_charts/wiki`, а служебные объекты вокруг него собираются
через `../../../vendor_charts/raw`.

Основной runtime находится в `releases/wikijs.yaml`. Доступ к базе задается в
`releases/db-secret.yaml`. Redirect middleware для Traefik вынесен в
`releases/http-redirect-middleware.yaml`. Сетевые правила задаются в
`releases/networkpolicy.yaml`. Рабочие параметры лежат в
`environments/prod/app.values.yaml`.

## Что должно быть готово до применения

До этого слоя уже должен быть применен `deploy/kubernetes/platform`, чтобы в
кластере существовали namespace `wiki`, ingress-контур, `cert-manager` и
`ClusterIssuer`. Отдельно должен быть поднят `deploy/kubernetes/apps/postgres`,
потому что `Wiki.js` использует внешнюю базу `wikijs`.

На машине, с которой выполняется деплой, должны быть доступны `sops` и
`helm-secrets`, потому что пароль к базе и часть values читаются из
зашифрованных файлов.

## Как применять

```bash
cd deploy/kubernetes/apps/wiki

helmfile -e prod build > /tmp/wiki-build.yaml
helmfile -e prod sync
```

Слой использует upstream chart, поэтому локального `helm lint chart` здесь
нет. Основная проверка перед применением — это корректный рендер итогового
state через `helmfile build`.

## Как проверять после выкладки

Сначала имеет смысл проверить сами runtime-ресурсы:

```bash
kubectl -n wiki get deploy,pods,svc,ingress,secret,networkpolicy
kubectl -n wiki rollout status deploy/wikijs
```

После этого нужно убедиться, что выпущен TLS-сертификат и что оба входа
через ingress отвечают ожидаемо:

```bash
kubectl -n wiki get certificate,secret | grep wiki-tls
curl -I http://wiki.poluyanov.net
curl -I https://wiki.poluyanov.net
```

Если deployment уже `Ready`, а пользовательский путь по-прежнему недоступен,
следующий шаг — проверять ingress, selector сервиса и наличие `Endpoints`.
