# Monitoring, Alerting и Dashboards

Этот документ фиксирует итоговый observability-слой этапа B/C: из каких компонентов собран стек, какие сигналы он считает нормой, какие алерты уходят в почту, какие остаются только в UI, и как читать три provisioned dashboard-а без догадок.

## Что входит в стек

Observability-контур собирается в `deploy/kubernetes/observability` и разворачивается через `helmfile`. Базой служит `kube-prometheus-stack`: он поднимает `Prometheus Operator`, `Prometheus`, `Alertmanager`, `Grafana`, `kube-state-metrics` и `node-exporter`. Поверх него добавлены `blackbox-exporter` и `Probe`-ресурсы для synthetic availability checks, `Loki` для хранения логов и `Alloy` для чтения pod logs и отправки их в `loki-gateway`. Для ingress HTTP сигналов отдельно подключен `ServiceMonitor` на встроенный metrics endpoint `Traefik`.

Архитектурно слой разделен на три части. `recording-rules.yaml` считает стабильные SLI и rollout-сигналы. `alert-rules.yaml` строит поверх них symptom-level алерты. `dashboards-*.yaml` провиженят в Grafana три экрана: общий обзор, runtime `n8n` и внешний пользовательский путь. Такое разделение убирает дублирование длинных PromQL выражений и делает графики, alerting и ручные запросы в Prometheus консистентными.

## Monitoring as Code

Конфигурация лежит в репозитории и применяется как код, без ручной сборки через UI. Основные файлы такие: `deploy/kubernetes/observability/helmfile.yaml` как точка входа, `releases/recording-rules.yaml` для вычисляемых SLI, `releases/alert-rules.yaml` для пользовательских и operational alert-ов, `releases/dashboards-overview.yaml`, `releases/dashboards-n8n-runtime.yaml` и `releases/dashboards-public-endpoints.yaml` для Grafana dashboards, `releases/app-probes.yaml` и `blackbox-exporter.yaml` для synthetic probes, `releases/traefik-servicemonitor.yaml` для ingress metrics, `releases/loki.yaml` и `releases/alloy.yaml` для логов.

`Grafana` забирает dashboards через sidecar по label `grafana_dashboard: "1"`, поэтому JSON не импортируется вручную. `Alertmanager` routing задается в `deploy/kubernetes/observability/environments/prod/kube-prometheus-stack.values.yaml`. Это важно для защиты проекта: вся логика алертинга и визуализации воспроизводима из репозитория и не зависит от ручных кликов в UI.

## Как устроен текущий стек сигналов

Этот слой закрывает четыре золотых сигнала не на уровне лозунга, а на уровне конкретных источников данных. Availability считается через internal и public blackbox probes, а для внутренних зависимостей еще и через exporter `up`. Latency считается в двух независимых плоскостях: synthetic public probe latency и ingress server-side latency по Traefik histograms; для `n8n` поверх этого есть runtime-level event loop lag. Traffic берется из Traefik request counters и остается dashboard-only сигналом, потому что сам по себе не является actionable. Errors строятся через `*Down`, `*PublicEndpointDown`, ingress `5xx ratio`, burn-rate алерты и scrape quality сигналы. Saturation выражена через replica availability, process restarts, file descriptor pressure и event loop lag.

Ниже зафиксирован mapping между сигналом, метрикой и operational интерпретацией:

| Golden signal | Источник | Что показывает |
| --- | --- | --- |
| Availability | `probe_success`, exporter `up`, readiness | сервис доступен для пользователя, для кластера и для dependency-контуров |
| Latency | `probe_duration_seconds`, `traefik_router_request_duration_seconds_bucket`, `n8n_nodejs_eventloop_lag_seconds` | задержка внешнего пути, задержка ingress и внутреннее давление Node.js runtime |
| Traffic | `traefik_router_requests_total` | реальный HTTP поток через ingress для `n8n` и `wiki` |
| Errors | public/internal availability ratios, `traefik` 5xx, notification failures, scrape health | отказ, деградация SLO, ошибки ingress, проблемы мониторинга |
| Saturation | replica availability, restarts, FD ratio, event loop lag | приближение к лимитам и деградация runtime до полного outage |

## Alerting policy

Alerting здесь строится вокруг одного правила: email должен приходить только тогда, когда от оператора ожидается действие. History-style предупреждения, длинные SLO хвосты и bootstrap/deploy артефакты остаются видимыми в Alertmanager UI и Grafana, но не засоряют почту.

По operational смыслу набор правил делится на шесть групп. `Internal availability` ловит полную недоступность сервисов внутри кластера. `Public endpoints` проверяет пользовательский HTTPS путь, TLS и synthetic SLO. `Dependencies` отвечает за `postgres`, `redis`, backup-контур и scrape native `/metrics` у `n8n`. `n8n runtime` ловит проблемы процесса и rollout-состояния. `Self-monitoring` следит за самим observability-слоем. `Ingress HTTP` закрывает user-facing 5xx и p95 latency на Traefik.

### Полный список алертов и routing

| Alert | Severity | Что означает | Email |
| --- | --- | --- | --- |
| `N8nDown` | critical | `n8n` недоступен по internal blackbox probe | да |
| `WikiDown` | critical | `wiki` недоступна по internal blackbox probe | да |
| `OllamaDown` | critical | `ollama` недоступна по internal blackbox probe | да |
| `N8nAvailabilityDegraded` | warning | 30m internal availability `n8n` ниже SLO | нет |
| `WikiAvailabilityDegraded` | warning | 30m internal availability `wiki` ниже SLO | нет |
| `OllamaAvailabilityDegraded` | warning | 30m internal availability `ollama` ниже SLO | нет |
| `N8nPublicEndpointDown` | critical | внешний HTTPS путь `n8n` недоступен | да |
| `WikiPublicEndpointDown` | critical | внешний HTTPS путь `wiki` недоступен | да |
| `N8nPublicLatencyP95High` | warning | synthetic p95 latency `n8n` выше порога | нет |
| `WikiPublicLatencyP95High` | warning | synthetic p95 latency `wiki` выше порога | нет |
| `N8nTLSCertificateExpiringSoon` | warning | сертификат `n8n` истекает меньше чем через 14 дней | да |
| `WikiTLSCertificateExpiringSoon` | warning | сертификат `wiki` истекает меньше чем через 14 дней | да |
| `N8nAvailabilityBurnRateFast` | critical | быстрый расход public error budget `n8n` | нет |
| `N8nAvailabilityBurnRateSlow` | warning | медленный расход public error budget `n8n` | нет |
| `WikiAvailabilityBurnRateFast` | critical | быстрый расход public error budget `wiki` | нет |
| `WikiAvailabilityBurnRateSlow` | warning | медленный расход public error budget `wiki` | нет |
| `N8nMetricsTargetDown` | warning | `n8n` отвечает, но `/metrics` не скрейпится | да |
| `PostgresDown` | critical | exporter `postgres` недоступен | да |
| `RedisDown` | critical | exporter `redis` недоступен | да |
| `PostgresBackupMissing` | warning | CronJob backup отсутствует | да |
| `PostgresBackupFailed` | critical | backup stale или неуспешен | да |
| `N8nWebReplicaUnavailable` | warning | у `n8n-web` не хватает ready replicas | да |
| `N8nWorkerReplicaUnavailable` | warning | у `n8n-worker` не хватает ready replicas | да |
| `N8nEventLoopLagHigh` | warning | event loop lag `n8n` слишком высокий | да |
| `N8nFileDescriptorsHigh` | warning | `n8n` близок к лимиту file descriptors | да |
| `N8nPodRestartsTooOften` | warning | контейнеры `n8n` часто рестартуют | да |
| `N8nRolloutStuck` | warning | rollout `n8n` завис | да |
| `WikiRolloutStuck` | warning | rollout `wiki` завис | да |
| `OllamaRolloutStuck` | warning | rollout `ollama` завис | да |
| `PrometheusScrapeHealthDegraded` | warning | scrape quality core targets ниже 99% на 30m окне | нет |
| `AlertmanagerNotificationsDown` | critical | Alertmanager не доставляет уведомления | да |
| `AlertmanagerNoMetrics` | critical | Alertmanager не отдает notification metrics | да |
| `AlertmanagerNotificationsFailing` | warning | delivery success Alertmanager ниже 99% | да |
| `N8nIngress5xxHigh` | warning | ingress 5xx ratio `n8n` выше 5% | нет |
| `WikiIngress5xxHigh` | warning | ingress 5xx ratio `wiki` выше 5% | нет |
| `N8nIngressLatencyP95High` | warning | ingress p95 latency `n8n` выше 1s | нет |
| `WikiIngressLatencyP95High` | warning | ingress p95 latency `wiki` выше 1s | нет |

Отдельно от кастомных правил в Alertmanager также глушатся `Watchdog`, `InfoInhibitor` и upstream `severity=info`. Они не являются incident-level событиями и используются либо как meta-monitoring heartbeat, либо как inhibition-механика.

## Как работает suppression на deploy и bootstrap

Deploy-time noise режется не в Alertmanager, а в Prometheus-правилах. Для каждого сервиса (`n8n`, `wiki`, `ollama`) recording rules экспортируют четыре сигнала: `rollout:<service>_active` как live индикатор rollout-а, `rollout:<service>_recently_finished` как короткий recovery-хвост на 15 минут, `rollout:<service>_deploy_window` как generation-based fallback на 20 минут и `rollout:<service>_burn_cooldown` как длинный SLO cooldown на 75 минут. Для `n8n`, `wiki` и `ollama` также добавлен `rollout:<service>_bootstrap_window`, чтобы suppress накрывал первый холодный подъем чистого кластера.

Критические `*Down` и `*PublicEndpointDown` используют короткий suppressor через `recently_finished`, `deploy_window` и `bootstrap_window`. Это убирает false positive во время fresh install и штатного rollout-а, но не превращает сервис в долгий mute после завершения деплоя. Warning-level SLO и ingress правила используют только `burn_cooldown`, потому что их окна длиннее и они иначе продолжали бы шуметь как history tail.

## Как реализованы три дашборда

### Observability Overview

`Observability Overview` — это первый экран, который должен отвечать на вопрос, что горит сейчас и в какой зоне. В верхнем ряду лежат `n8n User Path`, `wiki User Path`, availability `ollama`, `postgres`, `redis`, `Alertmanager Health`, `Active Critical` и `Actionable Warning`. Здесь `n8n` и `wiki` сознательно показываются по public availability, а не по internal probe: это честнее для оператора и ближе к пользовательскому сценарию.

Ниже находятся `Application Availability 30m`, `Dependencies Health 30m`, `Core Scrape Health 30m`, `Restarts 6h by Namespace`, `Ingress Request Rate` и `Ingress 5xx Ratio`. Этот экран не должен использоваться для разбора event loop lag или file descriptors — такие сигналы вынесены в `n8n Runtime`.

`[Скриншот: Observability Overview после чистого deploy, когда top row уже выровнялся и видно Active Critical/Warning = 0]`

### n8n Runtime

`n8n Runtime` — это рабочий экран для разбора поведения самого `n8n`. В top row лежат `Availability 5m`, `Metrics Scrape 5m`, `Web Ready`, `Worker Ready`, `Lag Now`, `FD Usage`, `Runtime Restarts 6h` и `Deploy Window 20m`. Ниже находятся `Availability and Scrape`, `Memory`, `CPU Rate`, `Event Loop Lag`, `File Descriptors` и `Restarts by Container 6h`.

Этот дашборд отвечает не на вопрос “доступен ли сайт”, а на вопрос “почему именно `n8n` ведет себя плохо”. Если `Overview` показывает проблему только у `n8n`, следующий переход почти всегда сюда.

`[Скриншот: n8n Runtime со здоровым web/worker и отдельный скрин с rollout window / restart spike]`

### Public Endpoints / Edge

`Public Endpoints / Edge` показывает внешний пользовательский путь через HTTPS. В верхнем ряду лежат `n8n Public Availability 5m`, `wiki Public Availability 5m`, `n8n TLS Expiry`, `wiki TLS Expiry`, `n8n Probe p95 30m` и `wiki Probe p95 30m`. Ниже находятся `Public Availability Over Time`, `Public Endpoint Latency p95`, `Burn Rate Over Time`, `Ingress Request Rate`, `Ingress 5xx Ratio` и `Ingress p95 Latency`.

Synthetic probes и ingress metrics здесь намеренно живут рядом. Probes показывают, что видит внешний мониторинг. Ingress panels показывают, что реально обрабатывает Traefik. Это два разных угла зрения на один и тот же пользовательский путь.

`[Скриншот: Public Endpoints / Edge со здоровыми TLS и зелеными public availability панелями]`

## Что показывают дашборды сразу после cold start

После чистого подъема кластера часть `5m`, `30m`, `1h` и `6h` окон некоторое время остается красной или неполной, даже если сервис уже стабилен и почта молчит. Это нормальное поведение SLI windows, а не активная авария. `Availability 5m` и `Metrics Scrape 5m` выправляются быстрее, `30m` графики и burn-rate хвосты восстанавливаются заметно дольше. Если при этом `Web Ready`, `Worker Ready`, public probes, ingress 5xx и runtime метрики уже нормальные, значит это история bootstrap-а, а не текущий outage.

Эта же логика относится к `PrometheusScrapeHealthDegraded`: он смотрит на 30-минутное окно scrape quality и может жить как UI-only history signal после того, как targets уже вернулись в `UP`.

## Что проверять после rollout

После `helmfile -e prod sync` сначала нужно проверить наличие rules и dashboard ConfigMap:

```bash
cd deploy/kubernetes/observability
helmfile -e prod sync

kubectl -n observability get prometheusrule
kubectl -n observability get configmap | grep dashboard
```

Дальше имеет смысл проверить несколько базовых series в Prometheus:

```promql
sli:n8n_public_availability:ratio_5m
sli:n8n_metrics_target:ratio_5m
sli:alertmanager_notification_success:ratio_5m
up{job="n8n-web",namespace="n8n"}
up{job="observability-alertmanager",namespace="observability"}
```

Эти запросы покрывают пользовательский путь, native `/metrics`, delivery-пайплайн и наличие основных targets. Если они возвращают series, observability-контур после rollout собран корректно.

## Как читать инцидент по слоям

Если приходит `N8nPublicEndpointDown`, начинать нужно с `Public Endpoints / Edge`. Там видно, что сломалось именно у внешнего пути: availability, TLS, probe latency или ingress errors. Если публичная probe красная, а internal availability `n8n` жива, проблема почти наверняка находится между пользователем и ingress.

Если приходит `N8nMetricsTargetDown`, нужно переходить в `n8n Runtime`: пользовательский путь еще может отвечать, но `/metrics` уже потерян. Это тонкая operational проблема, а не outage.

Если приходит `AlertmanagerNotificationsDown` или `AlertmanagerNoMetrics`, смотреть нужно уже не на приложения, а на alerting pipeline. Для этого на `Overview` вынесен отдельный `Alertmanager Health`, а сам alert остается в email.

## Смежные документы

`docs/kubernetes_deploy/sli-slo.md` фиксирует сами SLI/SLO и логику их расчета. `deploy/kubernetes/observability/README.md` описывает файловую структуру observability-слоя и порядок применения через `helmfile`. Вместе эти документы закрывают архитектуру, operational policy и runtime-поведение observability-контура.
