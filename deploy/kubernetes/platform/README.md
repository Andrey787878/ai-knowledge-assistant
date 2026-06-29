# deploy/kubernetes/platform

## Назначение слоя

Этот слой поднимает базовую платформенную часть Kubernetes-контура. Здесь
создаются рабочие namespace проекта и разворачивается TLS-инфраструктура для
ingress через `cert-manager` и `ClusterIssuer`.

Этот Helmfile идет раньше прикладных слоев. Без него остальные части
Kubernetes-контура не смогут штатно создать ingress-ресурсы, выпустить
сертификаты и разложить приложения по своим namespace.

## Что применяет Helmfile

Точкой входа служит `helmfile.yaml`. Namespace-ресурсы собираются через
`../../vendor_charts/raw`. `cert-manager` ставится из
`../../vendor_charts/cert-manager`. `ClusterIssuer` для `Let's Encrypt`
собирается отдельным release через тот же `raw` chart.

Структура слоя разделена на три части. `releases/namespaces.yaml` создает
namespace `db`, `observability`, `n8n`, `wiki` и `ollama`.
`releases/cert-manager.yaml` ставит сам `cert-manager`.
`releases/cluster-issuer.yaml` описывает `ClusterIssuer`, который затем
используют ingress-ресурсы прикладных слоев.

Рабочие параметры лежат в `environments/prod/*.values.yaml`.

## Что должно быть готово до применения

До этого слоя должен существовать уже поднятый `k3s`-кластер с рабочим
доступом через `kubectl`. На машине, с которой выполняется деплой, должен быть
настроен `helmfile`.

Отдельно стоит заранее определить, какой ACME endpoint будет использоваться на
текущем прогоне. Для тестовых прогонов имеет смысл использовать staging URL, а
production endpoint включать только после успешной проверки маршрута HTTP-01.

## Как применять

```bash
cd deploy/kubernetes/platform

helmfile -e prod build > /tmp/platform-build.yaml
helmfile -e prod sync
```

Основная предварительная проверка здесь — посмотреть итоговый рендер
namespace-ресурсов, `cert-manager` и `ClusterIssuer` в одном state, до
фактического применения в кластер.

## Как проверять после выкладки

Сначала нужно убедиться, что namespace созданы, а `cert-manager` поднялся:

```bash
kubectl get ns db observability n8n wiki ollama
kubectl -n cert-manager get pods
```

После этого стоит проверить сам `ClusterIssuer`:

```bash
kubectl get clusterissuer
kubectl describe clusterissuer letsencrypt-prod
```

Если namespace уже существуют, а выпуск сертификатов в прикладных слоях не
работает, следующий шаг — смотреть не в приложения, а в состояние
`cert-manager`, `ClusterIssuer` и прохождение HTTP-01 challenge.

## Что важно помнить

Для тестовых прогонов лучше использовать staging ACME URL в
`environments/prod/cluster-issuer.values.yaml`. На production endpoint стоит
переключаться только после того, как staging-прогон подтвердил корректный
маршрут challenge через ingress.
