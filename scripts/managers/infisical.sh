#!/bin/bash

# Doppler Manager - Infisical Implementation
# Implements the secret manager interface for Infisical CLI

set -euo pipefail

MANAGER_NAME="infisical"
MANAGER_VERSION="1.0.0"

if [[ -z "${MANAGER_REGISTRY:-}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    source "${SCRIPT_DIR}/secret_manager_interface.sh" 2>/dev/null || true
fi

# sm_init() - Initialize Infisical CLI
sm_init() {
    sm_status
}

# sm_status() - Get Infisical status in JSON format
sm_status() {
    if ! command -v infisical &> /dev/null && ! command -v fi &> /dev/null; then
        cat <<EOF
{
  "status": "ERROR",
  "code": "E001",
  "message": "Infisical CLI is not installed",
  "hint": "Install Infisical CLI: https://infisical.com/docs/cli/overview",
  "documentation": "references/SOP.md#infisical-setup",
  "project": null,
  "config": null,
  "manager": "${MANAGER_NAME}"
}
EOF
        return 1
    fi

    # Use 'fi' if available (shorthand), otherwise 'infisical'
    local cli="infisical"
    command -v fi &>/dev/null && cli="fi"

    # Check authentication
    if ! $cli secrets list --limit 1 &>/dev/null; then
        cat <<EOF
{
  "status": "ERROR",
  "code": "E002",
  "message": "Infisical CLI is not authenticated",
  "hint": "Run 'infisical login' to authenticate",
  "documentation": "references/SOP.md#infisical-setup",
  "project": null,
  "config": null,
  "manager": "${MANAGER_NAME}"
}
EOF
        return 1
    fi

    # Get current project info
    local project_path
    project_path=$($cli config view --field=project_path 2>/dev/null || echo "")
    local environment
    environment=$($cli config view --field=environment 2>/dev/null || echo "dev")

    if [[ -z "$project_path" ]]; then
        cat <<EOF
{
  "status": "WARNING",
  "code": "E004",
  "message": "Infisical project not configured for this directory",
  "hint": "Run 'infisical init' or 'fi init' in your project directory",
  "documentation": "references/SOP.md#infisical-setup",
  "project": null,
  "config": null,
  "manager": "${MANAGER_NAME}"
}
EOF
        return 0
    fi

    cat <<EOF
{
  "status": "OK",
  "code": "E000",
  "message": "Infisical is authenticated and configured",
  "hint": "Ready to use 'infisical run -- <command>' for secret injection",
  "documentation": "references/SOP.md#infisical-setup",
  "project": "${project_path}",
  "config": "${environment}",
  "manager": "${MANAGER_NAME}"
}
EOF
    return 0
}

# sm_run() - Inject secrets and run a command via Infisical
sm_run() {
    if [[ $# -eq 0 ]]; then
        echo "ERROR: sm_run requires a command to execute" >&2
        return 1
    fi

    if ! sm_is_configured 2>/dev/null; then
        echo "ERROR: Infisical not configured. Run 'infisical login' first." >&2
        return 1
    fi

    local cli="infisical"
    command -v fi &>/dev/null && cli="fi"

    sm_audit "run" "INJECTED" "true"
    $cli run -- "$@"
}

# sm_get() - Get a single secret value from Infisical
sm_get() {
    local secret_name="${1:-}"

    if [[ -z "$secret_name" ]]; then
        echo "ERROR: sm_get requires a secret name" >&2
        return 1
    fi

    if ! sm_is_configured 2>/dev/null; then
        echo "ERROR: Infisical not configured" >&2
        return 1
    fi

    local cli="infisical"
    command -v fi &>/dev/null && cli="fi"

    local value
    value=$($cli secrets get "$secret_name" --plain 2>/dev/null) || {
        echo "ERROR: Secret '$secret_name' not found or inaccessible" >&2
        return 1
    }

    echo "$value"
    sm_audit "get" "$secret_name" "true"
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
    local secret_name="${1:-}"

    if [[ -z "$secret_name" ]]; then
        echo "ERROR: sm_set requires a secret name" >&2
        return 1
    fi

    local cli="infisical"
    command -v fi &>/dev/null && cli="fi"

    echo "${cli} secrets set ${secret_name}=<value>"
    echo ""
    echo "Run the above command in your terminal to set the secret."
    echo "The AI agent will wait for you to confirm completion."

    return 0
}

sm_is_configured() {
    local cli="infisical"
    command -v fi &>/dev/null && cli="fi"
    command -v "$cli" &>/dev/null && $cli secrets list --limit 1 &>/dev/null
}

sm_get_token_type() {
    local cli="infisical"
    command -v fi &>/dev/null && cli="fi"

    local token
    token=$($cli config view --field=token 2>/dev/null || echo "")

    if [[ -z "$token" ]]; then
        echo "NONE"
    elif echo "$token" | grep -q "^ip\.st\."; then
        echo "SERVICE_TOKEN"
    elif echo "$token" | grep -q "^ip\.pt\."; then
        echo "USER_TOKEN"
    else
        echo "UNKNOWN"
    fi
}

export -f sm_init sm_status sm_run sm_get sm_audit sm_set sm_is_configured sm_get_token_type
