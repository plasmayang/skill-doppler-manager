#!/bin/bash

# Doppler Manager - Secret Rotation Detection and Triggering
# Detects stale secrets and triggers rotation workflows

set -euo pipefail

# Source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/tracing.sh" 2>/dev/null || true
source "${SCRIPT_DIR}/error_codes.sh" 2>/dev/null || true

# Configuration
ROTATION_STATE_DIR="${HOME}/.cache/doppler-manager/rotation"
mkdir -p "$ROTATION_STATE_DIR"

# Rotation defaults
STALE_THRESHOLD_DAYS=90
ROTATION_WARNING_DAYS=30

# Generate unique rotation ID
generate_rotation_id() {
    if command -v uuidgen &> /dev/null; then
        uuidgen | tr '[:upper:]' '[:lower:]'
    else
        echo "rot-$(date +%s)-$$-$(head -c 8 /dev/urandom | xxd -p)"
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

# Record secret access for rotation tracking
record_access() {
    local secret="${1:-}"
    local access_method="${2:-sm_get}"

    if [[ -z "$secret" ]]; then
        return 1
    fi

    local access_file="${ROTATION_STATE_DIR}/${secret}.json"
    local now
    now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local last_access="${now}"

    if [[ -f "$access_file" ]]; then
        last_access=$(jq -r '.last_access // "'"$now"'"' "$access_file" 2>/dev/null || echo "$now")
    fi

    cat > "$access_file" <<EOF
{
  "secret": "$(json_escape "$secret")",
  "last_access": "$last_access",
  "last_rotation": $(jq -r '.last_rotation // null' "$access_file" 2>/dev/null || echo "null"),
  "rotation_count": $(jq -r '.rotation_count // 0' "$access_file" 2>/dev/null || echo "0"),
  "status": "active"
}
EOF
}

# Calculate days since last access
days_since_access() {
    local secret="${1:-}"
    local access_file="${ROTATION_STATE_DIR}/${secret}.json"

    if [[ ! -f "$access_file" ]]; then
        echo "999"
        return
    fi

    local last_access
    last_access=$(jq -r '.last_access' "$access_file" 2>/dev/null)

    if [[ -z "$last_access" ]] || [[ "$last_access" == "null" ]]; then
        echo "999"
        return
    fi

    local last_date
    last_date=$(date -d "$last_access" +%s 2>/dev/null)
    local now_date
    now_date=$(date +%s)
    local diff_seconds=$((now_date - last_date))
    local diff_days=$((diff_seconds / 86400))

    echo "$diff_days"
}

# Check if rotation is needed for a secret
check_rotation_needed() {
    local secret="${1:-}"

    if [[ -z "$secret" ]]; then
        echo '{"error": "E101", "message": "check_rotation_needed requires secret name"}' >&2
        return 1
    fi

    local days
    days=$(days_since_access "$secret")
    local threshold="${2:-$STALE_THRESHOLD_DAYS}"

    if [[ "$days" -ge "$threshold" ]]; then
        echo '{"rotation_needed": true, "days_since_access": '"$days"', "threshold": '"$threshold"', "severity": "HIGH"}'
        return 0
    elif [[ "$days" -ge "$((threshold / 3))" ]]; then
        echo '{"rotation_needed": false, "days_since_access": '"$days"', "threshold": '"$threshold"', "severity": "WARNING"}'
        return 0
    else
        echo '{"rotation_needed": false, "days_since_access": '"$days"', "threshold": '"$threshold"', "severity": "OK"}'
        return 0
    fi
}

# Check rotation status for all tracked secrets
check_rotation_status() {
    local manager="${1:-}"
    local output_format="${2:-summary}"  # summary or detailed

    local secrets=()
    for access_file in "${ROTATION_STATE_DIR}"/*.json; do
        [[ -f "$access_file" ]] || continue
        secrets+=("$(basename "$access_file" .json)")
    done

    if [[ ${#secrets[@]} -eq 0 ]]; then
        echo '{"status": "OK", "tracked_secrets": 0, "secrets_needing_rotation": 0, "warnings": 0}'
        return 0
    fi

    local needs_rotation=0
    local warnings=0
    local details=()
    local stale_threshold="${3:-$STALE_THRESHOLD_DAYS}"

    for secret in "${secrets[@]}"; do
        local status
        status=$(check_rotation_needed "$secret" "$stale_threshold")

        local rotation_needed
        rotation_needed=$(echo "$status" | jq -r '.rotation_needed')
        local severity
        severity=$(echo "$status" | jq -r '.severity')
        local days
        days=$(echo "$status" | jq -r '.days_since_access')

        if [[ "$rotation_needed" == "true" ]]; then
            needs_rotation=$((needs_rotation + 1))
            details+=("{\"secret\":\"$(json_escape "$secret")\",\"status\":\"STALE\",\"days\":$days,\"manager\":\"$(json_escape "$manager")\"}")
        elif [[ "$severity" == "WARNING" ]]; then
            warnings=$((warnings + 1))
            details+=("{\"secret\":\"$(json_escape "$secret")\",\"status\":\"AGING\",\"days\":$days,\"manager\":\"$(json_escape "$manager")\"}")
        else
            details+=("{\"secret\":\"$(json_escape "$secret")\",\"status\":\"OK\",\"days\":$days,\"manager\":\"$(json_escape "$manager")\"}")
        fi
    done

    local summary
    if [[ "$needs_rotation" -gt 0 ]]; then
        summary="ERROR"
    elif [[ "$warnings" -gt 0 ]]; then
        summary="WARNING"
    else
        summary="OK"
    fi

    if [[ "$output_format" == "detailed" ]]; then
        cat <<EOF
{
  "status": "$summary",
  "tracked_secrets": ${#secrets[@]},
  "secrets_needing_rotation": $needs_rotation,
  "warnings": $warnings,
  "threshold_days": $stale_threshold,
  "details": [$(IFS=,; echo "${details[*]}")]
}
EOF
    else
        cat <<EOF
{
  "status": "$summary",
  "tracked_secrets": ${#secrets[@]},
  "secrets_needing_rotation": $needs_rotation,
  "warnings": $warnings,
  "threshold_days": $stale_threshold
}
EOF
    fi

    [[ "$summary" == "ERROR" ]] && return 2
    [[ "$summary" == "WARNING" ]] && return 1
    return 0
}

# Trigger rotation for a secret
sm_rotate() {
    local manager="${1:-}"
    local secret="${2:-}"

    if [[ -z "$manager" ]] || [[ -z "$secret" ]]; then
        echo '{"error": "E101", "message": "sm_rotate requires manager and secret arguments"}' >&2
        return 1
    fi

    # Start tracing span if available
    local span_id=""
    if declare -f trace_span >/dev/null 2>&1; then
        span_id=$(trace_span "sm_rotate" "manager" "$manager" "secret" "$secret")
    fi

    local rotation_id
    rotation_id=$(generate_rotation_id)

    local started_at
    started_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local status="pending"
    local error_message=""

    # Create rotation record
    local rotation_file="${ROTATION_STATE_DIR}/rotation-${rotation_id}.json"
    cat > "$rotation_file" <<EOF
{
  "rotation_id": "$rotation_id",
  "secret": "$(json_escape "$secret")",
  "manager": "$(json_escape "$manager")",
  "started_at": "$started_at",
  "completed_at": null,
  "status": "pending",
  "error": null
}
EOF

    # Execute rotation based on manager
    local result
    case "$manager" in
        doppler)
            # Doppler secrets are immutable; rotation is handled by updating the secret value
            # This triggers a new version in Doppler
            result=$(doppler secrets set "$secret" --value "$(openssl rand -base64 32)" 2>&1) && status="completed" || {
                status="failed"
                error_message="$result"
            }
            ;;
        vault)
            # Vault supports automatic rotation via lease renewals
            result=$(vault lease renew "$secret" 2>&1) && status="completed" || {
                status="failed"
                error_message="$result"
            }
            ;;
        aws_secrets)
            # AWS Secrets Manager rotation
            result=$(aws secretsmanager rotate-secret --secret-id "$secret" 2>&1) && status="completed" || {
                status="failed"
                error_message="$result"
            }
            ;;
        gcp_secret)
            # GCP Secret Manager rotation
            result=$(gcloud secrets versions add "$secret" --data-file=- 2>&1 <<< "$(openssl rand -base64 32)") && status="completed" || {
                status="failed"
                error_message="$result"
            }
            ;;
        azure_key)
            # Azure Key Vault rotation
            result=$(az keyvault secret set --vault-name "${AZURE_VAULT:-}" --name "$secret" --value "$(openssl rand -base64 32)" 2>&1) && status="completed" || {
                status="failed"
                error_message="$result"
            }
            ;;
        infisical)
            # Infisical rotation
            result=$(infisical secrets set "$secret" --value "$(openssl rand -base64 32)" 2>&1) && status="completed" || {
                status="failed"
                error_message="$result"
            }
            ;;
        *)
            echo '{"error": "E100", "message": "Manager '"'"'"'"$manager"'"'"'"' does not support rotation"}' >&2
            [[ -n "$span_id" ]] && declare -f trace_end >/dev/null 2>&1 && trace_end "$span_id" "ERROR" "Unsupported manager"
            return 1
            ;;
    esac

    local completed_at=""
    if [[ "$status" == "completed" ]]; then
        completed_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

        # Update access record with rotation info
        local access_file="${ROTATION_STATE_DIR}/${secret}.json"
        if [[ -f "$access_file" ]]; then
            local last_rotation
            last_rotation=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
            local rotation_count
            rotation_count=$(($(jq -r '.rotation_count // 0' "$access_file") + 1))
            jq --arg "$last_rotation" --argjson count "$rotation_count" \
               '.last_rotation = $last_rotation | .rotation_count = $count | .last_access = $last_rotation' \
               "$access_file" > "${access_file}.tmp"
            mv "${access_file}.tmp" "$access_file"
        fi

        # Log rotation event
        if declare -f log_audit >/dev/null 2>&1 || [[ -f "${SCRIPT_DIR}/audit_secrets.sh" ]]; then
            bash "${SCRIPT_DIR}/audit_secrets.sh" access "$secret" "sm_rotate" "true" "rotation_id=$rotation_id" 2>/dev/null || true
        fi
    fi

    # Update rotation record
    local error_json="null"
    if [[ -n "$error_message" ]]; then
        error_json="\"$(json_escape "$error_message")\""
    fi

    jq --arg status "$status" \
       --arg completed "$completed_at" \
       --argjson error "$error_json" \
       '.status = $status | .completed_at = $completed | .error = $error' \
       "$rotation_file" > "${rotation_file}.tmp"
    mv "${rotation_file}.tmp" "$rotation_file"

    # Output result
    cat "$rotation_file"

    [[ -n "$span_id" ]] && declare -f trace_end >/dev/null 2>&1 && trace_end "$span_id" "$status"

    [[ "$status" == "failed" ]] && return 1
    return 0
}

# Mark a secret as rotated (manual tracking)
mark_rotated() {
    local secret="${1:-}"

    if [[ -z "$secret" ]]; then
        echo '{"error": "E101", "message": "mark_rotated requires secret name"}' >&2
        return 1
    fi

    local access_file="${ROTATION_STATE_DIR}/${secret}.json"
    local now
    now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    if [[ -f "$access_file" ]]; then
        jq --arg "$now" \
           '.last_rotation = $now | .rotation_count = (.rotation_count // 0) + 1 | .last_access = $now' \
           "$access_file" > "${access_file}.tmp"
        mv "${access_file}.tmp" "$access_file"
    else
        cat > "$access_file" <<EOF
{
  "secret": "$(json_escape "$secret")",
  "last_access": "$now",
  "last_rotation": "$now",
  "rotation_count": 1,
  "status": "active"
}
EOF
    fi

    echo '{"status": "marked", "secret": "'"$(json_escape "$secret")"'"}'
    return 0
}

# Get rotation history for a secret
get_rotation_history() {
    local secret="${1:-}"

    if [[ -z "$secret" ]]; then
        echo '{"error": "E101", "message": "get_rotation_history requires secret name"}' >&2
        return 1
    fi

    local access_file="${ROTATION_STATE_DIR}/${secret}.json"

    if [[ ! -f "$access_file" ]]; then
        echo '{"error": "E102", "message": "No rotation history found for secret"}'
        return 1
    fi

    cat "$access_file"
    return 0
}

# Emit warnings for secrets needing rotation
emit_rotation_warnings() {
    local threshold_days="${1:-$STALE_THRESHOLD_DAYS}"

    local status_output
    status_output=$(check_rotation_status "" "detailed" "$threshold_days")

    local rotation_needed
    rotation_needed=$(echo "$status_output" | jq -r '.secrets_needing_rotation')

    if [[ "$rotation_needed" -gt 0 ]]; then
        echo "[ROTATION WARNING] $rotation_needed secret(s) have not been accessed in $threshold_days days or more:" >&2
        echo "$status_output" | jq -r '.details[] | select(.status == "STALE") | "  - \(.secret) (\(.days) days since last access)"' >&2
    fi

    echo "$status_output"
    return 0
}

# Main dispatcher
case "${1:-}" in
    check)
        check_rotation_needed "${2:-}" "${3:-}"
        ;;
    status)
        check_rotation_status "${2:-}" "${3:-}" "${4:-}"
        ;;
    rotate)
        sm_rotate "${2:-}" "${3:-}"
        ;;
    mark)
        mark_rotated "${2:-}"
        ;;
    history)
        get_rotation_history "${2:-}"
        ;;
    warnings)
        emit_rotation_warnings "${2:-}"
        ;;
    record)
        record_access "${2:-}" "${3:-}"
        ;;
    *)
        cat <<EOF
Secret Rotation Manager

Usage: $0 <command> [arguments]

Commands:
  check <secret> [threshold_days]    Check if secret needs rotation
  status [manager] [format] [days]   Check rotation status for all secrets
  rotate <manager> <secret>          Trigger rotation for a secret
  mark <secret>                     Mark secret as manually rotated
  history <secret>                   Get rotation history for a secret
  warnings [threshold_days]          Emit warnings for stale secrets
  record <secret> [method]           Record secret access for tracking

Examples:
  $0 check DATABASE_URL 90
  $0 status doppler detailed 90
  $0 rotate doppler API_KEY
  $0 warnings 90

Configuration:
  STALE_THRESHOLD_DAYS=$STALE_THRESHOLD_DAYS
  ROTATION_WARNING_DAYS=$ROTATION_WARNING_DAYS
EOF
        ;;
esac
