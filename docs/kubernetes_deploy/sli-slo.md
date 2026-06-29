# SLI и SLO

Этот документ фиксирует набор SLI и SLO для этапа B. Он опирается только на
те сигналы, которые уже есть в кластере и доведены в репозитории до рабочего
состояния. Здесь нет метрик, которые пришлось бы добавлять в документацию без
реального источника данных.

## Что измеряется сейчас

Первый слой SLI закрывает три группы сигналов. Пользовательский слой отвечает на вопрос, доступен ли сервис снаружи или по внутреннему API. Слой внутренних зависимостей показывает, живы ли PostgreSQL и Redis. Слой наблюдаемости проверяет, что сам стек мониторинга продолжает собирать и доставлять сигналы, иначе остальные SLO теряют смысл.

Для `n8n`, `wiki` и `ollama` базовым сигналом выбрана доступность через
blackbox probe. Такой выбор подходит для single-node `k3s` на одной VM:
probe измеряет именно доступность сервиса, а не внутреннее состояние
процесса. Для `n8n` и `wiki` поверх этого добавлен отдельный публичный SLI
через HTTPS probe по доменам, чтобы слой мониторинга видел не только
внутренний ClusterIP-маршрут, но и реальный пользовательский путь через
ingress, DNS и TLS. Для `postgres` и `redis` используется та же модель:
внутренние TCP blackbox probe проверяют реальную доступность зависимости для
клиента, а не только наличие exporter-метрик. Для `Prometheus` и
`Alertmanager` используются эксплуатационные цели, которые показывают,
продолжает ли стек собирать targets и отправлять уведомления.

Для `n8n` и `wiki` дополнительно зафиксирован ingress HTTP-слой по метрикам
Traefik. Он не заменяет blackbox availability, а отвечает на другой вопрос:
сколько пользовательского трафика реально проходит через ingress, сколько из
него заканчивается `5xx` и какой `p95` server-side latency видит сам Traefik.
Это уже не синтетический сигнал, а SLI уровня реальных запросов по живому
трафику.

## Зафиксированный набор

Ниже набор разделен на сервисные SLO по доступности, пользовательские SLO по
качеству HTTP-пути и короткие эксплуатационные цели контура наблюдаемости. Это
разделение намеренное: не все полезные сигналы стоит описывать как один и тот
же тип SLO.

### Сервисные SLO по доступности

| Сервис | SLI | Источник | SLO |
| --- | --- | --- | --- |
| `n8n` | внутренняя доступность | blackbox-проверка `blackbox-n8n` | `99.5%` в месяц |
| `n8n` | внешняя доступность | blackbox-проверка `blackbox-public-n8n` | `99.5%` в месяц |
| `wiki` | внутренняя доступность | blackbox-проверка `blackbox-wiki` | `99.5%` в месяц |
| `wiki` | внешняя доступность | blackbox-проверка `blackbox-public-wiki` | `99.5%` в месяц |
| `ollama` | внутренняя доступность | blackbox-проверка `blackbox-ollama` | `99.0%` в месяц |
| `postgres` | доступность зависимости | blackbox-проверка `blackbox-postgres` | `99.9%` в месяц |
| `redis` | доступность зависимости | blackbox-проверка `blackbox-redis` | `99.9%` в месяц |

### Пользовательские SLO по качеству HTTP-пути

| Сервис | SLI | Источник | SLO |
| --- | --- | --- | --- |
| `n8n` | доля `5xx` на ingress | метрики роутеров Traefik | доля `5xx`-ответов за месяц не превышает `0.5%` |
| `wiki` | доля `5xx` на ingress | метрики роутеров Traefik | доля `5xx`-ответов за месяц не превышает `0.5%` |
| `n8n` | задержка на ingress | метрики роутеров Traefik | не менее `99%` 5-минутных окон за месяц имеют `p95 <= 1s` |
| `wiki` | задержка на ingress | метрики роутеров Traefik | не менее `99%` 5-минутных окон за месяц имеют `p95 <= 1s` |

### Операционные цели контура наблюдаемости

| Компонент | SLI | Источник | SLO |
| --- | --- | --- | --- |
| `prometheus` | успешность сбора метрик по обязательным целям | метрика `up` по обязательным целям | не ниже `99%` успешных проверок за `30 минут` |
| `alertmanager` | успешность доставки уведомлений | метрики доставки уведомлений Alertmanager | не ниже `99%` успешных уведомлений за `5 минут` |

## Как считаются SLI

Для availability у сервисов и зависимостей источником служат `Probe` ресурсы из `deploy/kubernetes/observability/releases/app-probes.yaml`. Внутренние probes отправляют запросы через `blackbox-exporter` на адреса `n8n`, `wiki`, `ollama`, `postgres` и `redis` внутри кластера. Для HTTP-сервисов используются HTTP-модули, для `postgres` и `redis` — TCP connect probes. Такой способ измерения отделяет доступность самого сервиса от внешнего DNS, TLS и perimeter-level firewall. Для `n8n` и `wiki` добавлен второй слой probes по публичным HTTPS доменам, чтобы отдельно считать публичную availability и строить burn-rate alerts уже по пользовательскому пути.

Пример проверки availability для `n8n` выглядит так:

```promql
avg_over_time(probe_success{job="blackbox-n8n"}[30d])
```

`wiki` и `ollama` считаются тем же способом, меняется только `job`.

Ingress-уровень для `n8n` и `wiki` считается по метрикам роутеров Traefik.
Объем запросов берется из `traefik_router_requests_total`, доля `5xx`
считается по подмножеству `code=~"5.."`, а `p95 latency` — через
`histogram_quantile` поверх
`traefik_router_request_duration_seconds_bucket`. В репозитории эти
вычисления собраны в recording rules
`sli:n8n_ingress_requests:rate5m`, `sli:wiki_ingress_requests:rate5m`,
`sli:n8n_ingress_5xx:ratio5m`, `sli:wiki_ingress_5xx:ratio5m`,
`sli:n8n_ingress_latency:p95_5m` и `sli:wiki_ingress_latency:p95_5m`.
Такой слой уже показывает реальную HTTP-картину по пользовательскому
маршруту, а не только синтетическую достижимость.

Для `postgres` и `redis` availability считается по внутренним TCP blackbox probe, а не по exporter `up`. Это важно для recovery- и demo-сценариев: если StatefulSet временно scaled to `0`, сервис теряет endpoint или зависимость перестает принимать соединения, дашборды и alert rules продолжают видеть именно недоступность зависимости, а не только пропажу метрик.

Эксплуатационные SLI для `Prometheus` и `Alertmanager` нужны не ради полноты
списка, а для самоконтроля слоя наблюдаемости. Если `Prometheus` перестал
успешно скрейпить `kube-state-metrics`, `node-exporter`, `postgres exporter`,
`redis exporter`, `alloy`, `blackbox-exporter` и `n8n-web`, остальные графики
и алерты становятся недостоверными. Если `Alertmanager` регулярно не
доставляет уведомления, алертинг присутствует только на бумаге.

## Где находятся источники сигналов

`blackbox` probes описаны в `deploy/kubernetes/observability/releases/app-probes.yaml`, а их цели задаются в `deploy/kubernetes/observability/environments/prod/app-probes.values.yaml`. Источник native app metrics для `n8n` находится в `deploy/kubernetes/apps/n8n/chart/templates/servicemonitor.yaml`, `deploy/kubernetes/apps/n8n/chart/templates/configmap.yaml` и `deploy/kubernetes/apps/n8n/chart/templates/service-web.yaml`. Exporter-ы `postgres` и `redis` продолжают использоваться для scrape health и диагностики, но availability самих зависимостей считается уже через blackbox probes. Notification health Alertmanager и scrape health Prometheus приходят из `kube-prometheus-stack`.

Проверка на кластере начинается с факта наличия targets и probes, а не с
построения дашбордов. Сначала имеет смысл убедиться, что `Probe`,
`ServiceMonitor` и exporter targets реально появились и перешли в `UP`, и
только после этого собирать `PrometheusRule` и Grafana dashboards поверх них.

## Recording rules и alert rules

Базовые SLI сначала собираются в recording rules, а уже затем используются в alert rules. Такой порядок убирает дублирование длинных PromQL-выражений между алертами, дашбордами и ручной диагностикой, а также дает один стабильный слой вычисленных series для доступности и эксплуатационного состояния.

Recording rules находятся в `deploy/kubernetes/observability/releases/recording-rules.yaml`. В них фиксируются серии `sli:n8n_availability:*`, `sli:wiki_availability:*`, `sli:ollama_availability:*`, `sli:n8n_public_availability:*`, `sli:wiki_public_availability:*`, `sli:n8n_metrics_target:*`, `sli:postgres_availability:*`, `sli:redis_availability:*`, `sli:prometheus_scrape_health:*`, `sli:alertmanager_notification_success:*`, а также ingress-layer серии `sli:n8n_ingress_requests:rate5m`, `sli:wiki_ingress_requests:rate5m`, `sli:n8n_ingress_5xx:ratio5m`, `sli:wiki_ingress_5xx:ratio5m`, `sli:n8n_ingress_latency:p95_5m` и `sli:wiki_ingress_latency:p95_5m`. Эти series используются как базовый слой для дашбордов и для алертинга без повторного вычисления исходных выражений в каждом правиле.

Для availability и metrics-target recording rules используется scalar fallback
через `or on() vector(0)`. Это важно для single-target сервисов и внутренних
зависимостей: если target исчезает полностью, например StatefulSet временно
scaled to `0` или `Service` теряет endpoint, Prometheus чаще отдает не `0`, а
пустую серию. Без такого fallback и панели, и alert rules видели бы не
недоступность, а отсутствие данных. С fallback исчезновение target-а
интерпретируется как availability `0`, что делает поведение дашбордов и
алертов согласованным.

Alert rules находятся в `deploy/kubernetes/observability/releases/alert-rules.yaml`. Набор теперь делится на алерты доступности, алерты публичного пути, алерты зависимостей, runtime-алерты `n8n`, самоконтроль слоя наблюдаемости и ingress HTTP-алерты. Критические алерты `N8nDown`, `WikiDown`, `OllamaDown`, `PostgresDown` и `RedisDown` закрывают полную недоступность сервисов и зависимостей. Публичный слой добавляет `N8nPublicEndpointDown`, `WikiPublicEndpointDown`, алерты истечения TLS, синтетические latency-алерты и burn-rate алерты для публичной availability `n8n` и `wiki`. Ingress HTTP-слой добавляет `N8nIngress5xxHigh`, `WikiIngress5xxHigh`, `N8nIngressLatencyP95High` и `WikiIngressLatencyP95High`, чтобы отдельным классом контролировать ошибки и задержки реального пользовательского трафика. Уровень warning используется для деградации availability по `N8nAvailabilityDegraded`, `WikiAvailabilityDegraded`, `OllamaAvailabilityDegraded`, для отдельного контроля `N8nMetricsTargetDown`, для сигналов резервного копирования `PostgresBackupMissing` и `PostgresBackupFailed`, а также для runtime-правил `N8nWebReplicaUnavailable`, `N8nWorkerReplicaUnavailable`, `N8nEventLoopLagHigh`, `N8nFileDescriptorsHigh`, `N8nPodRestartsTooOften`. Эксплуатационный слой дополнен `PrometheusScrapeHealthDegraded`, `AlertmanagerNotificationsDown` и `AlertmanagerNotificationsFailing`.

## Подавление шума при rollout: `rollout:<service>_*`

В `deploy/kubernetes/observability/releases/recording-rules.yaml` определено
по четыре recording rules на сервис (`n8n`, `wiki`, `ollama`):

- `rollout:<service>_active` — живой индикатор активного rolling update
  (`updated < spec`, `available < spec`, `ready < spec`, `replicas != spec`,
  `metadata_generation != observed_generation`).
- `rollout:<service>_recently_finished` —
  `max_over_time(rollout:<service>_active[15m]) > 0`. Короткий хвост на
  15 минут после `rollout:active`. Применяется для критических `*Down` и
  `*PublicEndpointDown`, чтобы подавление перекрывало окно восстановления
  probe-ов после завершения rolling update.
- `rollout:<service>_deploy_window` — дополнительный generation-based сигнал:
  `metadata_generation != observed_generation or changes(metadata_generation[20m]) > 0`.
  Он компенсирует race между началом выкладки, scrape kube-state-metrics и
  blackbox probes на single-replica workload.
- `rollout:<service>_burn_cooldown` —
  `max_over_time(rollout:<service>_active[75m]) > 0`. Длинный хвост на
  75 минут после `rollout:active`. Применяется для warning-уровня, потому что
  их окна съезжают заметно дольше.

Соответствие alert → suppression signal:

| Alert класс                                            | Suppression signal                              |
| ------------------------------------------------------ | ----------------------------------------------- |
| `*Down`, `*PublicEndpointDown` (critical, `for: 5m`)   | `unless on() (rollout:<service>_recently_finished or rollout:<service>_deploy_window)` |
| `*AvailabilityDegraded`, `*PublicLatencyP95High`, `*AvailabilityBurnRateFast/Slow`, `*Ingress5xxHigh`, `*IngressLatencyP95High` (warning, длинные windows) | `unless on() rollout:<service>_burn_cooldown` |
| `*RolloutStuck`                                         | `expr: rollout:<service>_active` (без suppressor) |
| `*TLSCertificateExpiringSoon`, dependency alerts, observability self-alerts | без rollout-gate |

Разделение сделано осознанно: критические алерты должны снова срабатывать уже через ~15 минут после настоящей деградации после деплоя, тогда как warning-сигналы SLO на длинных окнах (`1h`/`6h`) допустимо подавлять дольше, чтобы не плодить пару firing/resolved после штатного rollout.

Дополнительно маршрутизация Alertmanager (`deploy/kubernetes/observability/environments/prod/kube-prometheus-stack.values.yaml`) отправляет `*AvailabilityDegraded`, `*AvailabilityBurnRateFast` и `*BurnRateSlow` в `null` receiver. Эти алерты остаются видны в Alertmanager и Grafana, но не отправляются на email, в том числе как `send_resolved`. Это специально синхронизировано с подавлением на уровне Prometheus: даже если длинный хвост probe-rate пробьет `unless on() rollout:_burn_cooldown`, в почту ничего не уйдет.

Отдельно от rollout-подавления в `Alertmanager` включено подавление по
корневой зависимости. `RedisDown` подавляет производные алерты
`N8nDown` и `N8nPublicEndpointDown`, если `n8n` деградирует из-за отказа
`redis`. `PostgresDown` делает то же для `n8n`, а также подавляет
`WikiDown` и `WikiPublicEndpointDown`, если `wiki` ломается вслед за
недоступным `postgres`. Это разделяет причину и следствие: в email остается
корневой инцидент зависимости, а производные симптомы остаются видны в UI
для расследования, но не превращаются в отдельные письма.
