#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: verify-ci-success.sh --workflow <workflow-file> --ref <ref> --sha <sha>

Verify that the selected ref already has a successful CI workflow run.

Required environment:
  GITHUB_REPOSITORY
  GITHUB_TOKEN
USAGE
}

workflow_file=""
target_ref=""
target_sha=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --workflow)
      [[ $# -ge 2 ]] || {
        echo "error: --workflow requires a value" >&2
        exit 1
      }
      workflow_file="$2"
      shift 2
      ;;
    --ref)
      [[ $# -ge 2 ]] || {
        echo "error: --ref requires a value" >&2
        exit 1
      }
      target_ref="$2"
      shift 2
      ;;
    --sha)
      [[ $# -ge 2 ]] || {
        echo "error: --sha requires a value" >&2
        exit 1
      }
      target_sha="$2"
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

[[ -n "${workflow_file}" ]] || {
  echo "error: --workflow is required" >&2
  usage >&2
  exit 1
}

[[ -n "${target_ref}" ]] || {
  echo "error: --ref is required" >&2
  usage >&2
  exit 1
}

[[ -n "${target_sha}" ]] || {
  echo "error: --sha is required" >&2
  usage >&2
  exit 1
}

[[ -n "${GITHUB_REPOSITORY:-}" ]] || {
  echo "error: GITHUB_REPOSITORY is not set" >&2
  exit 1
}

[[ -n "${GITHUB_TOKEN:-}" ]] || {
  echo "error: GITHUB_TOKEN is not set" >&2
  exit 1
}

api_url="https://api.github.com/repos/${GITHUB_REPOSITORY}/actions/workflows/${workflow_file}/runs?event=push&head_sha=${target_sha}&per_page=20"

response="$(curl -fsSL \
  -H "Authorization: Bearer ${GITHUB_TOKEN}" \
  -H "Accept: application/vnd.github+json" \
  "${api_url}")"

run_count="$(
  jq -r '
    [
      .workflow_runs[]
      | select(.head_sha == $sha and .conclusion == "success")
    ] | length
  ' --arg sha "${target_sha}" <<<"${response}"
)"

if [[ "${run_count}" -eq 0 ]]; then
  echo "error: ref ${target_ref} (${target_sha}) has no successful CI push run" >&2
  exit 1
fi

echo "Verified successful CI for ${target_ref} (${target_sha})"
