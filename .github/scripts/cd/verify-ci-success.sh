#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: verify-ci-success.sh --workflow <workflow-file> --ref <ref> --sha <sha> [--wait] [--timeout-seconds <seconds>] [--poll-interval-seconds <seconds>]

Verify that the selected ref already has a successful CI workflow run.

Required environment:
  GITHUB_REPOSITORY
  GITHUB_TOKEN
USAGE
}

workflow_file=""
target_ref=""
target_sha=""
wait_for_success="false"
timeout_seconds=0
poll_interval_seconds=15

fetch_runs() {
  local api_url

  api_url="https://api.github.com/repos/${GITHUB_REPOSITORY}/actions/workflows/${workflow_file}/runs?event=push&head_sha=${target_sha}&per_page=20"

  curl -fsSL \
    -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    "${api_url}"
}

successful_run_count() {
  jq -r '
    [
      .workflow_runs[]
      | select(.head_sha == $sha and .conclusion == "success")
    ] | length
  ' --arg sha "${target_sha}"
}

completed_failed_run_count() {
  jq -r '
    [
      .workflow_runs[]
      | select(
          .head_sha == $sha and
          .status == "completed" and
          .conclusion != null and
          .conclusion != "success"
        )
    ] | length
  ' --arg sha "${target_sha}"
}

active_run_count() {
  jq -r '
    [
      .workflow_runs[]
      | select(.head_sha == $sha and .status != "completed")
    ] | length
  ' --arg sha "${target_sha}"
}

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
    --wait)
      wait_for_success="true"
      shift
      ;;
    --timeout-seconds)
      [[ $# -ge 2 ]] || {
        echo "error: --timeout-seconds requires a value" >&2
        exit 1
      }
      timeout_seconds="$2"
      shift 2
      ;;
    --poll-interval-seconds)
      [[ $# -ge 2 ]] || {
        echo "error: --poll-interval-seconds requires a value" >&2
        exit 1
      }
      poll_interval_seconds="$2"
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

deadline_epoch=0
if [[ "${wait_for_success}" == "true" ]]; then
  if [[ "${timeout_seconds}" -le 0 ]]; then
    echo "error: --wait requires a positive --timeout-seconds value" >&2
    exit 1
  fi
  deadline_epoch="$(( $(date +%s) + timeout_seconds ))"
fi

while true; do
  response="$(fetch_runs)"

  run_count="$(successful_run_count <<<"${response}")"
  if [[ "${run_count}" -gt 0 ]]; then
    echo "Verified successful CI for ${target_ref} (${target_sha})"
    exit 0
  fi

  failed_run_count="$(completed_failed_run_count <<<"${response}")"
  if [[ "${failed_run_count}" -gt 0 ]]; then
    echo "error: ref ${target_ref} (${target_sha}) has a completed CI push run without success" >&2
    exit 1
  fi

  if [[ "${wait_for_success}" != "true" ]]; then
    echo "error: ref ${target_ref} (${target_sha}) has no successful CI push run" >&2
    exit 1
  fi

  now_epoch="$(date +%s)"
  if [[ "${now_epoch}" -ge "${deadline_epoch}" ]]; then
    echo "error: timed out waiting for successful CI for ${target_ref} (${target_sha})" >&2
    exit 1
  fi

  active_count="$(active_run_count <<<"${response}")"
  if [[ "${active_count}" -gt 0 ]]; then
    echo "Waiting for CI to finish for ${target_ref} (${target_sha}); active runs: ${active_count}" >&2
  else
    echo "Waiting for CI run to appear for ${target_ref} (${target_sha})" >&2
  fi

  sleep "${poll_interval_seconds}"
done
