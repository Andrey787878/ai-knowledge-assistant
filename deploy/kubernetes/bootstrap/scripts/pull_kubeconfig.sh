#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

INVENTORY_FILE="${PROJECT_DIR}/inventories/cloud/hosts.yml"
HOST_ALIAS="k3s"
SSH_USER="${ANSIBLE_REMOTE_USER:-ubuntu}"
SSH_KEY="${ANSIBLE_SSH_PRIVATE_KEY_FILE:-$HOME/.ssh/k3s_deploy}"
REMOTE_KUBECONFIG_PATH="/etc/rancher/k3s/k3s.yaml"
OUTPUT_FILE="${HOME}/.kube/config-k3s"
SERVER_ENDPOINT=""

usage() {
  cat <<'USAGE'
Usage: pull_kubeconfig.sh [options]

Options:
  --inventory <path>   Path to Ansible inventory hosts.yml
  --host <alias>       Host alias in inventory (default: k3s)
  --user <name>        SSH user (default: ubuntu or $ANSIBLE_REMOTE_USER)
  --identity <path>    SSH private key path (default: ~/.ssh/k3s_deploy or $ANSIBLE_SSH_PRIVATE_KEY_FILE)
  --remote-path <path> Remote kubeconfig path (default: /etc/rancher/k3s/k3s.yaml)
  --output <path>      Local output kubeconfig path (default: ~/.kube/config-k3s)
  --server <host/ip>   Kubernetes API host/IP for kubeconfig server field
  -h, --help           Show this help
USAGE
}

expand_tilde_path() {
  local path="$1"
  # Handle accidentally malformed value like "/home/user/~/.ssh/key".
  if [[ "${path}" == "${HOME}/~/"* ]]; then
    printf '%s\n' "${HOME}/${path#"${HOME}/~/"}"
    return
  fi
  if [[ "${path}" == "~" ]]; then
    printf '%s\n' "${HOME}"
    return
  fi
  if [[ "${path}" == "~/"* ]]; then
    printf '%s\n' "${HOME}/${path#~/}"
    return
  fi
  printf '%s\n' "${path}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --inventory)
      INVENTORY_FILE="$2"
      shift 2
      ;;
    --host)
      HOST_ALIAS="$2"
      shift 2
      ;;
    --user)
      SSH_USER="$2"
      shift 2
      ;;
    --identity)
      SSH_KEY="$2"
      shift 2
      ;;
    --remote-path)
      REMOTE_KUBECONFIG_PATH="$2"
      shift 2
      ;;
    --output)
      OUTPUT_FILE="$2"
      shift 2
      ;;
    --server)
      SERVER_ENDPOINT="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ ! -f "${INVENTORY_FILE}" ]]; then
  echo "Inventory file not found: ${INVENTORY_FILE}" >&2
  exit 1
fi

SSH_KEY="$(expand_tilde_path "${SSH_KEY}")"

# Ensure ansible-inventory can create local temp files even when
# the default ~/.ansible/tmp path is unavailable in the current environment.
if [[ -z "${ANSIBLE_LOCAL_TEMP:-}" ]]; then
  export ANSIBLE_LOCAL_TEMP="${PROJECT_DIR}/.ansible/tmp"
fi
mkdir -p "${ANSIBLE_LOCAL_TEMP}"

if ! command -v ansible-inventory >/dev/null 2>&1; then
  echo "ansible-inventory command not found in PATH" >&2
  exit 1
fi

SSH_TARGET="$(
  ansible-inventory -i "${INVENTORY_FILE}" --host "${HOST_ALIAS}" 2>/dev/null \
    | awk -F'"' '/"ansible_host"[[:space:]]*:/ { print $4; exit }'
)"

if [[ -z "${SSH_TARGET}" ]]; then
  echo "Could not resolve ansible_host for '${HOST_ALIAS}' in ${INVENTORY_FILE}" >&2
  exit 1
fi

if [[ -z "${SERVER_ENDPOINT}" ]]; then
  SERVER_ENDPOINT="${SSH_TARGET}"
fi

SSH_OPTS=(
  -o StrictHostKeyChecking=accept-new
  -o UserKnownHostsFile="${HOME}/.ssh/known_hosts"
  -o IdentitiesOnly=yes
)

KEY_CANDIDATES=()
if [[ -n "${SSH_KEY}" ]]; then
  KEY_CANDIDATES+=("$(expand_tilde_path "${SSH_KEY}")")
fi

# Fallback candidates for local environments where Stage A/B keys differ.
if [[ -z "${ANSIBLE_SSH_PRIVATE_KEY_FILE:-}" ]]; then
  KEY_CANDIDATES+=("$(expand_tilde_path "${HOME}/.ssh/ansible_deploy")")
fi

SSH_SELECTED_KEY=""
for key in "${KEY_CANDIDATES[@]}"; do
  [[ -f "${key}" ]] || continue
  if ssh "${SSH_OPTS[@]}" -i "${key}" -o BatchMode=yes -o ConnectTimeout=8 \
    "${SSH_USER}@${SSH_TARGET}" true >/dev/null 2>&1; then
    SSH_SELECTED_KEY="${key}"
    break
  fi
done

if [[ -z "${SSH_SELECTED_KEY}" ]]; then
  echo "SSH auth failed for ${SSH_USER}@${SSH_TARGET}." >&2
  if [[ ${#KEY_CANDIDATES[@]} -gt 0 ]]; then
    echo "Tried keys: ${KEY_CANDIDATES[*]}" >&2
  fi
  echo "Pass explicit key with --identity <path> or export ANSIBLE_SSH_PRIVATE_KEY_FILE." >&2
  exit 1
fi

SSH_OPTS+=(-i "${SSH_SELECTED_KEY}")
echo "Using SSH key: ${SSH_SELECTED_KEY}"

TMP_FILE="$(mktemp)"
trap 'rm -f "${TMP_FILE}"' EXIT

scp "${SSH_OPTS[@]}" \
  "${SSH_USER}@${SSH_TARGET}:${REMOTE_KUBECONFIG_PATH}" \
  "${TMP_FILE}"

sed -E \
  -e "s#(server:[[:space:]]*https://)(127\\.0\\.0\\.1|localhost|0\\.0\\.0\\.0)(:6443)#\\1${SERVER_ENDPOINT}\\3#g" \
  "${TMP_FILE}" > "${TMP_FILE}.patched"

mkdir -p "$(dirname -- "${OUTPUT_FILE}")"
install -m 600 "${TMP_FILE}.patched" "${OUTPUT_FILE}"

echo "Saved kubeconfig: ${OUTPUT_FILE}"
echo "API server endpoint: https://${SERVER_ENDPOINT}:6443"
echo "Use it with:"
echo "  export KUBECONFIG=\"${OUTPUT_FILE}\""
