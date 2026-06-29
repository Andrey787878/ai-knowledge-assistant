# deploy/kubernetes/observability

## Назначение слоя

Этот каталог содержит весь observability-слой кластера как код. Здесь
собраны метрики Kubernetes и приложений, synthetic probes, alert routing,
дашборды Grafana и логовый контур на базе `Loki` и `Alloy`.

Слой не ограничивается одной системой мониторинга. Он объединяет метрики,
алертинг, логи и синтетические проверки в один воспроизводимый Helmfile-state,
который можно развернуть заново без ручной настройки через интерфейсы.

## Что применяет Helmfile

Точкой входа служит `helmfile.yaml`. Базой стека выступает
`kube-prometheus-stack`, который поднимает `Prometheus`, `Alertmanager`,
`Grafana`, `kube-state-metrics` и `node-exporter`. Поверх него добавляются
`blackbox-exporter`, `Loki`, `Alloy` и отдельный `ServiceMonitor` для метрик
`Traefik`.

Внутри слоя роли разделены по файлам. `releases/recording-rules.yaml` считает
SLI и сигналы rollout-окна. `releases/alert-rules.yaml` описывает симптомные и
эксплуатационные алерты. `releases/dashboards-overview.yaml`,
`releases/dashboards-n8n-runtime.yaml` и
`releases/dashboards-public-endpoints.yaml` провиженят три дашборда Grafana.
`releases/app-probes.yaml` и `releases/blackbox-exporter.yaml` задают
синтетические проверки. `releases/traefik-servicemonitor.yaml` подключает
ingress-метрики. `releases/loki.yaml` и `releases/alloy.yaml` собирают логи.
`releases/networkpolicy.yaml` фиксирует сетевую модель allow-list для
observability-контура.

Рабочие values лежат в `environments/prod/kube-prometheus-stack.values.yaml` и
`environments/prod/meta.values.yaml`. Секреты находятся в
`environments/prod/secrets.values.enc.yaml`.

## Что должно быть готово до применения

До этого слоя уже должны быть применены `deploy/kubernetes/platform` и
прикладные слои, которые он наблюдает. Без поднятых приложений `blackbox`
пробы, `ServiceMonitor` и часть recording rules не смогут собрать осмысленную
картину.

На машине, с которой выполняется деплой, должны быть доступны `helmfile`,
`sops` и `helm-secrets`, потому что routing, Grafana admin secret и SMTP
параметры Alertmanager читаются из зашифрованных values.

## Как устроен слой

Слой держится на трех опорных частях. Первая — наблюдаемость как код: rules,
dashboards и alert routing не собираются вручную в UI. Вторая — политика
высокосигнального алертинга: в email уходит только ограниченный набор корневых
и actionable-сигналов, а исторические и диагностические алерты остаются в
Grafana и Alertmanager. Третья — разделение дашбордов по вопросам:
`Observability Overview` отвечает на вопрос, где сейчас проблема,
`n8n Runtime` — что происходит внутри основного сервиса,
`Public Endpoints / Edge` — что видит пользователь снаружи.

Подробная документация по стеку вынесена отдельно в
`../../docs/kubernetes_deploy/monitoring.md` и
`../../docs/kubernetes_deploy/sli-slo.md`. Этот README оставляет только
структуру слоя, путь применения и практические проверки.

## Как применять

```bash
cd deploy/kubernetes/observability

helmfile -e prod build > /tmp/observability-build.yaml
helmfile -e prod sync
```

Перед фактическим `sync` полезно смотреть итоговый `build`, потому что в одном
state здесь соединяются storage, rules, probes, network policy, SMTP routing,
дашборды и логовый контур.

## Как проверять после выкладки

Сначала стоит проверить базовые ресурсы observability namespace:

```bash
kubectl -n observability get pods,svc,pvc
kubectl -n observability get ingress
```

После этого можно посмотреть, что Alloy читает логи, а Grafana и Alertmanager
доступны:

```bash
kubectl -n observability logs daemonset/alloy --tail=100
kubectl -n observability port-forward svc/observability-grafana 3000:80
kubectl -n observability get secret observability-grafana-admin -o jsonpath='{.data.admin-password}' | base64 -d
```

Grafana в рабочем контуре доступна по `https://grafana.poluyanov.net`.
Alertmanager доступен по `https://alertmanager.poluyanov.net`.
`port-forward` остается удобной локальной проверкой на `http://localhost:3000`.

## Что важно помнить

Admin password Grafana хранится в
`environments/prod/secrets.values.enc.yaml` и прокидывается через Secret
`observability-grafana-admin`. SMTP password для Alertmanager хранится там же,
по ключу `alertmanager.smtp.auth_password`.

`Loki` хранит логи семь дней на `local-path` PVC размером `10Gi`. `Alloy`
начинает читать новые строки после запуска и отправляет их в `loki-gateway`.
`blackbox-exporter` одновременно проверяет внутренние сервисы `n8n`, `wiki`,
`ollama`, `postgres`, `redis` и публичные HTTPS endpoints `n8n` и `wiki`.
Метрики `Traefik` собираются через `ServiceMonitor` из `kube-system`, что дает
базу для ingress-level HTTP сигналов.

Сетевые правила observability-контура применяются как explicit allow-list с
namespace-wide default deny. Если меняются IP ноды или сетевые диапазоны
кластера, соответствующие policy-значения в `meta.values.yaml` тоже нужно
обновлять.

Во время rollout самого `blackbox-exporter` на single-node `k3s` может
кратковременно появляться `TargetDown` по job `blackbox-exporter`, потому что
`hostNetwork` port `9115` освобождается между старым и новым pod. Длинные
SLO-сигналы вроде `AvailabilityDegraded` и `BurnRate*` тоже могут жить еще
некоторое время после штатного rollout, потому что считаются по окнам `30m`,
`1h` и `6h`, а не только по текущему состоянию.

Email routing в этом слое работает по модели явного списка. В письма уходят
только корневые отказы, отказы публичных точек входа, деградация качества на
ingress, `PostgresBackupFailed` и сигналы поломки доставки алертов. Остальные
алерты остаются в Grafana и Alertmanager как диагностические или исторические
сигналы.
