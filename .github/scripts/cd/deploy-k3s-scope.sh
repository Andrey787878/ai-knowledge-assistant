#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: deploy-k3s-scope.sh <scope>

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
helmfile_bin="${HELMFILE_BIN:-helmfile}"
repo_root="$(git rev-parse --show-toplevel)"

case "${scope}" in
  all)
    helmfile_path="deploy/kubernetes/helmfile.yaml"
    ;;
  platform)
    helmfile_path="deploy/kubernetes/platform/helmfile.yaml"
    ;;
  observability)
    helmfile_path="deploy/kubernetes/observability/helmfile.yaml"
    ;;
  postgres)
    helmfile_path="deploy/kubernetes/apps/postgres/helmfile.yaml"
    ;;
  redis)
    helmfile_path="deploy/kubernetes/apps/redis/helmfile.yaml"
    ;;
  wiki)
    helmfile_path="deploy/kubernetes/apps/wiki/helmfile.yaml"
    ;;
  ollama)
    helmfile_path="deploy/kubernetes/apps/ollama/helmfile.yaml"
    ;;
  n8n)
    helmfile_path="deploy/kubernetes/apps/n8n/helmfile.yaml"
    ;;
  *)
    echo "error: unsupported scope: ${scope}" >&2
    usage >&2
    exit 1
    ;;
esac

cd "${repo_root}"

echo "==> Deploy scope: ${scope}"
"${helmfile_bin}" -f "${helmfile_path}" -e prod sync
