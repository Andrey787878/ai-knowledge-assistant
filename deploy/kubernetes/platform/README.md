# Этап B (k3s): platform слой (cert-manager + ClusterIssuer)

Ранбук для деплоя platform-слоя в Kubernetes-этапе:

- установка `cert-manager` через `helmfile`,
- создание `ClusterIssuer` (Let's Encrypt HTTP-01 через `traefik`).

Индекс этапной документации: [README этапа B](../../../docs/kubernetes_deploy/README.md)

## Быстрый старт

```bash
cd deploy/kubernetes/platform

# Проверьте доступ к кластеру
export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config-k3s}"
kubectl get nodes

# Проверьте инструменты
helm version
helmfile --version

# Заполните values
environments/prod/platform.values.yaml
environments/prod/cluster-issuer.values.yaml
environments/prod/cert-manager.values.yaml

# Рендер/деплой
helmfile -e prod lint
helmfile -e prod template > /tmp/platform-rendered.yaml
helmfile -e prod apply

# Проверка
kubectl -n cert-manager get pods -o wide
kubectl get clusterissuer
kubectl describe clusterissuer letsencrypt-prod
```

## Оглавление

- [Структура](#structure)
- [Критерии готовности](#definition-of-done)
- [Предусловия](#step-1)
- [Подготовьте values](#step-2)
- [Проверьте рендер перед apply](#step-3)
- [Деплой platform слоя](#step-4)
- [Проверка после деплоя](#step-5)

<a id="structure"></a>

## Структура

```text
deploy/kubernetes/platform
├── README.md
├── helmfile.yaml
├── releases
│   ├── cert-manager.yaml
│   └── cluster-issuer.yaml
└── environments
    └── prod
        ├── platform.values.yaml
        ├── cluster-issuer.values.yaml
        └── cert-manager.values.yaml
```

Назначение файлов:

- `helmfile.yaml` - точка входа `helmfile`, репозитории и wiring releases/env.
- `releases/cert-manager.yaml` - Helm release `jetstack/cert-manager`.
- `releases/cluster-issuer.yaml` - Helm release `bedag/raw` с `ClusterIssuer`.
- `environments/prod/platform.values.yaml` - версии chart'ов platform-слоя.
- `environments/prod/cluster-issuer.values.yaml` - параметры ACME issuer.
- `environments/prod/cert-manager.values.yaml` - ресурсы/опции чарта cert-manager.

<a id="definition-of-done"></a>

## Критерии готовности

- `helmfile -e prod apply` завершился без ошибок.
- `kubectl -n cert-manager get pods` показывает `Running` для компонентов cert-manager.
- `kubectl get clusterissuer` показывает `Ready=True` для целевого issuer.

<a id="step-1"></a>

## Предусловия

- k3s кластер уже поднят bootstrap-этапом.
- есть рабочий `kubeconfig` (обычно `~/.kube/config-k3s`).
- установлены `kubectl`, `helm`, `helmfile`.

Быстрые проверки:

```bash
export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config-k3s}"
kubectl get nodes
helm version
helmfile --version
```

<a id="step-2"></a>

## Подготовьте values

Отредактируйте значения:

`environments/prod/platform.values.yaml`:

- `cert_manager_chart_version`
- `raw_chart_version`

`environments/prod/cluster-issuer.values.yaml`:

- `cluster_issuer_name`
- `acme_email`
- `acme_server` (`staging` или `production`)
- `ingress_class` (по умолчанию `traefik`)
- `acme_account_private_key_secret_name`

`environments/prod/cert-manager.values.yaml`:

- `installCRDs`
- `prometheus.enabled`
- ресурсы `resources/webhook/cainjector`

<a id="step-3"></a>

## Проверьте рендер перед apply

```bash
cd deploy/kubernetes/platform
helmfile -e prod lint
helmfile -e prod template > /tmp/platform-rendered.yaml
```

Полезно быстро проверить, что `ClusterIssuer` попал в рендер:

```bash
rg -n "kind: ClusterIssuer|name: letsencrypt" /tmp/platform-rendered.yaml -S
```

<a id="step-4"></a>

## Деплой platform слоя

```bash
cd deploy/kubernetes/platform
helmfile -e prod apply
```

<a id="step-5"></a>

## Проверка после деплоя

```bash
kubectl -n cert-manager get pods -o wide
kubectl get clusterissuer
kubectl describe clusterissuer letsencrypt-prod
```

Проверка CRD cert-manager:

```bash
kubectl get crd | rg "cert-manager.io" -n
```

Ожидаемо:

- `cert-manager`, `cert-manager-webhook`, `cert-manager-cainjector` в `Running`,
- `ClusterIssuer` в `Ready=True`.
