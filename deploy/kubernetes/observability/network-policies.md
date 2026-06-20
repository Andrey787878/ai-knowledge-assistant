# Сетевые политики observability

## Модель изоляции

Namespace `observability` работает по модели явных разрешений. Релиз
`observability-networkpolicy` из файла `releases/networkpolicy.yaml` создаёт
правила для необходимых соединений и общий `observability-default-deny` для
всех остальных ingress- и egress-потоков.

Все политики находятся в одном Helmfile-релизе. Такая структура совпадает с
остальными слоями проекта: `n8n`, `wiki`, `postgres`, `redis` и `ollama` также
хранят сетевой контракт в одном файле `releases/networkpolicy.yaml`.

## Параметры окружения

Сетевые адреса задаются в `environments/prod/meta.values.yaml`, потому что они
зависят от конкретного k3s-контура.

| Параметр | Значение | Назначение |
| --- | --- | --- |
| `network_policy.kubernetes_api_service_cidr` | `10.43.0.1/32` | ClusterIP Kubernetes API на `443/tcp` |
| `network_policy.node_cidr` | `10.20.0.3/32` | Адрес k3s-ноды, API и node metrics |
| `network_policy.external_cidr` | `0.0.0.0/0` | Базовый CIDR для явно разрешённого внешнего egress |

Для Kubernetes API разрешены ClusterIP `10.43.0.1:443` и адрес ноды
`10.20.0.3:6443`. Это учитывает обработку NetworkPolicy до и после Service
DNAT. При изменении адреса ноды или Service CIDR значения необходимо обновить
до применения Helmfile.

## Матрица трафика

Таблица описывает все разрешённые соединения observability-компонентов.
Указаны порты контейнеров назначения, поскольку именно их проверяет
NetworkPolicy после маршрутизации через Service.

| Источник | Назначение | Порт | Причина |
| --- | --- | ---: | --- |
| Traefik | Grafana | `3000/tcp` | Публичный ingress Grafana |
| Traefik | Alertmanager | `9093/tcp` | Публичный ingress Alertmanager |
| Traefik | ACME HTTP-01 solver | `8089/tcp` | Выпуск и продление сертификатов |
| Grafana | Prometheus | `9090/tcp` | Источник метрик |
| Grafana | Alertmanager | `9093/tcp` | Источник алертов |
| Grafana | Loki gateway | `8080/tcp` | Источник логов |
| Sidecar-контейнеры Grafana | Kubernetes API | `443`, `6443/tcp` | Загрузка dashboards и datasources |
| Prometheus | Alertmanager | `9093`, `8080/tcp` | Доставка алертов и scrape метрик |
| Prometheus | Grafana | `3000/tcp` | Метрики Grafana |
| Prometheus | Prometheus Operator | `10250/tcp` | Метрики оператора |
| Prometheus | kube-state-metrics | `8080/tcp` | Метрики объектов Kubernetes |
| Prometheus | Alloy | `12345/tcp` | Метрики Alloy |
| Prometheus | Loki gateway и Loki | `8080`, `3100/tcp` | Метрики Loki |
| Prometheus | Blackbox Exporter | `9115/tcp` | Запуск probes и метрики exporter |
| Prometheus | PostgreSQL exporter | `9187/tcp` | Метрики PostgreSQL |
| Prometheus | Redis exporter | `9121/tcp` | Метрики Redis |
| Prometheus | k3s-нода | `9100`, `10250`, `10249/tcp` | node-exporter, kubelet, kube-proxy |
| Prometheus | CoreDNS | `9153/tcp` | Метрики DNS |
| Prometheus | Kubernetes API | `443`, `6443/tcp` | Обнаружение targets |
| Blackbox Exporter | n8n web | `5678/tcp` | Внутренняя HTTP health-проверка |
| Blackbox Exporter | Wiki.js | `3000/tcp` | Внутренняя HTTP health-проверка |
| Blackbox Exporter | Ollama | `11434/tcp` | Внутренняя HTTP health-проверка |
| Alloy | Loki gateway | `8080/tcp` | Отправка логов |
| Alloy | Kubernetes API | `443`, `6443/tcp` | Обнаружение pod-ов |
| Loki gateway | Loki | `3100/tcp` | Запись и чтение логов |
| Loki | Loki | `7946/tcp` | Memberlist |
| Sidecar правил Loki | Kubernetes API | `443`, `6443/tcp` | Загрузка правил |
| Alertmanager | SMTP | `587/tcp` | Отправка email-уведомлений |
| Operator и admission Jobs | Kubernetes API | `443`, `6443/tcp` | Reconcile и Helm hooks |
| kube-state-metrics | Kubernetes API | `443`, `6443/tcp` | Чтение объектов кластера |
| Все observability pod-ы | CoreDNS | `53/udp,tcp` | Разрешение имён |

Внешний egress разрешён только Alertmanager на `587/tcp`. Из диапазона
исключены RFC1918, carrier-grade NAT и link-local сети. Стандартная
NetworkPolicy не умеет разрешать FQDN, поэтому доступ ограничивается selector-ом
Alertmanager и конкретным портом SMTP.

## Проверки Blackbox

Blackbox Exporter напрямую проверяет ClusterIP-сервисы приложений. В
`app-probes.values.yaml` используются адреса
`n8n-web-svc.n8n.svc.cluster.local`, `wikijs.wiki.svc.cluster.local` и
`ollama-svc.ollama.svc.cluster.local`.

Destination namespace также должен разрешать соединение. Политика n8n допускает
Blackbox только к web pod-у на `5678/tcp`, политика Wiki.js — к приложению на
`3000/tcp`, политика Ollama — к API на `11434/tcp`.

PostgreSQL и Redis не проверяются Blackbox. Для них используются exporters,
которые отдают не только доступность процесса, но и профильные метрики СУБД.

Внутренние probes не проверяют публичный DNS, TLS-сертификаты, Security Group и
маршрут Traefik. Такие проверки следует добавлять отдельными edge probes, чтобы
не смешивать доступность приложения и внешнего периметра в одном сигнале.

## Межпространственные разрешения

Для namespace с default deny соединение должно быть разрешено с обеих сторон.
Prometheus получает egress к PostgreSQL exporter на `9187/tcp` и Redis exporter
на `9121/tcp`, а политики `db` и `n8n` разрешают соответствующий ingress только
от pod-а `observability-prometheus`.

Ограничение пользовательских CIDR остаётся на уровне Yandex Security Group и
UFW. NetworkPolicy приложения видит источником Traefik, а не исходный адрес
пользователя.

## Применение

Перед применением необходимо проверить context, адрес ноды и Service IP
Kubernetes API.

```bash
kubectl config current-context
kubectl get nodes -o wide
kubectl get svc kubernetes -o wide
kubectl -n kube-system get pods --show-labels
```

Локальный render проверяет шаблоны без обращения к кластеру.

```bash
cd deploy/kubernetes
helmfile -f helmfile.yaml -e ci template --skip-deps >/tmp/kubernetes-rendered.yaml
```

Сначала применяются destination-политики приложений, затем политика
observability.

```bash
helmfile -f apps/postgres/releases/networkpolicy.yaml \
  --state-values-file ../environments/prod/meta.values.yaml sync
helmfile -f apps/redis/releases/networkpolicy.yaml \
  --state-values-file ../environments/prod/meta.values.yaml sync
helmfile -f apps/n8n/releases/networkpolicy.yaml \
  --state-values-file ../environments/prod/meta.values.yaml sync
helmfile -f apps/wiki/releases/networkpolicy.yaml \
  --state-values-file ../environments/prod/meta.values.yaml sync
helmfile -f apps/ollama/releases/networkpolicy.yaml \
  --state-values-file ../environments/prod/meta.values.yaml sync
helmfile -f observability/releases/networkpolicy.yaml \
  --state-values-file ../environments/prod/meta.values.yaml sync
```

После первого включения используется обычный запуск корневого Helmfile.

```bash
helmfile -f helmfile.yaml -e prod sync
```

## Проверка после применения

Сначала проверяется наличие политик и совпадение labels с pod selectors.

```bash
kubectl -n observability get networkpolicy
kubectl -n observability get pods --show-labels
kubectl -n db get networkpolicy postgres-allow-ingress-metrics
kubectl -n n8n get networkpolicy redis-allow-ingress-metrics
```

Состояние targets и probes проверяется через API Prometheus.

```bash
kubectl -n observability port-forward svc/observability-prometheus 9090:9090
curl -fsS 'http://127.0.0.1:9090/api/v1/targets?state=active'
curl -fsS --get \
  --data-urlencode 'query=probe_success{job=~"blackbox-(n8n|wiki|ollama)"}' \
  'http://127.0.0.1:9090/api/v1/query'
```

Loki проверяется через gateway, который является единой точкой доступа для
Grafana и Alloy.

```bash
kubectl -n observability port-forward svc/loki-gateway 3100:80
curl -fsS http://127.0.0.1:3100/ready
curl -fsS 'http://127.0.0.1:3100/loki/api/v1/labels'
```

Логи компонентов позволяют найти соединение, которое было забыто в allow-list.

```bash
kubectl -n observability logs deployment/observability-grafana --all-containers --since=10m
kubectl -n observability logs daemonset/alloy --all-containers --since=10m
kubectl -n observability logs statefulset/loki --all-containers --since=10m
kubectl -n observability logs statefulset/alertmanager-observability-alertmanager --all-containers --since=10m
```

Отрицательный тест подтверждает, что pod без разрешающего selector-а может
использовать DNS, но не может обратиться к Prometheus.

```bash
kubectl -n observability run networkpolicy-denied-test \
  --image=busybox:1.37.0 --restart=Never \
  --command -- sh -c 'nslookup kubernetes.default.svc && ! wget -T 5 -qO- http://observability-prometheus:9090/-/ready'
kubectl -n observability logs networkpolicy-denied-test
kubectl -n observability delete pod networkpolicy-denied-test
```

## Аварийный rollback

Если обязательный поток не был учтён, временно удаляется только default deny.
Остальные allow-политики остаются активными и не мешают диагностике.

```bash
kubectl -n observability delete networkpolicy observability-default-deny
```

После исправления необходимо отрендерить и применить
`releases/networkpolicy.yaml`, проверить затронутый компонент и убедиться, что
Helmfile восстановил `observability-default-deny`.
