#!/bin/bash

# Doppler Manager - Secret Access Audit Logger
# Records all secret access attempts for security auditing
# Output format: JSON Lines (JSONL) for easy parsing and ingestion

set -euo pipefail

# Configuration
AUDIT_LOG_DIR="${DOPPLER_AUDIT_DIR:-${HOME}/.cache/doppler-manager}"
AUDIT_LOG_FILE="${AUDIT_LOG_DIR}/audit.log"
ALERT_LOG_FILE="${AUDIT_LOG_DIR}/alerts.log"

# Ensure audit directory exists
mkdir -p "$AUDIT_LOG_DIR"

# Timestamp in ISO 8601 format
timestamp() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# Generate UUID for correlation
generate_id() {
    if command -v uuidgen &> /dev/null; then
        uuidgen | tr '[:upper:]' '[:lower:]'
    else
        # Fallback for systems without uuidgen
        echo "$(date +%s)-$$-$(head -c 16 /dev/urandom | base64)"
    fi
}

# Log an audit event
log_audit() {
    local event_type="$1"
    local event_data="$2"
    local log_file="${3:-$AUDIT_LOG_FILE}"

    printf '%s\n' "{\"id\":\"$(generate_id)\",\"timestamp\":\"$(timestamp)\",\"type\":\"$event_type\",\"data\":$event_data,\"agent\":\"doppler-manager-skill\",\"version\":\"1.0.0\"}" >> "$log_file"
}

# Log a secret access event
log_secret_access() {
    local secret_name="${1:-UNKNOWN}"
    local access_method="${2:-doppler_run}"
    local success="${3:-true}"
    local error_msg="${4:-}"

    local success_json="true"
    if [[ "$success" != "true" ]]; then
        success_json="false"
    fi

    local data_json
    if [[ -n "$error_msg" ]]; then
        local error_json
        error_json=$(printf '%s' "$error_msg" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))' 2>/dev/null || echo "\"$error_msg\"")
        data_json="{\"secret_name\":\"$secret_name\",\"access_method\":\"$access_method\",\"success\":$success_json,\"error\":$error_json}"
    else
        data_json="{\"secret_name\":\"$secret_name\",\"access_method\":\"$access_method\",\"success\":$success_json}"
    fi

    log_audit "SECRET_ACCESS" "$data_json"
}

# Log a potential leak detection
log_leak_detected() {
    local leak_type="${1:-UNKNOWN}"
    local context="${2:-}"
    local severity="${3:-MEDIUM}"

    local data_json
    if [[ -n "$context" ]]; then
        local context_json
        context_json=$(printf '%s' "$context" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))' 2>/dev/null || echo "\"redacted\"")
        data_json="{\"leak_type\":\"$leak_type\",\"context\":$context_json,\"severity\":\"$severity\"}"
    else
        data_json="{\"leak_type\":\"$leak_type\",\"severity\":\"$severity\"}"
    fi

    log_audit "LEAK_DETECTED" "$data_json" "$ALERT_LOG_FILE"

    # Also print warning
    echo "[ALERT] Potential secret leak detected: $leak_type (severity: $severity)" >&2
}

# Log an auth event
log_auth_event() {
    local auth_type="${1:-unknown}"
    local success="${2:-true}"
    local user="${3:-}"
    local project="${4:-}"

    local data_json
    if [[ -n "$user" ]]; then
        data_json="{\"auth_type\":\"$auth_type\",\"success\":$success,\"user\":\"$user\",\"project\":\"$project\"}"
    else
        data_json="{\"auth_type\":\"$auth_type\",\"success\":$success}"
    fi

    log_audit "AUTH_EVENT" "$data_json"
}

# Log a command execution with secrets
log_command_exec() {
    local command="${1:-}"
    local cwd="${2:-$(pwd)}"
    local success="${3:-true}"
    local exit_code="${4:-0}"

    local data_json
    data_json="{\"command\":\"$command\",\"cwd\":\"$cwd\",\"success\":$success,\"exit_code\":$exit_code}"

    log_audit "COMMAND_EXEC" "$data_json"
}

# View recent audit logs
view_logs() {
    local lines="${1:-50}"

    if [[ -f "$AUDIT_LOG_FILE" ]]; then
        echo "=== Recent Audit Logs (last $lines entries) ==="
        tail -n "$lines" "$AUDIT_LOG_FILE" | python3 -m json.tool 2>/dev/null || tail -n "$lines" "$AUDIT_LOG_FILE"
    else
        echo "No audit logs found at $AUDIT_LOG_FILE"
    fi
}

# View alerts
view_alerts() {
    if [[ -f "$ALERT_LOG_FILE" ]]; then
        echo "=== Security Alerts ==="
        cat "$ALERT_LOG_FILE" | python3 -m json.tool 2>/dev/null || cat "$ALERT_LOG_FILE"
    else
        echo "No alerts found"
    fi
}

# Export logs for review
export_logs() {
    local output_file="${1:-doppler-audit-export.jsonl}"

    if [[ -f "$AUDIT_LOG_FILE" ]]; then
        cp "$AUDIT_LOG_FILE" "$output_file"
        echo "Exported audit logs to $output_file"
    else
        echo "No logs to export"
        return 1
    fi
}

# Clean old logs (retention policy)
clean_logs() {
    local retention_days="${1:-30}"

    if [[ -f "$AUDIT_LOG_FILE" ]]; then
        # Remove entries older than retention_days
        local temp_file
        temp_file=$(mktemp)
        while IFS= read -r line; do
            local log_time
            log_time=$(echo "$line" | python3 -c 'import json,sys; print(json.load(sys.stdin)["timestamp"])' 2>/dev/null || echo "")
            if [[ -n "$log_time" ]]; then
                local log_date
                log_date=$(date -d "$log_time" +%s 2>/dev/null || echo "0")
                local cutoff_date
                cutoff_date=$(date -d "$retention_days days ago" +%s 2>/dev/null || echo "0")
                if [[ "$log_date" -gt "$cutoff_date" ]]; then
                    echo "$line" >> "$temp_file"
                fi
            fi
        done < "$AUDIT_LOG_FILE"
        mv "$temp_file" "$AUDIT_LOG_FILE"
        echo "Cleaned logs older than $retention_days days"
    fi
}

# Main command dispatcher
case "${1:-}" in
    access)
        log_secret_access "${2:-}" "${3:-doppler_run}" "${4:-true}" "${5:-}"
        ;;
    leak)
        log_leak_detected "${2:-UNKNOWN}" "${3:-}" "${4:-MEDIUM}"
        ;;
    auth)
        log_auth_event "${2:-unknown}" "${3:-true}" "${4:-}" "${5:-}"
        ;;
    exec)
        log_command_exec "${2:-}" "${3:-}" "${4:-true}" "${5:-0}"
        ;;
    view)
        view_logs "${2:-50}"
        ;;
    alerts)
        view_alerts
        ;;
    export)
        export_logs "${2:-doppler-audit-export.jsonl}"
        ;;
    clean)
        clean_logs "${2:-30}"
        ;;
    *)
        echo "Doppler Manager Audit Logger"
        echo ""
        echo "Usage:"
        echo "  $0 access <secret_name> <method> <success> [error_msg]"
        echo "  $0 leak <type> [context] [severity]"
        echo "  $0 auth <type> <success> [user] [project]"
        echo "  $0 exec <command> <cwd> <success> <exit_code>"
        echo "  $0 view [lines]"
        echo "  $0 alerts"
        echo "  $0 export [output_file]"
        echo "  $0 clean [retention_days]"
        echo ""
        echo "Examples:"
        echo "  $0 access DATABASE_URL doppler_run true"
        echo "  $0 leak PASTED_SECRET 'User pasted API key in chat' HIGH"
        echo "  $0 auth service_token true service-account prod-project"
        echo ""
        echo "Log files:"
        echo "  Audit: $AUDIT_LOG_FILE"
        echo "  Alerts: $ALERT_LOG_FILE"
        ;;
esac