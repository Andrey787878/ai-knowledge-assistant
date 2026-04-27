# deploy/kubernetes/apps/wiki

## Что это
Слой Wiki.js, который использует внешний PostgreSQL (из `apps/postgres`).

## Что ставится

- Wiki.js Deployment/Service/Ingress
- Secret с паролем к внешнему PostgreSQL
- Traefik Middleware для HTTP->HTTPS redirect
- NetworkPolicy

## Какие chart используются

- `../../../vendor_charts/wiki` (upstream `requarks/wiki`) для runtime
- `../../../vendor_charts/raw` (upstream `bedag/raw`) для secret и networkpolicy

## Основные файлы

- `helmfile.yaml` — точка входа
- `releases/wikijs.yaml` — runtime wiki
- `releases/db-secret.yaml` — пароль БД
- `releases/http-redirect-middleware.yaml` — redirect HTTP->HTTPS
- `releases/networkpolicy.yaml` — сетевые правила
- `environments/prod/app.values.yaml` — ingress и externalPostgresql

## Зависимости

- `deploy/kubernetes/platform` уже применен (namespace `wiki`, cert-manager, ClusterIssuer)
- `deploy/kubernetes/apps/postgres` уже применен (БД `wikijs` доступна)
- настроены `sops` и `helm-secrets`

## Как применять

```bash
cd deploy/kubernetes/apps/wiki

# Проверка рендера
helmfile -e prod build > /tmp/wiki-build.yaml

# Применение
helmfile -e prod sync
```

## Проверка

```bash
kubectl -n wiki get deploy,pods,svc,ingress,secret,networkpolicy
kubectl -n wiki rollout status deploy/wikijs
kubectl -n wiki get certificate,secret | grep wiki-tls
curl -I http://wiki.poluyanov.net
curl -I https://wiki.poluyanov.net
```
