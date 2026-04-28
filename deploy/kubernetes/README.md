# Этап B (single-node k3s): Kubernetes runbook

Единая точка запуска для Kubernetes-этапа (k3s + Helmfile).

Индекс документации этапа B: [README этапа B](../../docs/kubernetes_deploy/README.md)

![Архитектура и сеть этапа B](../../docs/kubernetes_deploy/diagrams/network-topology.png)

## Назначение

Этот этап разворачивает кластерный слой на single-node k3s:

- `platform` (cert-manager, ClusterIssuer, namespaces)
- `apps/postgres`
- `apps/redis`
- `apps/wiki`
- `apps/ollama`
- `apps/n8n`

## Быстрый старт

```bash
export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config-k3s}"

cd deploy/kubernetes
helmfile -e prod build > /tmp/k3s-build.yaml
helmfile -e prod sync
```

## Предусловия

- Terraform Этап B выполнен: `deploy/terraform/k3s_deploy`.
- Bootstrap Этап B выполнен: `deploy/kubernetes/bootstrap`.
- Установлены: `kubectl`, `helm`, `helmfile`, `sops`, `age`.
- Установлен Helm plugin `secrets`.
- Доступен `KUBECONFIG` к целевому k3s-кластеру.

## Подготовка

Проверки перед запуском:

```bash
export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config-k3s}"

kubectl get nodes
helm version
helmfile --version
helm plugin list
```

Порядок слоев задан в [helmfile.yaml](./helmfile.yaml):

1. `platform/helmfile.yaml`
2. `apps/postgres/helmfile.yaml`
3. `apps/redis/helmfile.yaml`
4. `apps/wiki/helmfile.yaml`
5. `apps/ollama/helmfile.yaml`
6. `apps/n8n/helmfile.yaml`

## Порядок запуска

Полный запуск:

```bash
cd deploy/kubernetes
helmfile -e prod build > /tmp/k8s-stage-build.yaml
helmfile -e prod sync
```

Точечный запуск одного слоя (пример `n8n`):

```bash
cd deploy/kubernetes/apps/n8n
helmfile -e prod sync
```

## Проверка после деплоя

```bash
kubectl get ns
kubectl -n cert-manager get pods
kubectl get clusterissuer

kubectl -n db get pods
kubectl -n n8n get deploy,pods,svc,ingress,job
kubectl -n wiki get deploy,pods,svc,ingress
kubectl -n ollama get deploy,pods,svc,pvc
```

Ключевые rollout-проверки:

```bash
kubectl -n n8n rollout status deploy/n8n-web
kubectl -n n8n rollout status deploy/n8n-worker
kubectl -n wiki rollout status deploy/wikijs
kubectl -n ollama rollout status deploy/ollama
```

Критерий готовности:

- `helmfile -e prod sync` завершился без ошибок;
- runtime workloads в `Running`;
- `ClusterIssuer` в `Ready=True`.

## Операционные команды

Обновление:

```bash
cd deploy/kubernetes
helmfile -e prod sync
```

Удаление слоя:

```bash
cd deploy/kubernetes
helmfile -e prod destroy
```

## Частые проблемы

`Kubernetes cluster unreachable`:

- проверьте `KUBECONFIG`;
- проверьте доступ к API `:6443`.

`failed to decrypt`:

- проверьте `~/.config/sops/age/keys.txt`;
- проверьте доступ к `*.enc.yaml`.

`n8n workflows import failed`:

- проверьте логи job:
  `kubectl -n n8n logs job/n8n-import-workflows --tail=200`.

`certificate not ready`:

- проверьте DNS и HTTP-01 доступность `80/tcp`;
- проверьте `kubectl describe clusterissuer letsencrypt-prod`.

## Связанная документация

- [Индекс Kubernetes-документации](../../docs/kubernetes_deploy/README.md)
- [Сеть](../../docs/kubernetes_deploy/network.md)
- [Ingress TLS и ACME](../../docs/kubernetes_deploy/ingress-tls-acme.md)
- [Ранбук по сертификатам](../../docs/kubernetes_deploy/certificates-runbook.md)
- [Резервное копирование и восстановление PostgreSQL](../../docs/kubernetes_deploy/backup-restore.md)
- [Эксплуатация и приемка](../../docs/kubernetes_deploy/operations.md)
- [Карта helmfile/release](../../docs/kubernetes_deploy/helmfiles-releases-map.md)

Локальные README по слоям:

- [Bootstrap k3s](./bootstrap/README.md)
- [Platform слой](./platform/README.md)
- [apps/postgres](./apps/postgres/README.md)
- [apps/redis](./apps/redis/README.md)
- [apps/wiki](./apps/wiki/README.md)
- [apps/ollama](./apps/ollama/README.md)
- [apps/n8n](./apps/n8n/README.md)
