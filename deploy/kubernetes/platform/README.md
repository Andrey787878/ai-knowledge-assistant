# deploy/kubernetes/platform

## Что это
Платформенный слой кластера: базовые namespace и TLS-инфраструктура для ingress.

## Что ставится

- namespace: `db`, `n8n`, `wiki`, `ollama`
- `cert-manager`
- `ClusterIssuer` для Let's Encrypt (HTTP-01 через `traefik`)

## Какие chart используются

- `../../vendor_charts/cert-manager` (upstream `jetstack/cert-manager`)
- `../../vendor_charts/raw` (upstream `bedag/raw`) для namespace и `ClusterIssuer`

## Основные файлы

- `helmfile.yaml` — точка входа
- `releases/namespaces.yaml` — namespace
- `releases/cert-manager.yaml` — cert-manager
- `releases/cluster-issuer.yaml` — ClusterIssuer
- `environments/prod/*.values.yaml` — параметры production

## Как применять

```bash
cd deploy/kubernetes/platform

# Проверка рендера
helmfile -e prod build > /tmp/platform-build.yaml

# Применение
helmfile -e prod sync
```

## Проверка

```bash
kubectl get ns db n8n wiki ollama
kubectl -n cert-manager get pods
kubectl get clusterissuer
kubectl describe clusterissuer letsencrypt-prod
```

## Важно

- Для тестов используйте staging ACME URL в `environments/prod/cluster-issuer.values.yaml`.
- На production переключайте `acme_server` на production URL только после успешного staging-прогона.
