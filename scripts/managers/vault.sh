#!/bin/bash

# Doppler Manager - HashiCorp Vault Implementation
# Implements the secret manager interface for HashiCorp Vault

set -euo pipefail

MANAGER_NAME="vault"
MANAGER_VERSION="1.0.0"

if [[ -z "${MANAGER_REGISTRY:-}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    source "${SCRIPT_DIR}/secret_manager_interface.sh" 2>/dev/null || true
fi

# sm_init() - Initialize Vault CLI
sm_init() {
    sm_status
}

# sm_status() - Get Vault status in JSON format
sm_status() {
    if ! command -v vault &> /dev/null; then
        cat <<EOF
{
  "status": "ERROR",
  "code": "E001",
  "message": "Vault CLI is not installed",
  "hint": "Install Vault CLI: https://developer.hashicorp.com/vault/install",
  "documentation": "references/SOP.md#vault-setup",
  "project": null,
  "config": null,
  "manager": "${MANAGER_NAME}"
}
EOF
        return 1
    fi

    if [[ -z "${VAULT_ADDR:-}" ]]; then
        cat <<EOF
{
  "status": "ERROR",
  "code": "E006",
  "message": "VAULT_ADDR environment variable is not set",
  "hint": "Set VAULT_ADDR to your Vault server address",
  "documentation": "references/SOP.md#vault-setup",
  "project": null,
  "config": null,
  "manager": "${MANAGER_NAME}"
}
EOF
        return 1
    fi

    local vault_status
    vault_status=$(vault status -format=json 2>&1) || {
        local error_msg=$(echo "$vault_status" | head -1)
        cat <<EOF
{
  "status": "ERROR",
  "code": "E002",
  "message": "Vault is not authenticated or unreachable: $error_msg",
  "hint": "Run 'vault login' to authenticate",
  "documentation": "references/SOP.md#vault-setup",
  "project": null,
  "config": null,
  "manager": "${MANAGER_NAME}"
}
EOF
        return 1
    }

    local sealed=$(echo "$vault_status" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("sealed","unknown"))' 2>/dev/null || echo "unknown")
    if [[ "$sealed" == "true" ]]; then
        cat <<EOF
{
  "status": "ERROR",
  "code": "E102",
  "message": "Vault is sealed",
  "hint": "Unseal Vault with 'vault unseal'",
  "documentation": "references/SOP.md#vault-setup",
  "project": null,
  "config": null,
  "manager": "${MANAGER_NAME}"
}
EOF
        return 1
    fi

    cat <<EOF
{
  "status": "OK",
  "code": "E000",
  "message": "Vault is authenticated and reachable",
  "hint": "Ready to use 'vault kv get' for secret retrieval",
  "documentation": "references/SOP.md#vault-setup",
  "project": "${VAULT_ADDR:-unknown}",
  "config": null,
  "manager": "${MANAGER_NAME}"
}
EOF
    return 0
}

# sm_run() - Run command with Vault secrets injected
sm_run() {
    if [[ $# -eq 0 ]]; then
        echo "ERROR: sm_run requires a command to execute" >&2
        return 1
    fi

    if ! sm_is_configured 2>/dev/null; then
        echo "ERROR: Vault not configured. Set VAULT_ADDR and authenticate first." >&2
        return 1
    fi

    sm_audit "run" "INJECTED" "true"
    "$@"
}

# sm_get() - Get a single secret value from Vault
sm_get() {
    local secret_path="${1:-}"

    if [[ -z "$secret_path" ]]; then
        echo "ERROR: sm_get requires a secret path" >&2
        return 1
    fi

    if ! sm_is_configured 2>/dev/null; then
        echo "ERROR: Vault not configured" >&2
        return 1
    fi

    local value
    value=$(vault kv get -format=json "$secret_path" 2>/dev/null | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["data"]["data"].get(list(d["data"]["data"].keys())[0],""))' 2>/dev/null) || {
        echo "ERROR: Secret '$secret_path' not found or inaccessible" >&2
        return 1
    }

    echo "$value"
    sm_audit "get" "$secret_path" "true"
    return 0
}

# sm_audit() - Log secret access event
sm_audit() {
    local event_type="${1:-}"
    local secret_name="${2:-}"
    local success="${3:-true}"

    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

    if [[ -f "${script_dir}/audit_secrets.sh" ]]; then
        bash "${script_dir}/audit_secrets.sh" access "$secret_name" "sm_${event_type}" "$success" 2>/dev/null || true
    fi
}

# sm_set() - Prepare a command for setting a secret (HITL pattern)
sm_set() {
    local secret_path="${1:-}"

    if [[ -z "$secret_path" ]]; then
        echo "ERROR: sm_set requires a secret path" >&2
        return 1
    fi

    echo "vault kv put ${secret_path} <key>=<value>"
    echo ""
    echo "Run the above command in your terminal to set the secret."
    echo "The AI agent will wait for you to confirm completion."

    return 0
}

sm_is_configured() {
    command -v vault &> /dev/null && [[ -n "${VAULT_ADDR:-}" ]] && vault status &>/dev/null
}

export -f sm_init sm_status sm_run sm_get sm_audit sm_set sm_is_configured
