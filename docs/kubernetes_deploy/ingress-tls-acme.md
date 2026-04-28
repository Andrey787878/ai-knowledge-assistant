# Edge TLS через cert-manager + Let's Encrypt (HTTP-01)

## Область

Документ описывает выпуск и продление публичных TLS-сертификатов на этапе B.

Компоненты:

- `cert-manager`
- `ClusterIssuer`
- Traefik ingress controller

## Как устроено

1. В `platform` устанавливается `cert-manager`.
2. В `platform` создается `ClusterIssuer`.
3. В ingress приложений задаются:
   - `cert-manager.io/cluster-issuer`
   - `tls.secretName`
4. В `wiki` и `n8n` используется Traefik Middleware `redirectScheme` для HTTP->HTTPS redirect.
5. cert-manager выпускает сертификат и сохраняет его в Secret namespace приложения.

## Предусловия

- DNS A/AAAA записи доменов указывают на публичный IP кластера.
- `80/tcp` открыт для HTTP-01 challenge и HTTP->HTTPS redirect.
- `443/tcp` открыт для пользовательского HTTPS.
- `ClusterIssuer` в `Ready=True`.

## Применение

```bash
# platform
cd deploy/kubernetes/platform
helmfile -e prod sync

# apps с публичным ingress
cd ../apps/wiki
helmfile -e prod sync

cd ../n8n
helmfile -e prod sync
```

## Проверка

```bash
kubectl get clusterissuer
kubectl describe clusterissuer letsencrypt-prod
```

```bash
kubectl -n wiki get certificate,secret
kubectl -n n8n get certificate,secret
kubectl -n wiki describe certificate
kubectl -n n8n describe certificate
```

## Переход staging -> production ACME

1. В [cluster-issuer.values.yaml](../../deploy/kubernetes/platform/environments/prod/cluster-issuer.values.yaml) установить production URL:
   `https://acme-v02.api.letsencrypt.org/directory`
2. Применить `platform`:
   `helmfile -e prod sync`
3. Переприменить `wiki` и `n8n` releases.
4. Проверить `Certificate`, `Order`, `Challenge`.

## Если сертификат не выпускается

1. Проверить DNS.
2. Проверить доступность `80/tcp` и `443/tcp`.
3. Проверить `ClusterIssuer` и события `Order/Challenge`.
4. Проверить ingress host/annotation/secretName.
