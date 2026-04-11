#!/bin/bash

# Doppler Manager - HITL Secret Access Request Workflow
# Human-in-the-loop approval workflow for secret access

set -euo pipefail

# Source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/tracing.sh" 2>/dev/null || true
source "${SCRIPT_DIR}/error_codes.sh" 2>/dev/null || true

# Configuration
REQUEST_DIR="${HOME}/.config/doppler-manager/requests"
mkdir -p "$REQUEST_DIR"

# Request defaults
REQUEST_TTL_HOURS=24
DEFAULT_REQUESTER="${USER:-$(whoami)}"

# Generate unique request ID
generate_request_id() {
    if command -v uuidgen &> /dev/null; then
        uuidgen | tr '[:upper:]' '[:lower:]'
    else
        echo "req-$(date +%s)-$$-$(head -c 8 /dev/urandom | xxd -p)"
    fi
}

# JSON escape helper
json_escape() {
    local str="$1"
    str="${str//\\/\\\\}"
    str="${str//\"/\\\"}"
    str="${str//$'\n'/\\n}"
    str="${str//$'\t'/\\t}"
    printf '%s' "$str"
}

# Validate JSON (basic check)
is_valid_json() {
    local json="${1:-}"
    echo "$json" | jq . >/dev/null 2>&1
}

# Get current timestamp
timestamp() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# Create access request
# Usage: sm_request <secret> <reason>
sm_request() {
    local secret="${1:-}"
    local reason="${2:-}"

    if [[ -z "$secret" ]]; then
        echo '{"error": "E101", "message": "sm_request requires secret name"}' >&2
        return 1
    fi

    if [[ -z "$reason" ]]; then
        echo '{"error": "E101", "message": "sm_request requires reason for access"}' >&2
        return 1
    fi

    # Start tracing span if available
    local span_id=""
    if declare -f trace_span >/dev/null 2>&1; then
        span_id=$(trace_span "sm_request" "secret" "$secret")
    fi

    local request_id
    request_id=$(generate_request_id)

    local created_at
    created_at=$(timestamp)
    local expires_at
    expires_at=$(date -u -d "+${REQUEST_TTL_HOURS} hours" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || \
                  date -u -v+"${REQUEST_TTL_HOURS}"H +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || \
                  timestamp)

    local requester="${REQUESTER:-$DEFAULT_REQUESTER}"

    local request_file="${REQUEST_DIR}/${request_id}.json"

    cat > "$request_file" <<EOF
{
  "id": "$request_id",
  "secret": "$(json_escape "$secret")",
  "reason": "$(json_escape "$reason")",
  "requester": "$(json_escape "$requester")",
  "timestamp": "$created_at",
  "expires_at": "$expires_at",
  "status": "pending",
  "approved_by": null,
  "approved_at": null,
  "rejected_by": null,
  "rejected_at": null,
  "rejection_reason": null
}
EOF

    # Log the request
    if declare -f log_audit >/dev/null 2>&1 || [[ -f "${SCRIPT_DIR}/audit_secrets.sh" ]]; then
        bash "${SCRIPT_DIR}/audit_secrets.sh" access "$secret" "sm_request" "true" "request_id=$request_id" 2>/dev/null || true
    fi

    # Output request confirmation
    cat <<EOF
{
  "request_id": "$request_id",
  "secret": "$(json_escape "$secret")",
  "reason": "$(json_escape "$reason")",
  "requester": "$(json_escape "$requester")",
  "created_at": "$created_at",
  "expires_at": "$expires_at",
  "status": "pending",
  "message": "Access request created. Awaiting approval."
}
EOF

    [[ -n "$span_id" ]] && declare -f trace_end >/dev/null 2>&1 && trace_end "$span_id" "OK"

    return 0
}

# Approve access request
# Usage: sm_approve <request_id>
sm_approve() {
    local request_id="${1:-}"

    if [[ -z "$request_id" ]]; then
        echo '{"error": "E101", "message": "sm_approve requires request_id"}' >&2
        return 1
    fi

    # Start tracing span if available
    local span_id=""
    if declare -f trace_span >/dev/null 2>&1; then
        span_id=$(trace_span "sm_approve" "request_id" "$request_id")
    fi

    local request_file="${REQUEST_DIR}/${request_id}.json"

    if [[ ! -f "$request_file" ]]; then
        echo '{"error": "E102", "message": "Request not found: '"$request_id"'"}' >&2
        [[ -n "$span_id" ]] && declare -f trace_end >/dev/null 2>&1 && trace_end "$span_id" "ERROR" "Request not found"
        return 1
    fi

    # Check if already processed
    local current_status
    current_status=$(jq -r '.status' "$request_file")
    if [[ "$current_status" != "pending" ]]; then
        echo '{"error": "E102", "message": "Request already processed: '"$current_status"'"}' >&2
        [[ -n "$span_id" ]] && declare -f trace_end >/dev/null 2>&1 && trace_end "$span_id" "ERROR" "Already processed"
        return 1
    fi

    local approved_by="${APPROVER:-$DEFAULT_REQUESTER}"
    local approved_at
    approved_at=$(timestamp)

    # Update request
    jq --arg approved_by "$approved_by" \
       --arg approved_at "$approved_at" \
       '.status = "approved" | .approved_by = $approved_by | .approved_at = $approved_at' \
       "$request_file" > "${request_file}.tmp"
    mv "${request_file}.tmp" "$request_file"

    # Get secret name for audit
    local secret
    secret=$(jq -r '.secret' "$request_file")

    # Log approval
    if declare -f log_audit >/dev/null 2>&1 || [[ -f "${SCRIPT_DIR}/audit_secrets.sh" ]]; then
        bash "${SCRIPT_DIR}/audit_secrets.sh" access "$secret" "sm_approve" "true" "request_id=$request_id" 2>/dev/null || true
    fi

    # Output approval confirmation
    cat <<EOF
{
  "request_id": "$request_id",
  "secret": "$(json_escape "$secret")",
  "status": "approved",
  "approved_by": "$(json_escape "$approved_by")",
  "approved_at": "$approved_at",
  "message": "Access request approved."
}
EOF

    [[ -n "$span_id" ]] && declare -f trace_end >/dev/null 2>&1 && trace_end "$span_id" "OK"

    return 0
}

# Reject access request
# Usage: sm_reject <request_id> [reason]
sm_reject() {
    local request_id="${1:-}"
    local rejection_reason="${2:-No reason provided}"

    if [[ -z "$request_id" ]]; then
        echo '{"error": "E101", "message": "sm_reject requires request_id"}' >&2
        return 1
    fi

    # Start tracing span if available
    local span_id=""
    if declare -f trace_span >/dev/null 2>&1; then
        span_id=$(trace_span "sm_reject" "request_id" "$request_id")
    fi

    local request_file="${REQUEST_DIR}/${request_id}.json"

    if [[ ! -f "$request_file" ]]; then
        echo '{"error": "E102", "message": "Request not found: '"$request_id"'"}' >&2
        [[ -n "$span_id" ]] && declare -f trace_end >/dev/null 2>&1 && trace_end "$span_id" "ERROR" "Request not found"
        return 1
    fi

    # Check if already processed
    local current_status
    current_status=$(jq -r '.status' "$request_file")
    if [[ "$current_status" != "pending" ]]; then
        echo '{"error": "E102", "message": "Request already processed: '"$current_status"'"}' >&2
        [[ -n "$span_id" ]] && declare -f trace_end >/dev/null 2>&1 && trace_end "$span_id" "ERROR" "Already processed"
        return 1
    fi

    local rejected_by="${APPROVER:-$DEFAULT_REQUESTER}"
    local rejected_at
    rejected_at=$(timestamp)

    # Update request
    jq --arg rejected_by "$rejected_by" \
       --arg rejected_at "$rejected_at" \
       --arg rejection_reason "$rejection_reason" \
       '.status = "rejected" | .rejected_by = $rejected_by | .rejected_at = $rejected_at | .rejection_reason = $rejection_reason' \
       "$request_file" > "${request_file}.tmp"
    mv "${request_file}.tmp" "$request_file"

    # Get secret name for audit
    local secret
    secret=$(jq -r '.secret' "$request_file")

    # Log rejection
    if declare -f log_audit >/dev/null 2>&1 || [[ -f "${SCRIPT_DIR}/audit_secrets.sh" ]]; then
        bash "${SCRIPT_DIR}/audit_secrets.sh" access "$secret" "sm_reject" "true" "request_id=$request_id" 2>/dev/null || true
    fi

    # Output rejection confirmation
    cat <<EOF
{
  "request_id": "$request_id",
  "secret": "$(json_escape "$secret")",
  "status": "rejected",
  "rejected_by": "$(json_escape "$rejected_by")",
  "rejected_at": "$rejected_at",
  "rejection_reason": "$(json_escape "$rejection_reason")",
  "message": "Access request rejected."
}
EOF

    [[ -n "$span_id" ]] && declare -f trace_end >/dev/null 2>&1 && trace_end "$span_id" "OK"

    return 0
}

# List pending requests
sm_list_requests() {
    local status_filter="${1:-all}"  # all, pending, approved, rejected, expired

    local requests=()

    for request_file in "${REQUEST_DIR}"/*.json; do
        [[ -f "$request_file" ]] || continue

        local file_status
        file_status=$(jq -r '.status' "$request_file")

        if [[ "$status_filter" != "all" ]] && [[ "$file_status" != "$status_filter" ]]; then
            continue
        fi

        # Check for expired pending requests
        if [[ "$file_status" == "pending" ]]; then
            local expires_at
            expires_at=$(jq -r '.expires_at' "$request_file")
            local now
            now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

            if [[ "$expires_at" < "$now" ]]; then
                # Mark as expired
                jq '.status = "expired"' "$request_file" > "${request_file}.tmp"
                mv "${request_file}.tmp" "$request_file"
                file_status="expired"
            fi
        fi

        requests+=("$request_file")
    done

    if [[ ${#requests[@]} -eq 0 ]]; then
        echo '{"requests": [], "count": 0, "filter": "'"$status_filter"'"}'
        return 0
    fi

    # Sort by timestamp (newest first)
    local sorted_files
    sorted_files=$(printf '%s\n' "${requests[@]}" | xargs ls -t 2>/dev/null || echo "${requests[0]}")

    local json="{\"requests\":["
    local first=true
    for request_file in $sorted_files; do
        [[ -f "$request_file" ]] || continue
        if [[ "$first" == "true" ]]; then
            first=false
        else
            json+=","
        fi
        json+=$(jq -c '.' "$request_file")
    done
    json+="],\"count\":${#requests[@]},\"filter\":\"$status_filter\"}"

    echo "$json"
    return 0
}

# Get request details
sm_get_request() {
    local request_id="${1:-}"

    if [[ -z "$request_id" ]]; then
        echo '{"error": "E101", "message": "sm_get_request requires request_id"}' >&2
        return 1
    fi

    local request_file="${REQUEST_DIR}/${request_id}.json"

    if [[ ! -f "$request_file" ]]; then
        echo '{"error": "E102", "message": "Request not found: '"$request_id"'"}' >&2
        return 1
    fi

    cat "$request_file"
    return 0
}

# Cancel a pending request (by requester)
sm_cancel_request() {
    local request_id="${1:-}"

    if [[ -z "$request_id" ]]; then
        echo '{"error": "E101", "message": "sm_cancel_request requires request_id"}' >&2
        return 1
    fi

    local request_file="${REQUEST_DIR}/${request_id}.json"

    if [[ ! -f "$request_file" ]]; then
        echo '{"error": "E102", "message": "Request not found: '"$request_id"'"}' >&2
        return 1
    fi

    local current_status
    current_status=$(jq -r '.status' "$request_file")
    local requester
    requester=$(jq -r '.requester' "$request_file")
    local current_user
    current_user="${USER:-$(whoami)}"

    if [[ "$current_status" != "pending" ]]; then
        echo '{"error": "E102", "message": "Can only cancel pending requests"}' >&2
        return 1
    fi

    if [[ "$requester" != "$current_user" ]]; then
        echo '{"error": "E005", "message": "Only the requester can cancel a request"}' >&2
        return 1
    fi

    jq '.status = "cancelled"' "$request_file" > "${request_file}.tmp"
    mv "${request_file}.tmp" "$request_file"

    echo '{"status": "cancelled", "request_id": "'"$request_id"'"}'
    return 0
}

# Cleanup expired requests
sm_cleanup_requests() {
    local cleaned=0
    local now
    now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    for request_file in "${REQUEST_DIR}"/*.json; do
        [[ -f "$request_file" ]] || continue

        local status
        status=$(jq -r '.status' "$request_file")
        local expires_at
        expires_at=$(jq -r '.expires_at' "$request_file")

        if [[ "$status" == "pending" ]] && [[ "$expires_at" < "$now" ]]; then
            jq '.status = "expired"' "$request_file" > "${request_file}.tmp"
            mv "${request_file}.tmp" "$request_file"
            cleaned=$((cleaned + 1))
        fi
    done

    echo "{\"cleaned\": $cleaned}"
    return 0
}

# Main dispatcher
case "${1:-}" in
    request)
        sm_request "${2:-}" "${3:-}"
        ;;
    approve)
        sm_approve "${2:-}"
        ;;
    reject)
        sm_reject "${2:-}" "${3:-}"
        ;;
    list)
        sm_list_requests "${2:-}"
        ;;
    get)
        sm_get_request "${2:-}"
        ;;
    cancel)
        sm_cancel_request "${2:-}"
        ;;
    cleanup)
        sm_cleanup_requests
        ;;
    *)
        cat <<EOF
HITL Access Request Manager

Usage: $0 <command> [arguments]

Commands:
  request <secret> <reason>      Create access request
  approve <request_id>          Approve pending request
  reject <request_id> [reason]  Reject pending request
  list [status]                 List requests (status: all, pending, approved, rejected, expired)
  get <request_id>              Get request details
  cancel <request_id>           Cancel pending request (by requester)
  cleanup                       Clean up expired requests

Examples:
  $0 request API_KEY "Need access for deployment script"
  $0 approve req-12345
  $0 reject req-12345 "Insufficient justification"
  $0 list pending

Request Storage:
  $REQUEST_DIR

Error Codes:
  E101 - Missing required arguments
  E102 - Request not found or invalid
  E005 - Permission denied
EOF
        ;;
esac
