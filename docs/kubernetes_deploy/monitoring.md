# Мониторинг, алертинг и дашборды

Этот документ описывает слой наблюдаемости этапов B/C: из каких компонентов
собран стек, какие сигналы он считает нормой, какие алерты уходят в почту,
какие остаются только в интерфейсе и как читать три подготовленных дашборда.

## Что входит в стек

Контур наблюдаемости собирается в `deploy/kubernetes/observability` и
разворачивается через `helmfile`. Базой служит `kube-prometheus-stack`: он
поднимает `Prometheus Operator`, `Prometheus`, `Alertmanager`, `Grafana`,
`kube-state-metrics` и `node-exporter`. Поверх него добавлены
`blackbox-exporter` и `Probe`-ресурсы для синтетических проверок доступности,
`Loki` для хранения логов и `Alloy` для чтения логов pod-ов и отправки их в
`loki-gateway`. Для HTTP-сигналов на ingress отдельно подключен
`ServiceMonitor` на встроенный endpoint метрик `Traefik`.

Архитектурно слой разделен на три части. `recording-rules.yaml` считает
устойчивые SLI и сигналы развертывания. `alert-rules.yaml` строит поверх них
симптомные алерты. `dashboards-*.yaml` провиженят в Grafana три экрана:
общий обзор, разбор `n8n` во время работы и внешний пользовательский путь.
Такое разделение убирает дублирование длинных PromQL-выражений и делает
графики, алертинг и ручные запросы в Prometheus согласованными.

## Наблюдаемость как код

Конфигурация лежит в репозитории и применяется как код, без ручной настройки
через интерфейс. Основные файлы такие:
`deploy/kubernetes/observability/helmfile.yaml` как точка входа,
`releases/recording-rules.yaml` для вычисляемых SLI,
`releases/alert-rules.yaml` для пользовательских и эксплуатационных алертов,
`releases/dashboards-overview.yaml`,
`releases/dashboards-n8n-runtime.yaml` и
`releases/dashboards-public-endpoints.yaml` для дашбордов Grafana,
`releases/app-probes.yaml` и `blackbox-exporter.yaml` для синтетических проб,
`releases/traefik-servicemonitor.yaml` для ingress-метрик,
`releases/loki.yaml` и `releases/alloy.yaml` для логов.

`Grafana` забирает дашборды через sidecar по label
`grafana_dashboard: "1"`, поэтому JSON не импортируется вручную.
Маршрутизация `Alertmanager` задается в
`deploy/kubernetes/observability/environments/prod/kube-prometheus-stack.values.yaml`.
Это важно для защиты проекта: вся логика алертинга и визуализации
воспроизводима из репозитория и не зависит от ручных кликов в интерфейсе.

## Как устроен текущий стек сигналов

Этот слой закрывает четыре золотых сигнала не на уровне лозунга, а на уровне
конкретных источников данных. Доступность считается через внутренние и внешние
blackbox-пробы; та же модель применяется и к внутренним зависимостям
`postgres` и `redis`, чтобы availability всегда означала реальную
доступность сервиса, а не только наличие exporter-метрик. Задержка считается в
двух независимых плоскостях: задержка синтетической внешней пробы и задержка
на ingress по гистограммам Traefik; для `n8n` поверх этого есть задержка цикла
событий Node.js. Трафик берется из счетчиков запросов Traefik и остается
сигналом только для дашбордов, потому что сам по себе не требует действия.
Ошибки строятся через `*Down`, `*PublicEndpointDown`, ingress `5xx ratio`,
burn-rate алерты и сигналы качества scrape. Насыщение выражено через
доступность реплик, перезапуски процессов, давление по file descriptors и
задержку цикла событий.

Ниже зафиксировано соответствие между сигналом, метрикой и эксплуатационной
интерпретацией:

| Золотой сигнал | Источник | Что показывает |
| --- | --- | --- |
| Доступность | `probe_success`, exporter `up`, readiness | сервис доступен для пользователя, для кластера и для контуров зависимостей |
| Задержка | `probe_duration_seconds`, `traefik_router_request_duration_seconds_bucket`, `n8n_nodejs_eventloop_lag_seconds` | задержка внешнего пути, задержка ingress и внутреннее давление на `n8n` |
| Трафик | `traefik_router_requests_total` | реальный HTTP-поток через ingress для `n8n` и `wiki` |
| Ошибки | public/internal availability ratios, `traefik` 5xx, notification failures, scrape health | отказ, деградация SLO, ошибки ingress, проблемы мониторинга |
| Насыщение | replica availability, restarts, FD ratio, event loop lag | приближение к лимитам и деградация до полного отказа |

## Политика уведомлений

Алертинг здесь строится вокруг одного правила: письмо должно приходить только
тогда, когда от оператора ожидается прямое действие. Исторические
предупреждения, длинные SLO-хвосты, runtime-симптомы и артефакты деплоя
остаются видимыми в Alertmanager и Grafana, но не засоряют почту.

По смыслу набор правил делится на шесть групп. `Internal availability`
ловит полную недоступность сервисов внутри кластера. `Public endpoints`
проверяет пользовательский HTTPS-путь, TLS и синтетические SLO.
`Dependencies` отвечает за `postgres`, `redis`, контур резервного копирования
и scrape нативного `/metrics` у `n8n`. `n8n runtime` ловит проблемы процесса
и состояния развёртывания. `Self-monitoring` следит за самим слоем
наблюдаемости. `Ingress HTTP` закрывает пользовательские `5xx` и
`p95 latency` на Traefik.

### Полный список алертов и маршрутизации

Почта здесь работает по модели явного списка. В письма уходят только:

- `N8nDown`
- `WikiDown`
- `OllamaDown`
- `N8nPublicEndpointDown`
- `WikiPublicEndpointDown`
- `N8nIngress5xxHigh`
- `WikiIngress5xxHigh`
- `N8nIngressLatencyP95High`
- `WikiIngressLatencyP95High`
- `PostgresDown`
- `RedisDown`
- `PostgresBackupFailed`
- `AlertmanagerNotificationsDown`
- `AlertmanagerNotificationsFailing`
- `AlertmanagerNoMetrics`

Отдельно настроено подавление по зависимостям. `RedisDown` подавляет
`N8nDown` и `N8nPublicEndpointDown`, если `n8n` ломается как следствие
отказа `redis`. `PostgresDown` подавляет те же производные сигналы у `n8n`,
а для `wiki` подавляет `WikiDown` и `WikiPublicEndpointDown`, если корневой
причиной инцидента становится отказ `postgres`. Это убирает каскад из
корневого алерта и пользовательских симптомов для одного и того же сбоя:
в почту уходит причина, а не весь веер следствий.

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
| `N8nMetricsTargetDown` | warning | `n8n` отвечает, но `/metrics` не скрейпится | нет |
| `PostgresDown` | critical | `postgres` недоступен по internal TCP blackbox probe | да |
| `RedisDown` | critical | `redis` недоступен по internal TCP blackbox probe | да |
| `PostgresBackupMissing` | warning | CronJob backup отсутствует | нет |
| `PostgresBackupFailed` | critical | backup stale или неуспешен | да |
| `N8nWebReplicaUnavailable` | warning | у `n8n-web` не хватает ready replicas | нет |
| `N8nWorkerReplicaUnavailable` | warning | у `n8n-worker` не хватает ready replicas | нет |
| `N8nEventLoopLagHigh` | warning | event loop lag `n8n` слишком высокий | нет |
| `N8nFileDescriptorsHigh` | warning | `n8n` близок к лимиту file descriptors | нет |
| `N8nPodRestartsTooOften` | warning | контейнеры `n8n` часто рестартуют | нет |
| `N8nRolloutStuck` | warning | rollout `n8n` завис | нет |
| `WikiRolloutStuck` | warning | rollout `wiki` завис | нет |
| `OllamaRolloutStuck` | warning | rollout `ollama` завис | нет |
| `PrometheusScrapeHealthDegraded` | warning | scrape quality core targets ниже 99% на 30m окне | нет |
| `AlertmanagerNotificationsDown` | critical | Alertmanager не доставляет уведомления | да |
| `AlertmanagerNoMetrics` | critical | Alertmanager не отдает notification metrics | да |
| `AlertmanagerNotificationsFailing` | warning | delivery success Alertmanager ниже 99% | да |
| `N8nIngress5xxHigh` | warning | ingress 5xx ratio `n8n` выше 5% | да |
| `WikiIngress5xxHigh` | warning | ingress 5xx ratio `wiki` выше 5% | да |
| `N8nIngressLatencyP95High` | warning | ingress p95 latency `n8n` выше 1s | да |
| `WikiIngressLatencyP95High` | warning | ingress p95 latency `wiki` выше 1s | да |

Все алерты, не входящие в явный список, остаются в Alertmanager и Grafana
через корневой `null` receiver. Отдельно от кастомных правил туда же попадают
`Watchdog`, `InfoInhibitor` и upstream `severity=info`. Они не являются
инцидентными событиями и используются либо как служебный heartbeat, либо как
механизм подавления.

Если ломается сам сервис, а не его зависимость, подавление не применяется.
Поэтому при ручной поломке `wiki` через потерю `Endpoints` ожидаемо приходят
оба письма: `WikiDown` как сигнал внутренней недоступности внутри кластера и
`WikiPublicEndpointDown` как сигнал отказа внешнего пользовательского пути
через ingress и HTTPS.

## Как работает подавление шума на deploy и bootstrap

Шум во время деплоя режется не в Alertmanager, а в правилах Prometheus. Для
каждого сервиса (`n8n`, `wiki`, `ollama`) recording rules экспортируют четыре
сигнала: `rollout:<service>_active` как живой индикатор развёртывания,
`rollout:<service>_recently_finished` как короткий хвост восстановления на
15 минут, `rollout:<service>_deploy_window` как дополнительную страховку на
20 минут и `rollout:<service>_burn_cooldown` как длинный SLO-хвост на
75 минут.

Критические `*Down` и `*PublicEndpointDown` используют короткое подавление
только через `recently_finished` и `deploy_window`. Этого достаточно, чтобы
не ловить шум деплоя, но при этом не скрывать реальную ручную поломку сервиса
на свежем кластере. Предупреждения уровня SLO и ingress-правила используют
только `burn_cooldown`, потому что их окна длиннее и иначе они продолжали бы
шуметь как исторический хвост.

## Как устроены три дашборда

### Observability Overview

`Observability Overview` — это первый экран, который должен отвечать на
вопрос, что горит сейчас и в какой зоне. В верхнем ряду лежат
`n8n User Path`, `wiki User Path`, availability `ollama`, `postgres`,
`redis`, `Alertmanager Health`, `Active Critical` и `Actionable Warning`.
Здесь `n8n` и `wiki` сознательно показываются по public availability, а
`postgres` и `redis` — по внутренним TCP blackbox probe, а не по scrape
exporter-а. Так верхний ряд остается единообразным: каждая карточка
доступности отвечает на вопрос «доступен ли сервис», а не «собираются ли с
него метрики».

Ниже находятся `Application Availability 30m`, `Dependencies Health 30m`,
`Core Scrape Health 30m`, `Restarts 6h by Namespace`, `Ingress Request Rate`
и `Ingress 5xx Ratio`. Этот экран не должен использоваться для разбора
event loop lag или file descriptors — такие сигналы вынесены в `n8n Runtime`.

`[Скриншот: Observability Overview после чистого deploy, когда top row уже выровнялся и видно Active Critical/Warning = 0]`

### n8n Runtime

`n8n Runtime` — это рабочий экран для разбора поведения самого `n8n`.
В верхнем ряду лежат `Availability 5m`, `Metrics Scrape 5m`, `Web Ready`,
`Worker Ready`, `Lag Now`, `FD Usage`, `Runtime Restarts 6h` и
`Deploy Window 20m`. Ниже находятся `Availability and Scrape`, `Memory`,
`CPU Rate`, `Event Loop Lag`, `File Descriptors` и
`Restarts by Container 6h`.

Этот дашборд отвечает не на вопрос «доступен ли сайт», а на вопрос
«почему именно `n8n` ведет себя плохо». Если `Overview` показывает проблему
только у `n8n`, следующий переход почти всегда сюда.

`[Скриншот: n8n Runtime со здоровым web/worker и отдельный скрин с rollout window и всплеском рестартов]`

### Public Endpoints / Edge

`Public Endpoints / Edge` показывает внешний пользовательский путь через
HTTPS. В верхнем ряду лежат `n8n Public Availability 5m`,
`wiki Public Availability 5m`, `n8n TLS Expiry`, `wiki TLS Expiry`,
`n8n Probe p95 30m` и `wiki Probe p95 30m`. Ниже находятся
`Public Availability Over Time`, `Public Endpoint Latency p95`,
`Burn Rate Over Time`, `Ingress Request Rate`, `Ingress 5xx Ratio` и
`Ingress p95 Latency`.

Синтетические пробы и ingress-метрики здесь намеренно живут рядом. Пробы
показывают, что видит внешний мониторинг. Панели ingress показывают, что
реально обрабатывает Traefik. Это два разных угла зрения на один и тот же
пользовательский путь.

`[Скриншот: Public Endpoints / Edge со здоровыми TLS и зелеными public availability панелями]`

## Что показывают дашборды сразу после cold start

После чистого подъема кластера часть окон `5m`, `30m`, `1h` и `6h` некоторое
время остается красной или неполной, даже если сервис уже стабилен и почта
молчит. Это нормальное поведение SLI-окон, а не активная авария.
`Availability 5m` и `Metrics Scrape 5m` выправляются быстрее, графики `30m`
и burn-rate хвосты восстанавливаются заметно дольше. Если при этом
`Web Ready`, `Worker Ready`, публичные пробы, ingress `5xx` и runtime-метрики
уже нормальные, значит это история холодного старта, а не текущий отказ.

Эта же логика относится к `PrometheusScrapeHealthDegraded`: он смотрит на
30-минутное окно качества scrape и может жить как сигнал только для
интерфейса после того, как targets уже вернулись в `UP`.

## Что проверять после rollout

После `helmfile -e prod sync` сначала нужно проверить наличие rules и
dashboard ConfigMap:

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

Эти запросы покрывают пользовательский путь, нативный `/metrics`, канал
доставки уведомлений и наличие основных targets. Если они возвращают series,
контур наблюдаемости после rollout собран корректно.

## Как читать инцидент по слоям

Если приходит `N8nPublicEndpointDown`, начинать нужно с
`Public Endpoints / Edge`. Там видно, что сломалось именно у внешнего пути:
доступность, TLS, задержка пробы или ingress-ошибки. Если публичная проба
красная, а внутренняя доступность `n8n` жива, проблема почти наверняка
находится между пользователем и ingress.

Если приходит `N8nMetricsTargetDown`, нужно переходить в `n8n Runtime`:
пользовательский путь еще может отвечать, но `/metrics` уже потерян. Это
тонкая эксплуатационная проблема, а не полный отказ.

Если приходит `AlertmanagerNotificationsDown` или `AlertmanagerNoMetrics`,
смотреть нужно уже не на приложения, а на контур доставки уведомлений. Для
этого на `Overview` вынесен отдельный `Alertmanager Health`, а сам alert
остается в email.

## Смежные документы

`docs/kubernetes_deploy/sli-slo.md` фиксирует сами SLI/SLO и логику их
расчета. `deploy/kubernetes/observability/README.md` описывает файловую
структуру observability-слоя и порядок применения через `helmfile`. Вместе
эти документы закрывают архитектуру, правила эксплуатации и поведение
observability-контура во время работы.
