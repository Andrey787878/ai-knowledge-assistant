#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: smoke-k3s-scope.sh <scope>

Scopes:
  all
  platform
  observability
  postgres
  redis
  wiki
  ollama
  n8n
USAGE
}

if [[ $# -ne 1 ]]; then
  usage >&2
  exit 1
fi

scope="$1"
repo_root="$(git rev-parse --show-toplevel)"
port_forward_pids=()

cleanup() {
  local pid
  for pid in "${port_forward_pids[@]:-}"; do
    kill "${pid}" >/dev/null 2>&1 || true
  done
}
trap cleanup EXIT

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "error: required command not found: $1" >&2
    exit 1
  }
}

wait_http_ok() {
  local url="$1"
  local attempts="${2:-30}"
  local delay="${3:-2}"
  local i

  for ((i = 1; i <= attempts; i += 1)); do
    if curl -fsS "${url}" >/dev/null; then
      return 0
    fi
    sleep "${delay}"
  done

  echo "error: HTTP check failed: ${url}" >&2
  return 1
}

start_port_forward() {
  local namespace="$1"
  local resource="$2"
  local local_port="$3"
  local remote_port="$4"
  local logfile

  logfile="$(mktemp)"
  kubectl -n "${namespace}" port-forward "${resource}" \
    "${local_port}:${remote_port}" >"${logfile}" 2>&1 &
  port_forward_pids+=("$!")
  sleep 2
}

rollout_deployment() {
  local namespace="$1"
  local name="$2"
  kubectl -n "${namespace}" rollout status "deployment/${name}" --timeout=10m
}

rollout_statefulset() {
  local namespace="$1"
  local name="$2"
  kubectl -n "${namespace}" rollout status "statefulset/${name}" --timeout=10m
}

rollout_daemonset() {
  local namespace="$1"
  local name="$2"
  kubectl -n "${namespace}" rollout status "daemonset/${name}" --timeout=10m
}

wait_pods_ready() {
  local namespace="$1"
  local selector="$2"
  kubectl -n "${namespace}" wait \
    --for=condition=Ready pod \
    -l "${selector}" \
    --timeout=10m
}

smoke_platform() {
  kubectl get namespace db observability n8n wiki ollama >/dev/null
  rollout_deployment cert-manager cert-manager
  rollout_deployment cert-manager cert-manager-cainjector
  rollout_deployment cert-manager cert-manager-webhook
  kubectl get clusterissuer letsencrypt-staging >/dev/null
}

smoke_observability() {
  wait_pods_ready observability "operator.prometheus.io/name=observability-prometheus"
  wait_pods_ready observability "alertmanager=observability-alertmanager"
  rollout_deployment observability observability-grafana
  rollout_statefulset observability loki
  rollout_daemonset observability alloy
  kubectl -n observability get servicemonitor,prometheusrule,probe >/dev/null
}

smoke_postgres() {
  rollout_statefulset db postgres-postgresql
  kubectl -n db get svc postgres-postgresql >/dev/null
  kubectl -n db get cronjob postgres-backup >/dev/null
}

smoke_redis() {
  rollout_statefulset n8n redis-master
  kubectl -n n8n get svc redis-master redis-metrics >/dev/null
}

smoke_wiki() {
  rollout_deployment wiki wikijs
  kubectl -n wiki get ingress >/dev/null
  start_port_forward wiki svc/wikijs 18082 3000
  wait_http_ok "http://127.0.0.1:18082/healthz"
}

smoke_ollama() {
  rollout_deployment ollama ollama
  kubectl -n ollama get svc ollama-svc >/dev/null
  start_port_forward ollama svc/ollama-svc 18114 11434
  wait_http_ok "http://127.0.0.1:18114/api/version"
}

smoke_n8n() {
  rollout_deployment n8n n8n-web
  rollout_deployment n8n n8n-worker
  kubectl -n n8n get ingress n8n-web-ingress >/dev/null
  kubectl -n n8n get job n8n-import-workflows >/dev/null
  start_port_forward n8n svc/n8n-web-svc 18081 80
  wait_http_ok "http://127.0.0.1:18081/rest/settings"
}

require_cmd kubectl
require_cmd curl

cd "${repo_root}"

echo "==> Smoke scope: ${scope}"

case "${scope}" in
  all)
    smoke_platform
    smoke_observability
    smoke_postgres
    smoke_redis
    smoke_wiki
    smoke_ollama
    smoke_n8n
    ;;
  platform)
    smoke_platform
    ;;
  observability)
    smoke_observability
    ;;
  postgres)
    smoke_postgres
    ;;
  redis)
    smoke_redis
    ;;
  wiki)
    smoke_wiki
    ;;
  ollama)
    smoke_ollama
    ;;
  n8n)
    smoke_n8n
    ;;
  *)
    echo "error: unsupported scope: ${scope}" >&2
    usage >&2
    exit 1
    ;;
esac
