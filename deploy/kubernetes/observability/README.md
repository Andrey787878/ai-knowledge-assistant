# deploy/kubernetes/observability

## Что это

Этот каталог содержит весь observability-слой кластера как код: метрики Kubernetes и приложений, synthetic probes, routing alert-ов, три provisioned Grafana dashboard-а и log pipeline на базе `Loki` и `Alloy`.

## Что разворачивается

Через `helmfile` поднимаются `kube-prometheus-stack`, `Prometheus`, `Alertmanager`, `Grafana`, `kube-state-metrics`, `node-exporter`, `blackbox-exporter`, `Loki`, `Alloy` и отдельный `ServiceMonitor` для метрик `Traefik`. В результате кластер получает один связанный стек для метрик, алертинга, дашбордов и логов.

## Основные файлы

`helmfile.yaml` остается точкой входа. `releases/recording-rules.yaml` считает SLI и rollout-сигналы. `releases/alert-rules.yaml` описывает symptom-level и operational alert-ы. `releases/dashboards-overview.yaml`, `releases/dashboards-n8n-runtime.yaml` и `releases/dashboards-public-endpoints.yaml` провиженят три дашборда Grafana. `releases/app-probes.yaml` и `releases/blackbox-exporter.yaml` задают synthetic probes, `releases/traefik-servicemonitor.yaml` подключает ingress metrics, `releases/loki.yaml` и `releases/alloy.yaml` собирают логи, `releases/networkpolicy.yaml` фиксирует allow-list модель сетевого доступа observability-контура.

Production values лежат в `environments/prod/kube-prometheus-stack.values.yaml`, общие labels и служебные значения — в `environments/prod/meta.values.yaml`, secrets — в `environments/prod/secrets.values.enc.yaml`.

## Что зафиксировано в этом слое

Текущая версия observability-контурa держится на трех опорах. Первая — monitoring as code: rules, dashboards и routing не настраиваются вручную в UI. Вторая — high-signal alerting policy: в email уходят только actionable alerts, history-style warnings остаются в UI. Третья — разделение по ролям дашбордов: `Observability Overview` отвечает на вопрос “что сломано”, `n8n Runtime` — “почему ломается именно n8n”, `Public Endpoints / Edge` — “что видит пользователь снаружи”.

Полное operational описание стека вынесено в `../../docs/kubernetes_deploy/monitoring.md`. Там зафиксированы компоненты стека, матрица alert routing, реализация четырех золотых сигналов, deploy/bootstrap suppression и места под скриншоты для финальной презентации. Набор SLI/SLO и логика вычисления recording rules описаны в `../../docs/kubernetes_deploy/sli-slo.md`.

## Как применять

```bash
cd deploy/kubernetes/observability

# Проверка helmfile-рендера
helmfile -e prod build > /tmp/observability-build.yaml

# Применение
helmfile -e prod sync
```

## Проверка

```bash
kubectl -n observability get pods,svc,pvc
kubectl -n observability get ingress
kubectl -n observability logs daemonset/alloy --tail=100
kubectl -n observability port-forward svc/observability-grafana 3000:80
kubectl -n observability get secret observability-grafana-admin -o jsonpath='{.data.admin-password}' | base64 -d
```

Grafana будет доступна на `https://grafana.poluyanov.net`, пользователь `admin`.
Alertmanager будет доступен на `https://alertmanager.poluyanov.net`.
Port-forward можно использовать для локальной проверки на `http://localhost:3000`.

## Важно

- Admin password хранится в `environments/prod/secrets.values.enc.yaml` и прокидывается через Secret `observability-grafana-admin`.
- SMTP app password для Alertmanager хранится в `environments/prod/secrets.values.enc.yaml` по ключу `alertmanager.smtp.auth_password`.
- Loki хранит логи 7 дней на `local-path` PVC размером `10Gi`.
- Alloy начинает читать новые строки после запуска и отправляет их в `loki-gateway`.
- Blackbox одновременно проверяет внутренние ClusterIP endpoints и публичные HTTPS endpoints `n8n` и `wiki`.
- Traefik metrics scrape теперь идет через `ServiceMonitor` из `kube-system`, что дает базу для ingress-level HTTP alerts и dashboard panels.
- NetworkPolicy применяются как explicit allow-list с namespace-wide default deny.
- Перед изменением IP ноды или Service CIDR обновите `network_policy` в `meta.values.yaml`.
- Во время rollout самого `blackbox-exporter` на single-node k3s может кратко срабатывать `TargetDown` по job `blackbox-exporter`, потому что hostNetwork port `9115` освобождается между старым и новым pod.
- `AvailabilityDegraded`, `AvailabilityBurnRateFast` и `AvailabilityBurnRateSlow` после rollout могут еще некоторое время существовать как history-style сигналы, потому что считаются по окнам `30m`, `1h` и `6h`, а не только по текущему состоянию.
- Email routing специально глушит `*AvailabilityDegraded`, `*AvailabilityBurnRateFast` и `*BurnRateSlow`: они остаются в Grafana и Alertmanager UI как SLO-history, но не шумят в почту.
- Traces пока не входят в этот слой.
