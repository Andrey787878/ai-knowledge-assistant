# Эксплуатация и приемка (Этап B)

## Область

Документ описывает эксплуатационный процесс этапа B (single-node k3s) и критерии приемки релиза.

## Порядок этапа B

1. Terraform: `init -> plan -> apply` в `deploy/terraform/k3s_deploy`.
2. Bootstrap k3s: Ansible в `deploy/kubernetes/bootstrap`.
3. Platform: `deploy/kubernetes/platform`.
4. Apps: `deploy/kubernetes/apps` (`postgres`, `redis`, `wiki`, `ollama`, `n8n`).

Главный ранбук Kubernetes-слоя:
[deploy/kubernetes/README.md](../../deploy/kubernetes/README.md).

Карта helmfile/release структуры:
[helmfiles-releases-map.md](./helmfiles-releases-map.md).

## Внутренний порядок Kubernetes-деплоя

Порядок применения задается агрегирующим `deploy/kubernetes/helmfile.yaml`:

1. `platform/helmfile.yaml`
2. `apps/postgres/helmfile.yaml`
3. `apps/redis/helmfile.yaml`
4. `apps/wiki/helmfile.yaml`
5. `apps/ollama/helmfile.yaml`
6. `apps/n8n/helmfile.yaml`

## Preflight перед релизом

Перед запуском проверьте:

1. `KUBECONFIG` указывает на целевой кластер.
2. Установлены `kubectl`, `helm`, `helmfile`, `sops`, `age`.
3. Установлен плагин `secrets` (`helm-secrets`).
4. Доступен ключ для расшифровки `*.enc.yaml`.

Базовые команды:

```bash
export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config-k3s}"

kubectl get nodes -o wide
kubectl get ns
helm version
helmfile --version
helm plugin list
```

## Операционный цикл применения

Для каждого слоя используйте одинаковый цикл:

1. `helmfile -e prod build` (проверка рендера).
2. `helmfile -e prod sync` (применение).
3. `kubectl rollout status` + health checks.

Полный прогон:

```bash
cd deploy/kubernetes
helmfile -e prod build > /tmp/k8s-stage-b-build.yaml
helmfile -e prod sync
```

Применение только одного слоя (пример `n8n`):

```bash
cd deploy/kubernetes/apps/n8n
helmfile -e prod build > /tmp/k8s-n8n-build.yaml
helmfile -e prod sync
```

## Проверка после релиза

Проверка системного состояния:

```bash
kubectl get ns
kubectl -n cert-manager get pods
kubectl get clusterissuer

kubectl -n db get pods,svc,pvc,job,cronjob
kubectl -n n8n get deploy,pods,svc,ingress,job
kubectl -n wiki get deploy,pods,svc,ingress
kubectl -n ollama get deploy,pods,svc,pvc,job
```

Проверка rollout:

```bash
kubectl -n db rollout status sts/postgres-postgresql
kubectl -n n8n rollout status deploy/n8n-web
kubectl -n n8n rollout status deploy/n8n-worker
kubectl -n wiki rollout status deploy/wikijs
kubectl -n ollama rollout status deploy/ollama
```

Базовые функциональные проверки:

```bash
curl -sk https://n8n.poluyanov.net/healthz
curl -skI https://wiki.poluyanov.net
kubectl -n ollama exec deploy/ollama -- curl -sf http://127.0.0.1:11434/api/version
```

## Release Gate

Релиз этапа B считается успешным только если одновременно выполняется:

1. Bootstrap k3s завершился без ошибок (`failed=0`).
2. `helmfile -e prod sync` завершился без ошибок.
3. `ClusterIssuer` в состоянии `Ready=True`.
4. `postgres`, `wiki`, `ollama`, `n8n-web`, `n8n-worker` в `Ready`.
5. Проверки ingress/health проходят (`n8n`, `wiki`).
6. Для `n8n` отсутствуют ошибки импорта workflows и ошибок доступа к PostgreSQL/Redis/Ollama.

## Инциденты и быстрые фиксы

`Kubernetes cluster unreachable`:

- проверьте `KUBECONFIG`;
- проверьте доступность API `:6443`;
- проверьте, что bootstrap этап завершен.

`failed to decrypt` / `sops metadata not found`:

- проверьте AGE ключ (`~/.config/sops/age/keys.txt`);
- проверьте, что работаете с корректным `*.enc.yaml`;
- проверьте `.sops.yaml` и используемый key-id.

`cert-manager/issuer not ready`:

- проверьте DNS A/AAAA записей на public IP;
- проверьте доступность `80/tcp` и `443/tcp`;
- проверьте `Order/Challenge` и логи `cert-manager`.

`n8n workflows import failed`:

- проверьте job/логи импорта;
- проверьте секреты и postgres credential в n8n;
- проверьте доступ n8n к PostgreSQL/Redis/Ollama по NetworkPolicy.

```bash
kubectl -n n8n get jobs
kubectl -n n8n logs job/n8n-import-workflows --all-containers=true --tail=500
```

`ImagePullBackOff`:

- проверьте egress в интернет (где требуется policy);
- проверьте имя/тег образа;
- проверьте доступность registry.

## Регулярная эксплуатация

- Плановый update релизов: `helmfile -e prod sync` в целевом слое.
- Проверка сертификатов: [certificates-runbook.md](./certificates-runbook.md).
- Backup/restore PostgreSQL: [backup-restore.md](./backup-restore.md).
- Разбор сетевых ограничений: [network.md](./network.md).
