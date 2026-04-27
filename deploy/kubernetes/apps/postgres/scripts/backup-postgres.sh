#!/usr/bin/env bash
set -Eeuo pipefail

KUBECTL_BIN="${KUBECTL_BIN:-kubectl}"
PG_NAMESPACE="${PG_NAMESPACE:-db}"
PG_RELEASE_NAME="${PG_RELEASE_NAME:-postgres}"
PG_SECRET_NAME="${PG_SECRET_NAME:-${PG_RELEASE_NAME}-postgresql}"
PG_SECRET_KEY="${PG_SECRET_KEY:-postgres-password}"
PG_USER="${PG_USER:-postgres}"
PG_BACKUP_DATABASES="${PG_BACKUP_DATABASES:-n8n wikijs}"

BACKUP_ROOT_DIR="${BACKUP_ROOT_DIR:-/var/backups/ai-agent/postgres}"
BACKUP_CURRENT_DIR="${BACKUP_CURRENT_DIR:-${BACKUP_ROOT_DIR}/current}"
BACKUP_LOCK_FILE="${BACKUP_LOCK_FILE:-${BACKUP_ROOT_DIR}/.backup.lock}"
BACKUP_INCLUDE_GLOBALS="${BACKUP_INCLUDE_GLOBALS:-true}"
BACKUP_PRUNE_ENABLED="${BACKUP_PRUNE_ENABLED:-false}"
BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-7}"

BACKUP_TS="$(date +'%Y%m%d-%H%M%S')"
TARGET_DIR="${BACKUP_ROOT_DIR}/${BACKUP_TS}"
LOCK_ACQUIRED="false"
PG_POD=""

read -r -a BACKUP_DATABASES <<< "${PG_BACKUP_DATABASES}"

k() {
  "${KUBECTL_BIN}" -n "${PG_NAMESPACE}" "$@"
}

find_postgres_pod() {
  k get pods \
    -l "app.kubernetes.io/instance=${PG_RELEASE_NAME},app.kubernetes.io/name=postgresql" \
    -o jsonpath='{range .items[?(@.status.phase=="Running")]}{.metadata.name}{"\n"}{end}' \
    | head -n1
}

cleanup() {
  local rc=$?

  if [[ -n "${PG_POD}" ]]; then
    for db_name in "${BACKUP_DATABASES[@]}"; do
      k exec "${PG_POD}" -- rm -f "/tmp/${db_name}.dump" >/dev/null 2>&1 || true
    done
  fi

  if [[ "${LOCK_ACQUIRED}" == "true" ]]; then
    rm -f "${BACKUP_LOCK_FILE}" >/dev/null 2>&1 || true
  fi

  exit "${rc}"
}

trap cleanup EXIT INT TERM

if [[ "${#BACKUP_DATABASES[@]}" -eq 0 ]]; then
  echo "PG_BACKUP_DATABASES must contain at least one database name." >&2
  exit 1
fi

mkdir -p "${BACKUP_ROOT_DIR}"
mkdir -p "${TARGET_DIR}"

if [[ -f "${BACKUP_LOCK_FILE}" ]]; then
  LOCK_PID="$(cat "${BACKUP_LOCK_FILE}" 2>/dev/null || true)"
  if [[ -n "${LOCK_PID}" && "${LOCK_PID}" =~ ^[0-9]+$ ]] && kill -0 "${LOCK_PID}" 2>/dev/null; then
    echo "another postgres backup process is running (pid: ${LOCK_PID})" >&2
    exit 1
  fi
  rm -f "${BACKUP_LOCK_FILE}" >/dev/null 2>&1 || true
fi

if ! (set -o noclobber; echo "$$" > "${BACKUP_LOCK_FILE}") 2>/dev/null; then
  echo "backup lock file exists: ${BACKUP_LOCK_FILE}" >&2
  exit 1
fi

LOCK_ACQUIRED="true"

PG_POD="$(find_postgres_pod)"
if [[ -z "${PG_POD}" ]]; then
  echo "postgres running pod not found in namespace '${PG_NAMESPACE}' for release '${PG_RELEASE_NAME}'." >&2
  exit 1
fi

PG_PASSWORD="$({ k get secret "${PG_SECRET_NAME}" -o "jsonpath={.data.${PG_SECRET_KEY}}" | base64 --decode; } 2>/dev/null)"
if [[ -z "${PG_PASSWORD}" ]]; then
  echo "cannot read postgres password from secret '${PG_SECRET_NAME}' key '${PG_SECRET_KEY}'." >&2
  exit 1
fi

if [[ "${BACKUP_INCLUDE_GLOBALS}" == "true" ]]; then
  k exec "${PG_POD}" -- sh -eu -c 'PGPASSWORD="$1" pg_dumpall --globals-only -U "$2"' sh "${PG_PASSWORD}" "${PG_USER}" > "${TARGET_DIR}/globals.sql"
fi

for db_name in "${BACKUP_DATABASES[@]}"; do
  tmp_dump="/tmp/${db_name}.dump"

  k exec "${PG_POD}" -- sh -eu -c 'PGPASSWORD="$1" pg_dump -Fc -U "$2" -d "$3" -f "$4"' sh "${PG_PASSWORD}" "${PG_USER}" "${db_name}" "${tmp_dump}"
  k cp "${PG_NAMESPACE}/${PG_POD}:${tmp_dump}" "${TARGET_DIR}/${db_name}.dump"
  k exec "${PG_POD}" -- rm -f "${tmp_dump}"
done

(
  cd "${TARGET_DIR}"
  sha256sum ./* > SHA256SUMS
)

ln -sfn "${TARGET_DIR}" "${BACKUP_CURRENT_DIR}"

if [[ "${BACKUP_PRUNE_ENABLED}" == "true" ]]; then
  find "${BACKUP_ROOT_DIR}" -mindepth 1 -maxdepth 1 -type d -name '20*' -mtime +"${BACKUP_RETENTION_DAYS}" -exec rm -rf {} +
fi

echo "postgres backup completed: ${TARGET_DIR}"
