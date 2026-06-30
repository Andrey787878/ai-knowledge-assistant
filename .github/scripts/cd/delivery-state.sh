#!/usr/bin/env bash
set -euo pipefail

state_namespace="${DELIVERY_STATE_NAMESPACE:-kube-system}"
state_configmap="${DELIVERY_STATE_CONFIGMAP:-k3s-delivery-state}"

usage() {
  cat <<'USAGE'
Usage:
  delivery-state.sh get-last-full-sha
  delivery-state.sh mark-success --sha <sha> --mode <mode> --scopes <scopes>

Commands:
  get-last-full-sha
      Print the SHA of the last successful full-stack deploy, if known.

  mark-success
      Persist successful deploy metadata into the cluster delivery-state ConfigMap.
USAGE
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "error: required command not found: $1" >&2
    exit 1
  }
}

configmap_value() {
  local key="$1"

  kubectl -n "${state_namespace}" get configmap "${state_configmap}" \
    -o "go-template={{ index .data \"${key}\" }}" 2>/dev/null || true
}

mark_success() {
  local deploy_sha=""
  local deploy_mode=""
  local deploy_scopes=""
  local last_full_sha=""
  local timestamp=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --sha)
        deploy_sha="${2:-}"
        shift 2
        ;;
      --mode)
        deploy_mode="${2:-}"
        shift 2
        ;;
      --scopes)
        deploy_scopes="${2:-}"
        shift 2
        ;;
      *)
        echo "error: unknown argument: $1" >&2
        usage >&2
        exit 1
        ;;
    esac
  done

  [[ -n "${deploy_sha}" ]] || {
    echo "error: --sha is required" >&2
    exit 1
  }

  [[ -n "${deploy_mode}" ]] || {
    echo "error: --mode is required" >&2
    exit 1
  }

  [[ -n "${deploy_scopes}" ]] || {
    echo "error: --scopes is required" >&2
    exit 1
  }

  last_full_sha="$(configmap_value last_full_deploy_sha)"
  if [[ "${deploy_mode}" == "full" || "${deploy_scopes}" == "all" ]]; then
    last_full_sha="${deploy_sha}"
  fi

  timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

  kubectl -n "${state_namespace}" create configmap "${state_configmap}" \
    --from-literal=last_full_deploy_sha="${last_full_sha}" \
    --from-literal=last_successful_deploy_sha="${deploy_sha}" \
    --from-literal=last_successful_deploy_mode="${deploy_mode}" \
    --from-literal=last_successful_deploy_scopes="${deploy_scopes}" \
    --from-literal=last_successful_deploy_at="${timestamp}" \
    --dry-run=client \
    -o yaml | kubectl apply -f -
}

main() {
  require_cmd kubectl

  [[ $# -ge 1 ]] || {
    usage >&2
    exit 1
  }

  case "$1" in
    get-last-full-sha)
      configmap_value last_full_deploy_sha
      ;;
    mark-success)
      shift
      mark_success "$@"
      ;;
    -h|--help)
      usage
      ;;
    *)
      echo "error: unknown command: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
}

main "$@"
