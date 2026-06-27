#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: detect-k3s-scopes.sh [--base-sha <sha>] [--head-sha <sha>]

Detect Kubernetes deploy scopes from changed files.

Outputs:
  scopes=<space-separated scopes>
  no_deploy=<true|false>
USAGE
}

base_sha=""
head_sha=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --base-sha)
      [[ $# -ge 2 ]] || {
        echo "error: --base-sha requires a value" >&2
        exit 1
      }
      base_sha="$2"
      shift 2
      ;;
    --head-sha)
      [[ $# -ge 2 ]] || {
        echo "error: --head-sha requires a value" >&2
        exit 1
      }
      head_sha="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -z "${head_sha}" ]]; then
  head_sha="$(git rev-parse HEAD)"
fi

if [[ -z "${base_sha}" || "${base_sha}" =~ ^0+$ ]]; then
  if git rev-parse "${head_sha}^" >/dev/null 2>&1; then
    base_sha="$(git rev-parse "${head_sha}^")"
  else
    base_sha="${head_sha}"
  fi
fi

declare -A scope_flags=(
  [platform]=0
  [observability]=0
  [postgres]=0
  [redis]=0
  [wiki]=0
  [ollama]=0
  [n8n]=0
)

deploy_all=0

while IFS= read -r file; do
  [[ -n "${file}" ]] || continue

  case "${file}" in
    deploy/kubernetes/helmfile.yaml)
      deploy_all=1
      ;;
    deploy/kubernetes/platform/*)
      scope_flags[platform]=1
      ;;
    deploy/kubernetes/observability/*)
      scope_flags[observability]=1
      ;;
    deploy/kubernetes/apps/postgres/*)
      scope_flags[postgres]=1
      ;;
    deploy/kubernetes/apps/redis/*)
      scope_flags[redis]=1
      ;;
    deploy/kubernetes/apps/wiki/*)
      scope_flags[wiki]=1
      ;;
    deploy/kubernetes/apps/ollama/*)
      scope_flags[ollama]=1
      ;;
    deploy/kubernetes/apps/n8n/*)
      scope_flags[n8n]=1
      ;;
  esac
done < <(git diff --name-only "${base_sha}" "${head_sha}")

if [[ "${deploy_all}" -eq 1 ]]; then
  echo "scopes=all"
  echo "no_deploy=false"
  exit 0
fi

ordered_scopes=(
  platform
  observability
  postgres
  redis
  wiki
  ollama
  n8n
)

scopes=()
for scope in "${ordered_scopes[@]}"; do
  if [[ "${scope_flags[${scope}]}" -eq 1 ]]; then
    scopes+=("${scope}")
  fi
done

if [[ "${#scopes[@]}" -eq 0 ]]; then
  echo "scopes="
  echo "no_deploy=true"
  exit 0
fi

printf 'scopes=%s\n' "${scopes[*]}"
echo "no_deploy=false"
