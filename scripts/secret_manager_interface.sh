#!/bin/bash

# Doppler Manager - Secret Manager Interface
# Abstract interface for multi-secret-manager support
# All secret managers must implement the functions defined here

set -euo pipefail

# Interface version
SM_INTERFACE_VERSION="1.0.0"

# Default error codes (extended from base E000-E007)
declare -A SM_ERROR_CODES=(
    ["E100"]="MANAGER_NOT_SUPPORTED"
    ["E101"]="MANAGER_NOT_CONFIGURED"
    ["E102"]="MANAGER_SPECIFIC_ERROR"
)

# Current active manager
CURRENT_MANAGER="${CURRENT_MANAGER:-}"

# Source the tracing module if available
if [[ -f "${SCRIPT_DIR:-.}/tracing.sh" ]]; then
    source "${SCRIPT_DIR}/tracing.sh" 2>/dev/null || true
fi

# ============================================
# INTERFACE DEFINITION
# Each secret manager MUST implement these functions:
# ============================================

# sm_init() - Initialize/configure the manager
# Arguments: None
# Returns: 0 on success, non-zero on failure
# Output: JSON status object
sm_init() {
    echo '{"error": "Not implemented"}' >&2
    return 1
}

# sm_status() - Get current status of the manager
# Arguments: None
# Returns: 0 on success, non-zero on failure
# Output: JSON status object matching check_status.sh format:
#   {
#     "status": "OK|WARNING|ERROR",
#     "code": "E000|E001|...",
#     "message": "...",
#     "hint": "...",
#     "documentation": "...",
#     "project": "...",
#     "config": "..."
#   }
sm_status() {
    echo '{"error": "Not implemented"}' >&2
    return 1
}

# sm_run() - Inject secrets and run a command
# Arguments: command [args...]
# Returns: exit code of the command
# Principle: Memory-only injection, no secrets to disk
sm_run() {
    echo '{"error": "Not implemented"}' >&2
    return 1
}

# sm_get() - Get a single secret value (memory-only)
# Arguments: secret_name
# Returns: 0 on success, non-zero if not found
# Output: The secret value (plaintext)
# CRITICAL: Must NOT echo or log the value
sm_get() {
    echo '{"error": "Not implemented"}' >&2
    return 1
}

# sm_audit() - Log a secret access event
# Arguments: event_type, secret_name, success
# Returns: 0 on success
sm_audit() {
    local event_type="${1:-}"
    local secret_name="${2:-}"
    local success="${3:-true}"

    # Delegate to audit_secrets.sh if available
    if [[ -f "${SCRIPT_DIR:-.}/audit_secrets.sh" ]]; then
        bash "${SCRIPT_DIR}/audit_secrets.sh" access "$secret_name" "sm_run" "$success" 2>/dev/null || true
    fi
}

# sm_set() - Prepare a command for setting a secret (HITL pattern)
# Arguments: secret_name
# Returns: 0, outputs the CLI command for user to run
# Note: This does NOT set the secret - it provides the command for human execution
sm_set() {
    local secret_name="${1:-}"
    echo '{"error": "Not implemented"}' >&2
    return 1
}

# ============================================
# MANAGER REGISTRY
# ============================================

declare -A MANAGER_REGISTRY=()

# sm_register() - Register a secret manager implementation
# Arguments: manager_name, manager_script_path
sm_register() {
    local manager_name="${1:-}"
    local manager_script="${2:-}"

    if [[ -z "$manager_name" ]] || [[ -z "$manager_script" ]]; then
        echo "ERROR: sm_register requires manager_name and manager_script" >&2
        return 1
    fi

    MANAGER_REGISTRY["$manager_name"]="$manager_script"
    echo "Registered secret manager: $manager_name -> $manager_script"
}

# sm_list() - List all registered managers
sm_list() {
    for manager in "${!MANAGER_REGISTRY[@]}"; do
        echo "$manager: ${MANAGER_REGISTRY[$manager]}"
    done
}

# ============================================
# MANAGER LOADING
# ============================================

# sm_load() - Load a specific manager implementation
# Arguments: manager_name
sm_load() {
    local manager_name="${1:-}"

    if [[ -z "${MANAGER_REGISTRY[$manager_name]:-}" ]]; then
        echo "ERROR: Manager '$manager_name' not found in registry" >&2
        return 1
    fi

    local manager_script="${MANAGER_REGISTRY[$manager_name]}"

    if [[ ! -f "$manager_script" ]]; then
        echo "ERROR: Manager script '$manager_script' not found" >&2
        return 1
    fi

    source "$manager_script"
    CURRENT_MANAGER="$manager_name"

    echo "Loaded secret manager: $manager_name"
}

# ============================================
# HELPER FUNCTIONS
# ============================================

# sm_is_configured() - Check if current manager is properly configured
sm_is_configured() {
    if [[ -z "$CURRENT_MANAGER" ]]; then
        return 1
    fi

    # Try to get status
    if sm_status >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# sm_get_error_code() - Get human-readable error for SM error codes
# Arguments: error_code
sm_get_error_code() {
    local error_code="${1:-}"

    if [[ -n "${SM_ERROR_CODES[$error_code]:-}" ]]; then
        echo "${SM_ERROR_CODES[$error_code]}"
    else
        echo "UNKNOWN_ERROR"
    fi
}

# sm_get_error_description() - Get description for SM error codes
# Arguments: error_code
sm_get_error_description() {
    local error_code="${1:-}"

    case "$error_code" in
        E100)
            echo "The requested secret manager is not supported. Available managers: ${!MANAGER_REGISTRY[*]}"
            ;;
        E101)
            echo "The secret manager is not configured. Run 'sm_init' or check installation."
            ;;
        E102)
            echo "A manager-specific error occurred. Check the manager's documentation."
            ;;
        *)
            echo "Unknown error code: $error_code"
            ;;
    esac
}

# sm_get_recovery_command() - Get recovery command for SM error codes
# Arguments: error_code
sm_get_recovery_command() {
    local error_code="${1:-}"

    case "$error_code" in
        E100)
            echo "Run 'detect_manager.sh' to see available managers"
            ;;
        E101)
            echo "Run 'sm_init' or check the manager-specific setup instructions"
            ;;
        E102)
            echo "Check the manager's documentation for specific error resolution"
            ;;
        *)
            echo "Unknown error code: $error_code"
            ;;
    esac
}

# ============================================
# AUTO-DETECTION SUPPORT
# ============================================

# sm_detect_managers() - Detect all available managers
# Returns: 0 if any manager found, 1 otherwise
sm_detect_managers() {
    local detected=0
    local manager_dir="${SCRIPT_DIR:-.}/managers"

    if [[ -d "$manager_dir" ]]; then
        for manager_script in "$manager_dir"/*.sh; do
            if [[ -f "$manager_script" ]]; then
                local manager_name
                manager_name=$(basename "$manager_script" .sh)

                # Source the manager briefly to check if it's loadable
                if source "$manager_script" 2>/dev/null; then
                    if declare -f sm_status >/dev/null 2>&1; then
                        sm_register "$manager_name" "$manager_script"
                        detected=$((detected + 1))
                    fi
                fi
            fi
        done
    fi

    return $((detected == 0 ? 1 : 0))
}

# ============================================
# USAGE
# ============================================

sm_usage() {
    cat <<EOF
Secret Manager Interface (v${SM_INTERFACE_VERSION})

Usage: source secret_manager_interface.sh && sm_<command>

Commands:
  sm_register <name> <script>  Register a manager implementation
  sm_load <name>               Load a manager by name
  sm_list                      List all registered managers
  sm_is_configured             Check if current manager is ready
  sm_detect_managers           Auto-detect available managers
  sm_get_error_code <code>     Get error code name
  sm_get_error_description <code>  Get error description
  sm_get_recovery_command <code>   Get recovery suggestion

Manager Interface (must implement):
  sm_init()         Initialize the manager
  sm_status()       Get JSON status (check_status.sh format)
  sm_run <cmd>      Inject secrets and run command
  sm_get <name>     Get secret value (memory-only)
  sm_audit <type> <name> <success>  Log access event
  sm_set <name>     Output set command for HITL

Error Codes (E100-E102):
  E100 - MANAGER_NOT_SUPPORTED
  E101 - MANAGER_NOT_CONFIGURED
  E102 - MANAGER_SPECIFIC_ERROR
EOF
}

# If sourced directly with no arguments, show usage
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    sm_usage
fi
