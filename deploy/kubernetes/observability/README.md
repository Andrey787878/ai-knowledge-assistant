# deploy/kubernetes/observability

## Что это

Observability-слой кластера: метрики Kubernetes, логи workload-ов, Prometheus, Alertmanager и Grafana.

## Что ставится

- `kube-prometheus-stack`
- Prometheus Operator
- Prometheus
- Alertmanager
- Grafana
- kube-state-metrics
- node-exporter
- Loki
- Alloy

## Какие chart используются

- `../vendor_charts/kube-prometheus-stack` (upstream `prometheus-community/kube-prometheus-stack` `86.2.3`)
- `../vendor_charts/loki` (upstream `grafana/loki` `7.0.0`)
- `../vendor_charts/alloy` (upstream `grafana/alloy` `1.10.0`)

## Основные файлы

- `helmfile.yaml` — точка входа
- `releases/grafana-admin-secret.yaml` — SOPS-backed admin secret для Grafana
- `releases/kube-prometheus-stack.yaml` — релиз monitoring stack
- `releases/loki.yaml` — хранилище логов
- `releases/alloy.yaml` — сбор логов Kubernetes pods
- `environments/prod/kube-prometheus-stack.values.yaml` — параметры production
- `environments/prod/secrets.values.enc.yaml` — production secrets
- `environments/prod/meta.values.yaml` — namespace и общие labels

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
- Traces пока не входят в этот слой.
