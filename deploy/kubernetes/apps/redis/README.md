# deploy/kubernetes/apps/redis

## Назначение слоя

Этот слой разворачивает `Redis` для очередей `n8n` в `queue mode`. Помимо
runtime StatefulSet сюда входят секрет с паролем и сетевые правила, которые
разрешают доступ только прикладному слою `n8n`.

`Redis` намеренно живет в namespace `n8n`, потому что относится не к общей
платформе, а к конкретному прикладному контуру `n8n`. Это упрощает сетевую
модель и делает связь между очередями и их потребителями более явной.

## Что применяет Helmfile

Runtime ставится через `../../../vendor_charts/redis`, а служебные ресурсы
вокруг него собираются через `../../../vendor_charts/raw`.

Основной StatefulSet лежит в `releases/redis.yaml`. Секрет с паролем
собирается через `releases/auth-secret.yaml`. Сетевые правила задаются в
`releases/networkpolicy.yaml`. Рабочие параметры лежат в
`environments/prod/app.values.yaml`, а пароль Redis — в
`environments/prod/secrets.values.enc.yaml`.

## Что должно быть готово до применения

До этого слоя уже должен быть применен `deploy/kubernetes/platform`, чтобы в
кластере существовал namespace `n8n`. На машине, с которой выполняется деплой,
должны быть доступны `sops` и `helm-secrets`.

Сам по себе `Redis` не зависит от поднятого `n8n`, но практически смысл этого
слоя появляется только вместе с `apps/n8n`, который использует его как backend
очередей.

## Как применять

```bash
cd deploy/kubernetes/apps/redis

helmfile -e prod build > /tmp/redis-build.yaml
helmfile -e prod sync
```

Основная предварительная проверка здесь — это итоговый рендер секрета, runtime
параметров и network policy в одном state.

## Как проверять после выкладки

После применения достаточно проверить StatefulSet и связанные с ним ресурсы:

```bash
kubectl -n n8n get sts,pods,svc,secret,networkpolicy
kubectl -n n8n rollout status sts/redis-master
```

Если StatefulSet поднялся, но `n8n` продолжает деградировать по очередям,
следующий шаг — смотреть пароль, endpoint сервиса и сетевые правила между
`n8n` и `redis`.
