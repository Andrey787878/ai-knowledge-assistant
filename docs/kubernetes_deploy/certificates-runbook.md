# Ранбук: сертификаты edge (cert-manager + Let's Encrypt)

## Что описывает документ

Документ описывает выпуск, продление и диагностику TLS-сертификатов в
Kubernetes-контуре этапов B и C. Здесь зафиксированы базовый операционный
цикл, проверки состояния `cert-manager` и типовые сценарии разбора проблем.

## Что отвечает за сертификаты

Компоненты:

- `cert-manager` (`cert-manager`, `webhook`, `cainjector`)
- `ClusterIssuer` (`letsencrypt-prod`)
- ingress в `wiki` и `n8n`

Где хранятся сертификаты:

- в Secret namespace приложения (`Ingress.spec.tls.secretName`)
- ACME account key в `cert-manager` (`acme_account_private_key_secret_name`)

## Базовый операционный цикл

1. Применить platform-слой (`cert-manager` + `ClusterIssuer`).
2. Применить app-слои с ingress (`wiki`, `n8n`).
3. Проверить `Certificate`, `Order`, `Challenge`.

```bash
cd deploy/kubernetes/platform
helmfile -e prod sync
```

```bash
cd deploy/kubernetes/apps/wiki
helmfile -e prod sync

cd ../n8n
helmfile -e prod sync
```

## Проверка состояния

Базовая проверка:

```bash
kubectl -n cert-manager get pods
kubectl get clusterissuer
kubectl describe clusterissuer letsencrypt-prod
```

Проверка по namespace приложения:

```bash
kubectl -n wiki get certificate,order,challenge,secret
kubectl -n n8n get certificate,order,challenge,secret
```

Если сертификат не в `Ready=True`, смотрим события:

```bash
kubectl -n wiki describe certificate
kubectl -n n8n describe certificate
kubectl -n cert-manager logs deploy/cert-manager --tail=200
```

<a id="step-4"></a>

## Production-контракт

Production-контур должен работать на production ACME directory:
`https://acme-v02.api.letsencrypt.org/directory`.

Проверочный цикл:

1. Убедиться, что в
   [cluster-issuer.values.yaml](../../deploy/kubernetes/platform/environments/prod/cluster-issuer.values.yaml)
   задан production URL.
2. Применить platform-слой.
3. Переприменить `wiki` и `n8n`.
4. Убедиться, что новые `Order`/`Challenge` успешны.

<a id="step-5"></a>

## Инциденты и быстрые фиксы

`certificate not ready`:

- проверить DNS A/AAAA на публичный IP кластера
- проверить доступность `80/tcp` и `443/tcp`
- проверить `cluster-issuer` аннотацию и `tls.secretName` в ingress
- посмотреть `Order/Challenge` и логи `cert-manager`

`ACME rate limit`:

- временно переключиться на staging URL только для диагностики
- подтвердить, что challenge проходит
- вернуть production URL и повторить apply

`wrong secret in ingress`:

- исправить `spec.tls.secretName`
- переприменить release приложения

## Источники

- [platform/releases/cert-manager.yaml](../../deploy/kubernetes/platform/releases/cert-manager.yaml)
- [platform/releases/cluster-issuer.yaml](../../deploy/kubernetes/platform/releases/cluster-issuer.yaml)
- [wiki release](../../deploy/kubernetes/apps/wiki/releases/wikijs.yaml)
- [n8n release](../../deploy/kubernetes/apps/n8n/releases/n8n.yaml)
