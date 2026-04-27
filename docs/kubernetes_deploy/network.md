# Сеть этапа B (NetworkPolicy)

## Область

Документ фиксирует сетевую модель Kubernetes-слоя этапа B.

## Архитектура и сеть этапа B

![Архитектура и сеть этапа B](./diagrams/network-topology.png)

## Модель безопасности

Во всех app-namespace используется один подход:

1. `default deny` для `Ingress` и `Egress`
2. точечные `allow` только под нужные сервисные потоки
3. отдельные правила для DNS (`53/udp`, `53/tcp`)

Все непредусмотренные потоки блокируются.

## Namespace и роли

- `db`: PostgreSQL и `postgres-ops` jobs
- `n8n`: n8n web/worker и Redis
- `wiki`: Wiki.js
- `ollama`: Ollama runtime и model-pull job
- `kube-system`: Traefik и CoreDNS

## Внешний вход

- Внешний трафик идет через Traefik.
- Основной ingress для `n8n-web` и `wiki/wikijs` идет от Traefik.
- Дополнительно разрешены внутренние ingress-потоки `n8n -> wiki` и `n8n/web+worker -> n8n-web`.
- Для ACME HTTP-01 разрешен ingress к solver pod-ам (`acme.cert-manager.io/http01-solver=true`) от Traefik на `8089/tcp`.
- `80/tcp` используется только для ACME HTTP-01 challenge и redirect на `443/tcp`.
- Прямой вход в pod-сети приложений отсутствует.

Cloud perimeter описан в:

- [Terraform](../../deploy/terraform/k3s_deploy/README.md)
- [Bootstrap](../../deploy/kubernetes/bootstrap/README.md)

## Разрешенные потоки

### Ingress

| Destination | Sources | Port |
|---|---|---|
| `db/postgresql` | `wiki/wikijs`, `n8n/*`, `db/postgres-ops` | `5432/tcp` |
| `wiki/wikijs` | `kube-system/traefik`, `n8n/*` | `3000/tcp` |
| `n8n-web` | `kube-system/traefik`, `n8n/web+worker` | `5678/tcp` |
| `n8n/redis` | `n8n/*` | `6379/tcp` |
| `ollama` | `n8n/*`, `ollama/ollama-ops` | `11434/tcp` |
| `wiki/http01-solver` | `kube-system/traefik` | `8089/tcp` |
| `n8n/http01-solver` | `kube-system/traefik` | `8089/tcp` |

### Egress

| Source | Destinations | Ports |
|---|---|---|
| `db/*` | DNS | `53/udp,tcp` |
| `db/postgres-ops` | `db/postgresql` | `5432/tcp` |
| `wiki/wikijs` | `db/postgresql`, DNS | `5432/tcp`, `53/udp,tcp` |
| `n8n/*` | `db/postgresql`, `n8n/redis`, `wiki/wikijs`, `ollama`, DNS | `5432`, `6379`, `3000`, `11434`, `53` |
| `n8n/redis` | DNS | `53/udp,tcp` |
| `ollama/*` | DNS | `53/udp,tcp` |
| `ollama/ollama` | Internet HTTPS | `443/tcp` |
| `ollama/ollama-ops` | `ollama` API | `11434/tcp` |

## Операционные проверки

```bash
kubectl -n db get networkpolicy
kubectl -n n8n get networkpolicy
kubectl -n wiki get networkpolicy
kubectl -n ollama get networkpolicy
```

Проверка, что сервисы соответствуют ожидаемым selector/labels:

```bash
kubectl -n n8n get pods --show-labels
kubectl -n wiki get pods --show-labels
kubectl -n ollama get pods --show-labels
kubectl -n db get pods --show-labels
```

## Change Checklist

Перед изменением NetworkPolicy:

1. зафиксировать текущие labels workload-ов
2. проверить, какие межсервисные потоки реально нужны
3. применить изменения через `helmfile -e prod sync`
4. выполнить rollout и connectivity проверки

## Источники правил

- [postgres networkpolicy](../../deploy/kubernetes/apps/postgres/releases/networkpolicy.yaml)
- [redis networkpolicy](../../deploy/kubernetes/apps/redis/releases/networkpolicy.yaml)
- [wiki networkpolicy](../../deploy/kubernetes/apps/wiki/releases/networkpolicy.yaml)
- [ollama networkpolicy](../../deploy/kubernetes/apps/ollama/releases/networkpolicy.yaml)
- [n8n networkpolicy](../../deploy/kubernetes/apps/n8n/releases/networkpolicy.yaml)
