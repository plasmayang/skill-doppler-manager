#!/bin/bash

# Doppler Manager - Token Bucket Rate Limiting
# Provides distributed rate limiting for secret operations

set -euo pipefail

# Source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/tracing.sh" 2>/dev/null || true

# Configuration
RATE_LIMIT_DIR="${HOME}/.cache/doppler-manager/rate_limits"
mkdir -p "$RATE_LIMIT_DIR"

# Defaults
DEFAULT_CAPACITY=10
DEFAULT_REFILL_RATE=1

# JSON escape helper
json_escape() {
    local str="$1"
    str="${str//\\/\\\\}"
    str="${str//\"/\\\"}"
    str="${str//$'\n'/\\n}"
    str="${str//$'\t'/\\t}"
    printf '%s' "$str"
}

# Get current epoch seconds
get_epoch() {
    date +%s
}

# Initialize a token bucket
# Usage: rate_limit_init <key> <capacity> <refill_rate>
rate_limit_init() {
    local key="${1:-default}"
    local capacity="${2:-$DEFAULT_CAPACITY}"
    local refill_rate="${3:-$DEFAULT_REFILL_RATE}"

    if [[ -z "$key" ]]; then
        echo '{"error": "E101", "message": "rate_limit_init requires key argument"}' >&2
        return 1
    fi

    # Validate numeric arguments
    if ! [[ "$capacity" =~ ^[0-9]+$ ]] || [[ "$capacity" -lt 1 ]]; then
        echo '{"error": "E101", "message": "capacity must be a positive integer"}' >&2
        return 1
    fi

    if ! [[ "$refill_rate" =~ ^[0-9]+$ ]] || [[ "$refill_rate" -lt 0 ]]; then
        echo '{"error": "E101", "message": "refill_rate must be a non-negative integer"}' >&2
        return 1
    fi

    local bucket_file="${RATE_LIMIT_DIR}/${key}.json"
    local now
    now=$(get_epoch)

    cat > "$bucket_file" <<EOF
{
  "key": "$(json_escape "$key")",
  "tokens": $capacity,
  "capacity": $capacity,
  "refill_rate": $refill_rate,
  "last_refill": $now
}
EOF

    cat <<EOF
{
  "status": "initialized",
  "key": "$(json_escape "$key")",
  "capacity": $capacity,
  "refill_rate": $refill_rate,
  "tokens": $capacity
}
EOF

    return 0
}

# Check if request is allowed under rate limit
# Usage: rate_limit_check <key>
# Returns: 0 if allowed, 1 if rate limited
rate_limit_check() {
    local key="${1:-default}"

    if [[ -z "$key" ]]; then
        echo '{"error": "E101", "message": "rate_limit_check requires key argument"}' >&2
        return 1
    fi

    # Start tracing span if available
    local span_id=""
    if declare -f trace_span >/dev/null 2>&1; then
        span_id=$(trace_span "rate_limit_check" "key" "$key")
    fi

    local bucket_file="${RATE_LIMIT_DIR}/${key}.json"

    # Initialize bucket if it doesn't exist
    if [[ ! -f "$bucket_file" ]]; then
        rate_limit_init "$key" >/dev/null 2>&1
    fi

    local now
    now=$(get_epoch)

    # Read bucket state
    local tokens capacity refill_rate last_refill
    tokens=$(jq -r '.tokens' "$bucket_file")
    capacity=$(jq -r '.capacity' "$bucket_file")
    refill_rate=$(jq -r '.refill_rate' "$bucket_file")
    last_refill=$(jq -r '.last_refill' "$bucket_file")

    # Calculate token refill based on time elapsed
    local elapsed=$((now - last_refill))
    local refill=0

    if [[ "$refill_rate" -gt 0 ]] && [[ "$elapsed" -gt 0 ]]; then
        # Refill tokens: refill_rate tokens per second
        refill=$((elapsed * refill_rate))
    fi

    # Add refill to current tokens, capped at capacity
    tokens=$((tokens + refill))
    if [[ "$tokens" -gt "$capacity" ]]; then
        tokens=$capacity
    fi

    # Check if we have at least 1 token
    if [[ "$tokens" -ge 1 ]]; then
        # Consume one token
        tokens=$((tokens - 1))

        # Update bucket atomically
        jq --argjson tokens "$tokens" --argjson now "$now" \
           '.tokens = $tokens | .last_refill = $now' \
           "$bucket_file" > "${bucket_file}.tmp"
        mv "${bucket_file}.tmp" "$bucket_file"

        # Output success
        cat <<EOF
{
  "allowed": true,
  "key": "$(json_escape "$key")",
  "tokens_remaining": $tokens,
  "capacity": $capacity,
  "refill_rate": $refill_rate
}
EOF

        [[ -n "$span_id" ]] && declare -f trace_end >/dev/null 2>&1 && trace_end "$span_id" "OK"
        return 0
    else
        # No tokens available, don't consume
        # Just update last_refill to prevent repeated calculation
        jq --argjson now "$now" '.last_refill = $now' \
           "$bucket_file" > "${bucket_file}.tmp"
        mv "${bucket_file}.tmp" "$bucket_file"

        # Calculate retry-after
        local retry_after=1
        if [[ "$refill_rate" -gt 0 ]]; then
            retry_after=$((1))
        fi

        # Output rate limited
        cat <<EOF
{
  "allowed": false,
  "key": "$(json_escape "$key")",
  "tokens_remaining": 0,
  "capacity": $capacity,
  "refill_rate": $refill_rate,
  "retry_after_seconds": $retry_after
}
EOF

        [[ -n "$span_id" ]] && declare -f trace_end >/dev/null 2>&1 && trace_end "$span_id" "LIMITED"
        return 1
    fi
}

# Reset a rate limit bucket
# Usage: rate_limit_reset <key>
rate_limit_reset() {
    local key="${1:-}"

    if [[ -z "$key" ]]; then
        echo '{"error": "E101", "message": "rate_limit_reset requires key argument"}' >&2
        return 1
    fi

    local bucket_file="${RATE_LIMIT_DIR}/${key}.json"

    if [[ ! -f "$bucket_file" ]]; then
        echo '{"error": "E102", "message": "Bucket not found: '"$key"'"}' >&2
        return 1
    fi

    # Re-initialize with same parameters
    local capacity refill_rate
    capacity=$(jq -r '.capacity' "$bucket_file")
    refill_rate=$(jq -r '.refill_rate' "$bucket_file")

    rm "$bucket_file"
    rate_limit_init "$key" "$capacity" "$refill_rate"

    return 0
}

# Get bucket status without consuming tokens
# Usage: rate_limit_status <key>
rate_limit_status() {
    local key="${1:-}"

    if [[ -z "$key" ]]; then
        echo '{"error": "E101", "message": "rate_limit_status requires key argument"}' >&2
        return 1
    fi

    local bucket_file="${RATE_LIMIT_DIR}/${key}.json"

    if [[ ! -f "$bucket_file" ]]; then
        echo '{"error": "E102", "message": "Bucket not found: '"$key"'"}' >&2
        return 1
    fi

    # Calculate current tokens with refill
    local now
    now=$(get_epoch)

    local tokens capacity refill_rate last_refill
    tokens=$(jq -r '.tokens' "$bucket_file")
    capacity=$(jq -r '.capacity' "$bucket_file")
    refill_rate=$(jq -r '.refill_rate' "$bucket_file")
    last_refill=$(jq -r '.last_refill' "$bucket_file")

    local elapsed=$((now - last_refill))
    local refill=0

    if [[ "$refill_rate" -gt 0 ]] && [[ "$elapsed" -gt 0 ]]; then
        refill=$((elapsed * refill_rate))
    fi

    tokens=$((tokens + refill))
    if [[ "$tokens" -gt "$capacity" ]]; then
        tokens=$capacity
    fi

    cat <<EOF
{
  "key": "$(json_escape "$key")",
  "tokens": $tokens,
  "capacity": $capacity,
  "refill_rate": $refill_rate,
  "last_refill": $last_refill,
  "seconds_until_full": $([[ "$refill_rate" -gt 0 ]] && echo "$(( (capacity - tokens) / refill_rate ))" || echo "null")
}
EOF

    return 0
}

# List all rate limit buckets
rate_limit_list() {
    local buckets=()

    for bucket_file in "${RATE_LIMIT_DIR}"/*.json; do
        [[ -f "$bucket_file" ]] || continue
        buckets+=("$(basename "$bucket_file" .json)")
    done

    if [[ ${#buckets[@]} -eq 0 ]]; then
        echo '{"buckets": [], "count": 0}'
        return 0
    fi

    local json="{\"buckets\":["
    local first=true
    for bucket in "${buckets[@]}"; do
        if [[ "$first" == "true" ]]; then
            first=false
        else
            json+=","
        fi
        json+="\"$(json_escape "$bucket")\""
    done
    json+="],\"count\":${#buckets[@]}}"

    echo "$json"
    return 0
}

# Delete a rate limit bucket
# Usage: rate_limit_delete <key>
rate_limit_delete() {
    local key="${1:-}"

    if [[ -z "$key" ]]; then
        echo '{"error": "E101", "message": "rate_limit_delete requires key argument"}' >&2
        return 1
    fi

    local bucket_file="${RATE_LIMIT_DIR}/${key}.json"

    if [[ ! -f "$bucket_file" ]]; then
        echo '{"error": "E102", "message": "Bucket not found: '"$key"'"}' >&2
        return 1
    fi

    rm "$bucket_file"

    echo '{"status": "deleted", "key": "'"$(json_escape "$key")"'"}'
    return 0
}

# Main dispatcher
case "${1:-}" in
    init)
        rate_limit_init "${2:-}" "${3:-}" "${4:-}"
        ;;
    check)
        rate_limit_check "${2:-}"
        ;;
    reset)
        rate_limit_reset "${2:-}"
        ;;
    status)
        rate_limit_status "${2:-}"
        ;;
    list)
        rate_limit_list
        ;;
    delete)
        rate_limit_delete "${2:-}"
        ;;
    *)
        cat <<EOF
Token Bucket Rate Limiter

Usage: $0 <command> [arguments]

Commands:
  init <key> [capacity] [refill_rate]  Initialize a rate limit bucket
  check <key>                           Check and consume token (0=allowed, 1=limited)
  reset <key>                          Reset bucket to full capacity
  status <key>                          Get bucket status without consuming
  list                                  List all buckets
  delete <key>                          Delete a bucket

Examples:
  $0 init api_calls 100 10    # 100 tokens, refill 10/second
  $0 check api_calls          # returns 0 if allowed, 1 if limited
  $0 status api_calls         # view current tokens

Storage:
  $RATE_LIMIT_DIR

Configuration:
  Default capacity: $DEFAULT_CAPACITY
  Default refill rate: $DEFAULT_REFILL_RATE

Error Codes:
  E101 - Missing or invalid arguments
  E102 - Bucket not found
EOF
        ;;
esac
