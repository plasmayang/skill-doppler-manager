#!/bin/bash

# Doppler Manager - Doppler Implementation
# Implements the secret manager interface for Doppler CLI
# Refactored from check_status.sh logic

set -euo pipefail

# Manager identification
MANAGER_NAME="doppler"
MANAGER_VERSION="1.0.0"

# Source the interface if being loaded standalone
if [[ -z "${MANAGER_REGISTRY:-}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    source "${SCRIPT_DIR}/secret_manager_interface.sh" 2>/dev/null || true
fi

# ============================================
# REQUIRED INTERFACE IMPLEMENTATIONS
# ============================================

# sm_init() - Initialize Doppler CLI
# Checks if Doppler is installed and authenticated
sm_init() {
    sm_status
}

# sm_status() - Get Doppler status in JSON format
# Returns JSON matching check_status.sh format
sm_status() {
    # Ensure Doppler CLI is installed
    if ! command -v doppler &> /dev/null; then
        cat <<EOF
{
  "status": "ERROR",
  "code": "E001",
  "message": "Doppler CLI is not installed",
  "hint": "Install Doppler CLI: https://docs.doppler.com/docs/install-cli",
  "documentation": "references/SOP.md#phase-1",
  "project": null,
  "config": null,
  "manager": "${MANAGER_NAME}"
}
EOF
        return 1
    fi

    # Check configuration and authentication
    local configure_output
    configure_output=$(doppler configure 2>&1)
    local configure_exit=$?

    if [[ $configure_exit -ne 0 ]]; then
        # Determine specific error type
        if echo "$configure_output" | grep -qi "expired\|invalid\|unauthorized"; then
            cat <<EOF
{
  "status": "ERROR",
  "code": "E003",
  "message": "Doppler token has expired or is invalid",
  "hint": "Run 'doppler login' to re-authenticate",
  "documentation": "references/SOP.md#phase-2",
  "project": null,
  "config": null,
  "manager": "${MANAGER_NAME}"
}
EOF
        elif echo "$configure_output" | grep -qi "permission\|denied"; then
            cat <<EOF
{
  "status": "ERROR",
  "code": "E005",
  "message": "Permission denied to access Doppler secrets",
  "hint": "Verify your Doppler access token has appropriate permissions",
  "documentation": "references/SOP.md#troubleshooting",
  "project": null,
  "config": null,
  "manager": "${MANAGER_NAME}"
}
EOF
        elif echo "$configure_output" | grep -qi "network\|connection\|timeout"; then
            cat <<EOF
{
  "status": "ERROR",
  "code": "E006",
  "message": "Network error connecting to Doppler",
  "hint": "Check your internet connection and VPN settings",
  "documentation": "references/SOP.md#troubleshooting",
  "project": null,
  "config": null,
  "manager": "${MANAGER_NAME}"
}
EOF
        else
            cat <<EOF
{
  "status": "ERROR",
  "code": "E002",
  "message": "Doppler CLI is not authenticated or configured",
  "hint": "Run 'doppler login' to authenticate",
  "documentation": "references/SOP.md#phase-2",
  "project": null,
  "config": null,
  "manager": "${MANAGER_NAME}"
}
EOF
        fi
        return 1
    fi

    # Extract Project and Config
    local project
    local config
    project=$(doppler configure get project --plain 2>/dev/null)
    config=$(doppler configure get config --plain 2>/dev/null)

    # Validate project and config
    if [[ -n "$project" ]] && [[ -n "$config" ]]; then
        if echo "$project" | grep -qiE "^(error|null|none|undefined)$" || \
           echo "$config" | grep -qiE "^(error|null|none|undefined)$"; then
            cat <<EOF
{
  "status": "ERROR",
  "code": "E007",
  "message": "Config mismatch detected - project or config contains invalid values",
  "hint": "Run 'doppler setup --project <project> --config <config>' to reconfigure",
  "documentation": "references/SOP.md#phase-3",
  "project": null,
  "config": null,
  "manager": "${MANAGER_NAME}"
}
EOF
            return 1
        fi

        # Verify the project/config actually works
        local verify_output
        verify_output=$(doppler secrets get DOPPLER_CONFIG_CHECK --plain 2>&1)
        local verify_exit=$?

        if [[ $verify_exit -ne 0 ]] && echo "$verify_output" | grep -qiE "not found|does not exist|invalid"; then
            : # Secret doesn't exist but config is valid - this is OK
        fi
    fi

    # Determine status
    if [[ -z "$project" ]] || [[ -z "$config" ]]; then
        cat <<EOF
{
  "status": "WARNING",
  "code": "E004",
  "message": "Authenticated, but no default Project or Config is set for this directory",
  "hint": "Run 'doppler setup' to configure project and config for this directory",
  "documentation": "references/SOP.md#phase-3",
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
  "message": "Authenticated and configured",
  "hint": "Ready to use 'doppler run -- <command>' for secret injection",
  "documentation": "references/SOP.md",
  "project": "${project}",
  "config": "${config}",
  "manager": "${MANAGER_NAME}"
}
EOF
    return 0
}

# sm_run() - Inject secrets and run command via Doppler
# Arguments: command [args...]
# Returns: exit code of the command
# Principle: Memory-only injection via doppler run
sm_run() {
    if [[ $# -eq 0 ]]; then
        echo "ERROR: sm_run requires a command to execute" >&2
        return 1
    fi

    # Check if configured before running
    if ! sm_is_configured 2>/dev/null; then
        echo "ERROR: Doppler not configured. Run 'doppler login' or 'doppler setup' first." >&2
        return 1
    fi

    # Log the access attempt
    sm_audit "run" "INJECTED" "true"

    # Execute via Doppler (memory-only injection)
    doppler run -- "$@"
}

# sm_get() - Get a single secret value (memory-only)
# Arguments: secret_name
# Returns: 0 on success, prints secret value
# CRITICAL: Must NOT echo or log the value
sm_get() {
    local secret_name="${1:-}"

    if [[ -z "$secret_name" ]]; then
        echo "ERROR: sm_get requires a secret name" >&2
        return 1
    fi

    # Check if configured
    if ! sm_is_configured 2>/dev/null; then
        echo "ERROR: Doppler not configured" >&2
        return 1
    fi

    # Get secret value directly (it will be consumed by caller)
    # This is allowed because the value is "immediately consumed" per SKILL.md
    local value
    value=$(doppler secrets get "$secret_name" --plain 2>/dev/null)

    if [[ $? -ne 0 ]]; then
        echo "ERROR: Secret '$secret_name' not found or inaccessible" >&2
        return 1
    fi

    # Output the value (caller is responsible for not exposing it)
    echo "$value"

    # Log access
    sm_audit "get" "$secret_name" "true"

    return 0
}

# sm_audit() - Log secret access event
# Arguments: event_type, secret_name, success
sm_audit() {
    local event_type="${1:-}"
    local secret_name="${2:-}"
    local success="${3:-true}"

    # Delegate to audit_secrets.sh if available
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

    if [[ -f "${script_dir}/audit_secrets.sh" ]]; then
        bash "${script_dir}/audit_secrets.sh" access "$secret_name" "sm_${event_type}" "$success" 2>/dev/null || true
    fi
}

# sm_set() - Prepare a command for setting a secret (HITL pattern)
# Arguments: secret_name
# Returns: 0, outputs the CLI command for user to run
# Note: This does NOT set the secret - it provides the command for human execution
sm_set() {
    local secret_name="${1:-}"

    if [[ -z "$secret_name" ]]; then
        echo "ERROR: sm_set requires a secret name" >&2
        return 1
    fi

    # Output the command for HITL
    echo "doppler secrets set ${secret_name}=<value>"
    echo ""
    echo "Run the above command in your terminal to set the secret."
    echo "The AI agent will wait for you to confirm completion."

    return 0
}

# ============================================
# HELPER FUNCTIONS
# ============================================

# sm_is_configured() - Check if Doppler is properly configured
sm_is_configured() {
    if ! command -v doppler &> /dev/null; then
        return 1
    fi

    if ! doppler configure &>/dev/null; then
        return 1
    fi

    return 0
}

# sm_get_token_type() - Get the type of Doppler token in use
# Returns: "SERVICE_TOKEN", "USER_TOKEN", or "UNKNOWN"
sm_get_token_type() {
    local token
    token=$(doppler configure get token --plain 2>/dev/null || echo "")

    if echo "$token" | grep -q "^dp\.st\."; then
        echo "SERVICE_TOKEN"
    elif echo "$token" | grep -q "^dp\.pt\."; then
        echo "USER_TOKEN"
    elif [[ -n "$token" ]]; then
        echo "UNKNOWN"
    else
        echo "NONE"
    fi
}

# sm_get_project_config() - Get current project and config
# Returns: project config (newline separated)
sm_get_project_config() {
    local project
    local config

    project=$(doppler configure get project --plain 2>/dev/null || echo "")
    config=$(doppler configure get config --plain 2>/dev/null || echo "")

    echo "$project"
    echo "$config"
}

# sm_validate_secret_name() - Validate a secret name format
# Arguments: secret_name
# Returns: 0 if valid, 1 otherwise
sm_validate_secret_name() {
    local secret_name="${1:-}"

    # Secret names should be uppercase with underscores
    if [[ "$secret_name" =~ ^[A-Z][A-Z0-9_]*$ ]]; then
        return 0
    else
        return 1
    fi
}

# Export functions for use when sourced
export -f sm_init
export -f sm_status
export -f sm_run
export -f sm_get
export -f sm_audit
export -f sm_set
export -f sm_is_configured
export -f sm_get_token_type
export -f sm_get_project_config
export -f sm_validate_secret_name
