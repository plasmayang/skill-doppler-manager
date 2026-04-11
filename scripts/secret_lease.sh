#!/bin/bash

# Doppler Manager - Secret Lease/TTL Management
# Implements token bucket rate limiting with lease semantics
# Falls back to sm_fetch if manager doesn't support leases

set -euo pipefail

# Source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/tracing.sh" 2>/dev/null || true
source "${SCRIPT_DIR}/error_codes.sh" 2>/dev/null || true

# Configuration
LEASE_CACHE_DIR="${HOME}/.cache/doppler-manager/leases"
mkdir -p "$LEASE_CACHE_DIR"

# Lease defaults
DEFAULT_LEASE_TTL=3600       # 1 hour in seconds
DEFAULT_RATE_CAPACITY=10     # max tokens in bucket
DEFAULT_REFILL_RATE=1        # tokens per second

# Token bucket storage
TOKEN_BUCKET_DIR="${HOME}/.cache/doppler-manager/token_buckets"
mkdir -p "$TOKEN_BUCKET_DIR"

# Generate unique lease ID
generate_lease_id() {
    if command -v uuidgen &> /dev/null; then
        uuidgen | tr '[:upper:]' '[:lower:]'
    else
        echo "lease-$(date +%s)-$$-$(head -c 8 /dev/urandom | xxd -p)"
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

# Token bucket operations
rate_limit_init() {
    local key="${1:-default}"
    local capacity="${2:-$DEFAULT_RATE_CAPACITY}"
    local refill_rate="${3:-$DEFAULT_REFILL_RATE}"

    local bucket_file="${TOKEN_BUCKET_DIR}/${key}.json"

    cat > "$bucket_file" <<EOF
{
  "key": "$(json_escape "$key")",
  "tokens": $capacity,
  "capacity": $capacity,
  "refill_rate": $refill_rate,
  "last_refill": $(date +%s)
}
EOF
}

rate_limit_check() {
    local key="${1:-default}"
    local bucket_file="${TOKEN_BUCKET_DIR}/${key}.json"

    if [[ ! -f "$bucket_file" ]]; then
        rate_limit_init "$key"
    fi

    local now
    now=$(date +%s)

    # Read and update bucket atomically
    local tokens capacity refill_rate last_refill
    tokens=$(jq -r '.tokens' "$bucket_file")
    capacity=$(jq -r '.capacity' "$bucket_file")
    refill_rate=$(jq -r '.refill_rate' "$bucket_file")
    last_refill=$(jq -r '.last_refill' "$bucket_file")

    # Calculate token refill
    local elapsed=$((now - last_refill))
    local refill=$((elapsed * refill_rate))
    tokens=$((tokens + refill))

    # Cap at capacity
    if [[ "$tokens" -gt "$capacity" ]]; then
        tokens=$capacity
    fi

    # Check if we have a token
    if [[ "$tokens" -ge 1 ]]; then
        tokens=$((tokens - 1))
        # Update bucket
        jq --argjson tokens "$tokens" --argjson now "$now" \
           '.tokens = $tokens | .last_refill = $now' "$bucket_file" > "${bucket_file}.tmp"
        mv "${bucket_file}.tmp" "$bucket_file"
        return 0
    else
        # Update last_refill to prevent repeated calculation
        jq --argjson now "$now" '.last_refill = $now' "$bucket_file" > "${bucket_file}.tmp"
        mv "${bucket_file}.tmp" "$bucket_file"
        return 1
    fi
}

rate_limit_reset() {
    local key="${1:-default}"
    local bucket_file="${TOKEN_BUCKET_DIR}/${key}.json"

    if [[ -f "$bucket_file" ]]; then
        rm "$bucket_file"
    fi
}

# Check if manager supports leases
manager_supports_leases() {
    local manager="${1:-doppler}"

    case "$manager" in
        doppler)
            # Doppler supports secrets with TTL via lease metadata
            return 0
            ;;
        vault)
            # Vault supports lease durations
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Acquire a lease on a secret
# Usage: sm_lease <manager> <secret> [ttl_seconds]
sm_lease() {
    local manager="${1:-}"
    local secret="${2:-}"
    local ttl="${3:-$DEFAULT_LEASE_TTL}"

    if [[ -z "$manager" ]] || [[ -z "$secret" ]]; then
        echo '{"error": "E101", "message": "sm_lease requires manager and secret arguments"}' >&2
        return 1
    fi

    # Start tracing span if available
    local span_id=""
    if declare -f trace_span >/dev/null 2>&1; then
        span_id=$(trace_span "sm_lease" "manager" "$manager" "secret" "$secret")
    fi

    # Rate limit check
    local rate_key="lease:${manager}:${secret}"
    if ! rate_limit_check "$rate_key"; then
        echo '{"error": "E006", "message": "Rate limit exceeded for lease acquisition"}' >&2
        [[ -n "$span_id" ]] && declare -f trace_end >/dev/null 2>&1 && trace_end "$span_id" "ERROR" "Rate limited"
        return 1
    fi

    local lease_id
    lease_id=$(generate_lease_id)

    local lease_file="${LEASE_CACHE_DIR}/${lease_id}.json"
    local acquired_at
    acquired_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local expires_at
    expires_at=$(date -u -d "+${ttl} seconds" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || \
                  date -u -v+"${ttl}"S +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || \
                  date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Create lease record
    cat > "$lease_file" <<EOF
{
  "lease_id": "$lease_id",
  "manager": "$(json_escape "$manager")",
  "secret": "$(json_escape "$secret")",
  "ttl": $ttl,
  "acquired_at": "$acquired_at",
  "expires_at": "$expires_at",
  "status": "active"
}
EOF

    # Log lease acquisition
    if declare -f log_audit >/dev/null 2>&1 || [[ -f "${SCRIPT_DIR}/audit_secrets.sh" ]]; then
        bash "${SCRIPT_DIR}/audit_secrets.sh" access "$secret" "sm_lease" "true" "lease_id=$lease_id" 2>/dev/null || true
    fi

    # Output lease info as JSON
    cat <<EOF
{
  "lease_id": "$lease_id",
  "secret": "$(json_escape "$secret")",
  "ttl": $ttl,
  "acquired_at": "$acquired_at",
  "expires_at": "$expires_at",
  "manager": "$(json_escape "$manager")"
}
EOF

    [[ -n "$span_id" ]] && declare -f trace_end >/dev/null 2>&1 && trace_end "$span_id" "OK"

    return 0
}

# Release a lease
sm_release_lease() {
    local lease_id="${1:-}"

    if [[ -z "$lease_id" ]]; then
        echo '{"error": "E101", "message": "sm_release_lease requires lease_id"}' >&2
        return 1
    fi

    local lease_file="${LEASE_CACHE_DIR}/${lease_id}.json"

    if [[ ! -f "$lease_file" ]]; then
        echo '{"error": "E102", "message": "Lease not found"}' >&2
        return 1
    fi

    # Mark as released
    local released_at
    released_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    jq --arg "$released_at" '.status = "released" | .released_at = $released_at' "$lease_file" > "${lease_file}.tmp"
    mv "${lease_file}.tmp" "$lease_file"

    echo '{"status": "released", "lease_id": "'"$lease_id"'"}'

    return 0
}

# Get secret with lease (falls back to sm_fetch)
sm_lease_get() {
    local manager="${1:-}"
    local secret="${2:-}"
    local ttl="${3:-$DEFAULT_LEASE_TTL}"

    if [[ -z "$manager" ]] || [[ -z "$secret" ]]; then
        echo '{"error": "E101", "message": "sm_lease_get requires manager and secret"}' >&2
        return 1
    fi

    # Acquire lease
    local lease_output
    lease_output=$(sm_lease "$manager" "$secret" "$ttl" 2>&1) || {
        echo "$lease_output" >&2
        return 1
    }

    # Check if manager supports direct lease retrieval
    if manager_supports_leases "$manager"; then
        # Fetch the actual secret value
        local secret_value
        case "$manager" in
            doppler)
                secret_value=$(doppler secrets get "$secret" --plain 2>/dev/null) || {
                    echo '{"error": "E102", "message": "Failed to fetch secret"}' >&2
                    return 1
                }
                ;;
            vault)
                secret_value=$(vault kv get -field=value "$secret" 2>/dev/null) || {
                    echo '{"error": "E102", "message": "Failed to fetch secret from Vault"}' >&2
                    return 1
                }
                ;;
        esac

        # Combine lease metadata with secret value
        jq -n \
            --argjson lease "$lease_output" \
            --arg value "$secret_value" \
            '$lease * {value: $value}'
    else
        # Fall back to sm_fetch pattern
        echo "$lease_output"
        echo '{"warning": "Manager does not support leases, secret value not included"}' >&2
    fi

    return 0
}

# List active leases
sm_list_leases() {
    local manager="${1:-}"
    local secret="${2:-}"

    local leases=()
    for lease_file in "${LEASE_CACHE_DIR}"/*.json; do
        [[ -f "$lease_file" ]] || continue

        local status
        status=$(jq -r '.status' "$lease_file" 2>/dev/null)

        if [[ "$status" == "active" ]]; then
            if [[ -n "$manager" ]]; then
                local file_manager
                file_manager=$(jq -r '.manager' "$lease_file" 2>/dev/null)
                [[ "$file_manager" != "$manager" ]] && continue
            fi
            if [[ -n "$secret" ]]; then
                local file_secret
                file_secret=$(jq -r '.secret' "$lease_file" 2>/dev/null)
                [[ "$file_secret" != "$secret" ]] && continue
            fi
            leases+=("$lease_file")
        fi
    done

    if [[ ${#leases[@]} -eq 0 ]]; then
        echo '{"leases": [], "count": 0}'
        return 0
    fi

    local json="{\"leases\":["
    local first=true
    for lease_file in "${leases[@]}"; do
        [[ -f "$lease_file" ]] || continue
        if [[ "$first" == "true" ]]; then
            first=false
        else
            json+=","
        fi
        json+=$(jq -c '.' "$lease_file")
    done
    json+="],\"count\":${#leases[@]}}"

    echo "$json"
    return 0
}

# Cleanup expired leases
sm_cleanup_leases() {
    local cleaned=0
    local now
    now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    for lease_file in "${LEASE_CACHE_DIR}"/*.json; do
        [[ -f "$lease_file" ]] || continue

        local status
        status=$(jq -r '.status' "$lease_file" 2>/dev/null)
        local expires_at
        expires_at=$(jq -r '.expires_at' "$lease_file" 2>/dev/null)

        if [[ "$status" == "active" ]] && [[ "$expires_at" < "$now" ]]; then
            jq '.status = "expired"' "$lease_file" > "${lease_file}.tmp"
            mv "${lease_file}.tmp" "$lease_file"
            cleaned=$((cleaned + 1))
        fi
    done

    echo "{\"cleaned\": $cleaned}"
    return 0
}

# Main dispatcher
case "${1:-}" in
    lease)
        sm_lease "${2:-}" "${3:-}" "${4:-}"
        ;;
    release)
        sm_release_lease "${2:-}"
        ;;
    get)
        sm_lease_get "${2:-}" "${3:-}" "${4:-}"
        ;;
    list)
        sm_list_leases "${2:-}" "${3:-}"
        ;;
    cleanup)
        sm_cleanup_leases
        ;;
    rate_init)
        rate_limit_init "${2:-default}" "${3:-}" "${4:-}"
        ;;
    rate_check)
        rate_limit_check "${2:-default}"
        ;;
    rate_reset)
        rate_limit_reset "${2:-default}"
        ;;
    *)
        cat <<EOF
Secret Lease Manager

Usage: $0 <command> [arguments]

Commands:
  lease <manager> <secret> [ttl]     Acquire a lease on a secret
  release <lease_id>                  Release a lease
  get <manager> <secret> [ttl]        Get secret with lease metadata
  list [manager] [secret]             List active leases
  cleanup                             Clean up expired leases
  rate_init <key> [capacity] [rate]   Initialize rate limit bucket
  rate_check <key>                    Check rate limit (0=allowed, 1=limited)
  rate_reset <key>                    Reset rate limit bucket

Examples:
  $0 lease doppler DATABASE_URL 3600
  $0 get doppler API_KEY 1800
  $0 list doppler
  $0 rate_init api_calls 100 10

Error Codes:
  E101 - Missing required arguments
  E102 - Manager-specific error
  E006 - Rate limit exceeded
EOF
        ;;
esac
