# SLI и SLO

Этот документ фиксирует набор SLI и SLO для этапа B. Набор намеренно опирается только на те сигналы, которые уже есть в кластере или доведены в репозитории до рабочего состояния. Здесь нет метрик, которые пришлось бы "додумывать" без реального источника данных.

## Что измеряется сейчас

Первый слой SLI закрывает три группы сигналов. Пользовательский слой отвечает на вопрос, доступен ли сервис снаружи или по внутреннему API. Слой внутренних зависимостей показывает, живы ли PostgreSQL и Redis. Слой observability проверяет, что сам monitoring stack продолжает собирать и доставлять сигналы, иначе остальные SLO теряют смысл.

Для `n8n`, `wiki` и `ollama` базовым сигналом выбран availability через blackbox probe. Такой выбор подходит для single-node k3s на одной VM: probe измеряет именно доступность сервиса, а не внутреннее состояние процесса. Для `n8n` и `wiki` поверх этого добавлен отдельный публичный SLI через HTTPS probe по доменам, чтобы слой мониторинга видел не только внутренний ClusterIP маршрут, но и реальный пользовательский путь через ingress, DNS и TLS. Для `postgres` и `redis` в базовый набор входит availability по exporter-метрикам и readiness pod-а, потому что эти сервисы работают как внутренние зависимости, а не как публичные HTTP endpoints. Для `Prometheus` и `Alertmanager` используются operational objectives, которые показывают, продолжает ли стек собирать targets и отправлять уведомления.

Для `n8n` и `wiki` дополнительно зафиксирован ingress HTTP слой по Traefik router metrics. Он не заменяет blackbox availability, а отвечает на другой вопрос: сколько пользовательского трафика реально проходит через ingress, сколько из него заканчивается 5xx и какой p95 server-side latency видит сам Traefik. Это уже не synthetic сигнал, а request-level SLI по живому трафику.

## Зафиксированный набор

Ниже перечислены SLI и стартовые SLO, которые имеет смысл класть в runbook уже сейчас.

| Сервис         | SLI                                | Источник                             | Стартовый SLO                     |
| -------------- | ---------------------------------- | ------------------------------------ | --------------------------------- |
| `n8n`          | availability                       | blackbox probe `blackbox-n8n`        | `99.5%` monthly                   |
| `n8n`          | public availability                | blackbox probe `blackbox-public-n8n` | `99.5%` monthly                   |
| `wiki`         | availability                       | blackbox probe `blackbox-wiki`       | `99.5%` monthly                   |
| `wiki`         | public availability                | blackbox probe `blackbox-public-wiki`| `99.5%` monthly                   |
| `ollama`       | availability                       | blackbox probe `blackbox-ollama`     | `99.0%` monthly                   |
| `n8n`          | ingress 5xx ratio                  | Traefik router metrics               | `< 5%` for alert window           |
| `n8n`          | ingress p95 latency                | Traefik router metrics               | `< 1s` for alert window           |
| `wiki`         | ingress 5xx ratio                  | Traefik router metrics               | `< 5%` for alert window           |
| `wiki`         | ingress p95 latency                | Traefik router metrics               | `< 1s` for alert window           |
| `postgres`     | dependency availability            | postgres exporter `up` + readiness   | `99.9%` monthly                   |
| `redis`        | dependency availability            | redis exporter `up` + readiness      | `99.9%` monthly                   |
| `prometheus`   | scrape health for core targets     | метрика `up` по обязательным targets | `>= 99%` successful scrapes       |
| `alertmanager` | notification delivery success rate | метрики Alertmanager notifications   | `>= 99%` successful notifications |

## Как считаются SLI

Для availability у пользовательских сервисов источником служат `Probe` ресурсы из `deploy/kubernetes/observability/releases/app-probes.yaml`. Внутренние probes отправляют запросы через `blackbox-exporter` на ClusterIP адреса `n8n`, `wiki` и `ollama`. Такой способ измерения отделяет доступность самого приложения от внешнего DNS, TLS и perimeter-level firewall. Для `n8n` и `wiki` добавлен второй слой probes по публичным HTTPS доменам, чтобы отдельно считать публичную availability и строить burn-rate alerts уже по пользовательскому пути.

Пример проверки `n8n` availability выглядит так:

```promql
avg_over_time(probe_success{job="blackbox-n8n"}[30d])
```

`wiki` и `ollama` считаются тем же способом, меняется только `job`.

Ingress-level SLI для `n8n` и `wiki` считается по Traefik router metrics. Request volume берется из `traefik_router_requests_total`, 5xx ratio считается по подмножеству `code=~"5.."`, а p95 latency — через `histogram_quantile` поверх `traefik_router_request_duration_seconds_bucket`. В репозитории эти вычисления собраны в recording rules `sli:n8n_ingress_requests:rate5m`, `sli:wiki_ingress_requests:rate5m`, `sli:n8n_ingress_5xx:ratio5m`, `sli:wiki_ingress_5xx:ratio5m`, `sli:n8n_ingress_latency:p95_5m` и `sli:wiki_ingress_latency:p95_5m`. Такой слой уже показывает реальную HTTP-картину по пользовательскому маршруту, а не только synthetic reachability.

Для `postgres` и `redis` availability складывается из двух сигналов. Метрика exporter-а показывает, что Prometheus может получить ответ от dependency по ее протоколу. Readiness pod-а показывает, что workload находится в готовом состоянии с точки зрения Kubernetes. Один сигнал без второго дает слишком много ложных интерпретаций, поэтому в SLI учитываются оба.

Operational SLI для `Prometheus` и `Alertmanager` нужны не ради полноты списка, а для самоконтроля observability слоя. Если `Prometheus` перестал успешно скрейпить `kube-state-metrics`, `node-exporter`, `postgres exporter`, `redis exporter`, `alloy`, `blackbox-exporter` и `n8n-web`, остальные графики и алерты становятся недостоверными. Если `Alertmanager` регулярно не доставляет уведомления, alerting присутствует только на бумаге.

## Где находятся источники сигналов

`blackbox` probes описаны в `deploy/kubernetes/observability/releases/app-probes.yaml`, а их цели задаются в `deploy/kubernetes/observability/environments/prod/app-probes.values.yaml`. Источник native app metrics для `n8n` находится в `deploy/kubernetes/apps/n8n/chart/templates/servicemonitor.yaml`, `deploy/kubernetes/apps/n8n/chart/templates/configmap.yaml` и `deploy/kubernetes/apps/n8n/chart/templates/service-web.yaml`. Availability внутренних зависимостей обеспечивают exporter-ы в `deploy/kubernetes/apps/postgres/environments/prod/app.values.yaml` и `deploy/kubernetes/apps/redis/environments/prod/app.values.yaml`. Notification health Alertmanager и scrape health Prometheus приходят из `kube-prometheus-stack`.

Проверка на кластере начинается с факта наличия targets и probes, а не с построения дашбордов. Сначала имеет смысл убедиться, что `Probe`, `ServiceMonitor` и exporter targets реально появились и перешли в `UP`, и только после этого собирать `PrometheusRule` и Grafana dashboards поверх них.

## Recording rules и alert rules

Базовые SLI сначала собираются в recording rules, а уже затем используются в alert rules. Такой порядок убирает дублирование длинных PromQL выражений между алертами, дашбордами и ручной диагностикой, а также дает один стабильный слой вычисленных series для availability и operational health.

Recording rules находятся в `deploy/kubernetes/observability/releases/recording-rules.yaml`. В них фиксируются серии `sli:n8n_availability:*`, `sli:wiki_availability:*`, `sli:ollama_availability:*`, `sli:n8n_public_availability:*`, `sli:wiki_public_availability:*`, `sli:n8n_metrics_target:*`, `sli:postgres_availability:*`, `sli:redis_availability:*`, `sli:prometheus_scrape_health:*`, `sli:alertmanager_notification_success:*`, а также ingress-layer серии `sli:n8n_ingress_requests:rate5m`, `sli:wiki_ingress_requests:rate5m`, `sli:n8n_ingress_5xx:ratio5m`, `sli:wiki_ingress_5xx:ratio5m`, `sli:n8n_ingress_latency:p95_5m` и `sli:wiki_ingress_latency:p95_5m`. Эти series используются как базовый слой для дашбордов и для алертинга без повторного вычисления исходных выражений в каждом правиле.

Alert rules находятся в `deploy/kubernetes/observability/releases/alert-rules.yaml`. Набор теперь делится на availability alerts, public endpoint alerts, dependency alerts, `n8n` runtime alerts, observability self-monitoring и ingress HTTP alerts. Критические алерты `N8nDown`, `WikiDown`, `OllamaDown`, `PostgresDown` и `RedisDown` закрывают полную недоступность сервисов и зависимостей. Публичный слой добавляет `N8nPublicEndpointDown`, `WikiPublicEndpointDown`, TLS expiry alerts, synthetic latency alerts и burn-rate alerts для публичной availability `n8n` и `wiki`. Ingress HTTP слой добавляет `N8nIngress5xxHigh`, `WikiIngress5xxHigh`, `N8nIngressLatencyP95High` и `WikiIngressLatencyP95High`, чтобы отдельным классом контролировать ошибки и задержки реального пользовательского трафика. Warning-уровень используется для деградации availability по `N8nAvailabilityDegraded`, `WikiAvailabilityDegraded`, `OllamaAvailabilityDegraded`, для отдельного контроля `N8nMetricsTargetDown`, для backup-сигналов `PostgresBackupMissing` и `PostgresBackupFailed`, а также для runtime правил `N8nWebReplicaUnavailable`, `N8nWorkerReplicaUnavailable`, `N8nEventLoopLagHigh`, `N8nFileDescriptorsHigh`, `N8nPodRestartsTooOften`. Operational слой дополнен `PrometheusScrapeHealthDegraded`, `AlertmanagerNotificationsDown` и `AlertmanagerNotificationsFailing`.

## Rollout suppression: `rollout:<service>_*` recording rules

В `deploy/kubernetes/observability/releases/recording-rules.yaml` определено по три recording rules на сервис (`n8n`, `wiki`, `ollama`):

- `rollout:<service>_active` — live индикатор активного rolling update (`updated < spec`, `available < spec`, `ready < spec`, `replicas != spec`, `metadata_generation != observed_generation`). Ранее содержал дополнительный клоз `changes(kube_deployment_metadata_generation[10m]) > 0` как неаккуратный cooldown; он убран — cooldown теперь явный сигнал отдельной recording rule.
- `rollout:<service>_recently_finished` — `max_over_time(rollout:<service>_active[15m]) > 0`. Короткий хвост на 15 минут после `rollout:active`. Применяется для критических `*Down` и `*PublicEndpointDown` алертов, чтобы suppress накрывал окно восстановления probe-ов после завершения rolling update (порядка `for: 5m` окна восстановления плюс margin), но не превращался в многочасовое mute при настоящих инцидентах.
- `rollout:<service>_deploy_window` — generation-based fallback signal: `metadata_generation != observed_generation or changes(metadata_generation[20m]) > 0`. Он компенсирует race между началом deploy, kube-state-metrics scrape и blackbox probes на single-replica workloads. Для `n8n-web` это дополнительная страховка поверх `maxUnavailable: 0`, для `ollama` — основной suppressor во время intentional `Recreate` rollout с RWO PVC.
- `rollout:<service>_burn_cooldown` — `max_over_time(rollout:<service>_active[75m]) > 0`. Длинный хвост на 75 минут после `rollout:active`. Применяется для warning-уровня (degraded availability, public latency, burn-rate, ingress alerts), потому что их windows съезжают заметно дольше (до 1h для `BurnRateFast`-составной).

Соответствие alert → suppression signal:

| Alert класс                                            | Suppression signal                              |
| ------------------------------------------------------ | ----------------------------------------------- |
| `*Down`, `*PublicEndpointDown` (critical, `for: 5m`)   | `unless on() (rollout:<service>_recently_finished or rollout:<service>_deploy_window)` |
| `*AvailabilityDegraded`, `*PublicLatencyP95High`, `*AvailabilityBurnRateFast/Slow`, `*Ingress5xxHigh`, `*IngressLatencyP95High` (warning, длинные windows) | `unless on() rollout:<service>_burn_cooldown` |
| `*RolloutStuck`                                         | `expr: rollout:<service>_active` (без suppressor) |
| `*TLSCertificateExpiringSoon`, dependency alerts, observability self-alerts | без rollout-gate |

Разделение сделано осознанно: критические alert-ы должны снова срабатывать уже через ~15 минут после настоящей пост-deploy деградации, тогда как warning-level SLO-сигналы на длинных windows (1h/6h) допустимо подавать с более длинным окном silence, чтобы не плодить post-rollout firing/resolved-пару.

Дополнительно Alertmanager routing (`deploy/kubernetes/observability/environments/prod/kube-prometheus-stack.values.yaml`) отсылает `*AvailabilityDegraded`, `*AvailabilityBurnRateFast` и `*BurnRateSlow` в null receiver. Эти alert-ы остаются видны в Alertmanager UI и Grafana, но не отправляются на email, в том числе `send_resolved`. Это специально синхронизировано с prometheus-level suppression: даже если длинный tail probe-rate пробьёт `unless on() rollout:_burn_cooldown`, на email ничего не уйдёт.
