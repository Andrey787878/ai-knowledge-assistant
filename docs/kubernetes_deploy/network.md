# Сеть Kubernetes-деплоя (Этап B, single-node k3s)

## Цель сетевой модели

В Этапе B сеть построена как zero-trust для pod-сети при сохранении управляемого edge-доступа:

- публичный периметр ограничен CIDR allow-list,
- внутри кластера действует `default deny` и разрешены только явные сервисные потоки,
- ingress, TLS и ACME встроены в единую модель (Traefik + cert-manager).

## Схема сети

![Схема сети Kubernetes (Этап B)](./diagrams/network-topology.png)

## Источники правил (код)

- Terraform сеть и SG:
  - `deploy/terraform/k3s_deploy/network.tf`
  - `deploy/terraform/k3s_deploy/security.tf`
  - `deploy/terraform/k3s_deploy/variables.tf`
- Bootstrap host firewall:
  - `deploy/kubernetes/bootstrap/roles/firewall/defaults/main.yml`
  - `deploy/kubernetes/bootstrap/roles/firewall/tasks/ufw.yml`
- NetworkPolicy:
  - `deploy/kubernetes/apps/postgres/releases/networkpolicy.yaml`
  - `deploy/kubernetes/apps/n8n/releases/networkpolicy.yaml`
  - `deploy/kubernetes/apps/wiki/releases/networkpolicy.yaml`
  - `deploy/kubernetes/apps/redis/releases/networkpolicy.yaml`
  - `deploy/kubernetes/apps/ollama/releases/networkpolicy.yaml`

## Сетевые зоны и trust boundary

- одна VM `k3s` (по умолчанию subnet `10.20.0.0/24`) с public IP,
- внешний вход только через `80/443` edge-порты и ограниченный `6443`,
- основная изоляция сервисов реализована внутри кластера через NetworkPolicy.

## Многоуровневые сетевые контроли

### Cloud Security Group (внешний периметр)

`k3s_sg`:

- `22/tcp` из `firewall_admin_ssh_sources`
- `6443/tcp` из `kube_api_allowed_cidrs`
- `80/tcp` из `edge_http_cidrs` (по умолчанию `0.0.0.0/0`)
- `443/tcp` из `edge_allowed_client_cidrs`
- egress: `ANY -> 0.0.0.0/0`

### Host firewall (UFW, bootstrap)

- incoming: `deny`
- outgoing: `allow`
- явные allow:
  - `22/tcp` из `firewall_admin_ssh_sources`
  - `6443/tcp` из `kube_api_allowed_cidrs`
  - `80/tcp` из `edge_http_cidrs`
  - `443/tcp` из `edge_allowed_client_cidrs`

### Kubernetes NetworkPolicy (внутренний периметр)

- в `db`, `n8n`, `wiki`, `ollama` используется `default deny` (`Ingress + Egress`),
- далее добавляются только целевые `allow` policy,
- DNS разрешается отдельными egress policy на CoreDNS.

Важно: в `n8n` namespace policy Redis selector-ограничена (применяется к redis pod-ам), что корректно для этой роли.

## Модель доступов

### Административный доступ

- SSH к ноде: только `firewall_admin_ssh_sources`.
- Kubernetes API (`6443`): только `kube_api_allowed_cidrs`.
- Ограничения продублированы в SG и UFW.

### Пользовательский доступ

- UI-сервисы (`wiki`, `n8n`) публикуются через Traefik Ingress.
- Публичный HTTPS доступ ограничен `edge_allowed_client_cidrs`.
- `80/tcp` используется для ACME HTTP-01 и редиректа на HTTPS.

### Внутренние сервисные потоки (Ingress, pod-level)

| Источник                                  | Назначение                  | Порт        | Где задано                             |
| ----------------------------------------- | --------------------------- | ----------- | -------------------------------------- |
| `wiki/wikijs`, `n8n/*`, `db/postgres-ops` | `db/postgresql`             | `5432/tcp`  | `postgres/releases/networkpolicy.yaml` |
| `kube-system/traefik`, `n8n/*`            | `wiki/wikijs`               | `3000/tcp`  | `wiki/releases/networkpolicy.yaml`     |
| `kube-system/traefik`, `n8n/(web,worker)` | `n8n-web`                   | `5678/tcp`  | `n8n/releases/networkpolicy.yaml`      |
| `n8n/*`                                   | `n8n/redis`                 | `6379/tcp`  | `redis/releases/networkpolicy.yaml`    |
| `n8n/*`, `ollama/ollama-ops`              | `ollama (component=ollama)` | `11434/tcp` | `ollama/releases/networkpolicy.yaml`   |
| `kube-system/traefik`                     | `n8n/http01-solver`         | `8089/tcp`  | `n8n/releases/networkpolicy.yaml`      |
| `kube-system/traefik`                     | `wiki/http01-solver`        | `8089/tcp`  | `wiki/releases/networkpolicy.yaml`     |

Примечание: для Traefik учитываются оба варианта labels (`app.kubernetes.io/name=traefik` и `app=traefik`).

## Egress модель (pod-level)

| Источник                    | Назначение                 | Порт         | Где задано                             |
| --------------------------- | -------------------------- | ------------ | -------------------------------------- |
| `db/*`                      | DNS (`kube-dns`/`coredns`) | `53/udp,tcp` | `postgres/releases/networkpolicy.yaml` |
| `db/postgres-ops`           | `db/postgresql`            | `5432/tcp`   | `postgres/releases/networkpolicy.yaml` |
| `n8n/*`                     | `db/postgresql`            | `5432/tcp`   | `n8n/releases/networkpolicy.yaml`      |
| `n8n/*`                     | `n8n/redis`                | `6379/tcp`   | `n8n/releases/networkpolicy.yaml`      |
| `n8n/*`                     | `wiki/wikijs`              | `3000/tcp`   | `n8n/releases/networkpolicy.yaml`      |
| `n8n/*`                     | `ollama`                   | `11434/tcp`  | `n8n/releases/networkpolicy.yaml`      |
| `n8n/*`                     | DNS (`kube-dns`/`coredns`) | `53/udp,tcp` | `n8n/releases/networkpolicy.yaml`      |
| `wiki/wikijs`               | `db/postgresql`            | `5432/tcp`   | `wiki/releases/networkpolicy.yaml`     |
| `wiki/wikijs`               | DNS (`kube-dns`/`coredns`) | `53/udp,tcp` | `wiki/releases/networkpolicy.yaml`     |
| `n8n/redis`                 | DNS (`kube-dns`/`coredns`) | `53/udp,tcp` | `redis/releases/networkpolicy.yaml`    |
| `ollama/*`                  | DNS (`kube-dns`/`coredns`) | `53/udp,tcp` | `ollama/releases/networkpolicy.yaml`   |
| `ollama (component=ollama)` | Internet                   | `443/tcp`    | `ollama/releases/networkpolicy.yaml`   |
| `ollama/ollama-ops`         | `ollama` API               | `11434/tcp`  | `ollama/releases/networkpolicy.yaml`   |

Ключевой момент:

- Internet egress на `443/tcp` разрешен runtime pod-ам Ollama,
- DNS egress разрешен только workload-ам, которым он нужен.

## DNS и TLS в сетевой модели

- DNS A/AAAA для сервисных доменов указывают на public IP k3s-ноды.
- ACME HTTP-01 работает через Traefik + cert-manager + ClusterIssuer.
- Для совместимости с `default deny` отдельно разрешен доступ Traefik к pod-ам `acme.cert-manager.io/http01-solver=true` на `8089/tcp`.

Без этого правила выпуск/продление сертификатов может блокироваться policy-слоем.

## Что явно закрыто

- прямой ingress в app pods извне (вход только через Traefik и разрешенные internal selectors),
- pod-to-pod потоки, не описанные в `allow` policy,
- произвольный Internet egress для большинства приложений.

Примечание: pull container images выполняется node-level компонентами (`container runtime`/`kubelet`) и не ограничивается Kubernetes NetworkPolicy.

## Проверки: автоматические и операционные

### Автоматические (bootstrap smoke)

- bootstrap smoke проверяет базовую готовность k3s-кластера:
  - Kubernetes API `/readyz`,
  - node `Ready`,
  - pod'ы `kube-system`,
  - доступные replicas у CoreDNS,
  - доступные replicas у Traefik, если Traefik не отключен,
  - `deploy/kubernetes/bootstrap/playbooks/smoke.yml`

### Операционные (runbook)

```bash
kubectl -n db get networkpolicy
kubectl -n n8n get networkpolicy
kubectl -n wiki get networkpolicy
kubectl -n ollama get networkpolicy
```

```bash
kubectl -n db get pods --show-labels
kubectl -n n8n get pods --show-labels
kubectl -n wiki get pods --show-labels
kubectl -n ollama get pods --show-labels
```

```bash
cd deploy/kubernetes
helmfile -e prod build
```
