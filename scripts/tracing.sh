#!/bin/bash

# Doppler Manager - OpenTelemetry Tracing Wrapper
# Provides distributed tracing for bash script operations
# Falls back gracefully when OTEL_ENDPOINT is not configured

set -euo pipefail

# Tracing configuration
: "${OTEL_ENDPOINT:=""}"
: "${OTEL_SERVICE_NAME:=doppler-manager}"
: "${OTEL_TRACES_SAMPLE_RATE:=1.0}"
: "${TRACING_ENABLED:=false}"

# Trace storage (in-memory for current session)
declare -a TRACES=()
declare -a SPANS=()
declare -a SPAN_STACK=()

# Generate a simple trace ID (128-bit hex)
generate_trace_id() {
    if command -v uuidgen &> /dev/null; then
        uuidgen | tr -d '-' | head -c 32
    else
        # Fallback: use openssl or /dev/urandom
        if command -v openssl &> /dev/null; then
            openssl rand -hex 16
        else
            head -c 16 /dev/urandom | xxd -p | tr -d '\n'
        fi
    fi
}

# Generate a simple span ID (64-bit hex)
generate_span_id() {
    if command -v openssl &> /dev/null; then
        openssl rand -hex 8
    else
        head -c 8 /dev/urandom | xxd -p | tr -d '\n'
    fi
}

# Get current timestamp in ISO 8601 format with nanoseconds
timestamp_iso() {
    date -u +"%Y-%m-%dT%H:%M:%S.%NZ"
}

# Get current timestamp as epoch nanoseconds
timestamp_epoch_ns() {
    if command -v date &> /dev/null; then
        # Try to get nanoseconds
        if date +%s%N &> /dev/null; then
            date +%s%N
        else
            # Fallback to seconds * 1000000000
            echo "$(($(date +%s) * 1000000000))"
        fi
    else
        echo "0"
    fi
}

# Initialize tracing session
trace_init() {
    if [[ -n "$OTEL_ENDPOINT" ]]; then
        TRACING_ENABLED="true"
        SESSION_TRACE_ID=$(generate_trace_id)
        SESSION_START_TIME=$(timestamp_epoch_ns)
        trace_info "Tracing initialized with endpoint: $OTEL_ENDPOINT"
        trace_info "Session trace ID: $SESSION_TRACE_ID"
    else
        trace_debug "OTEL_ENDPOINT not set, tracing disabled (fallback mode)"
    fi
}

# Check if tracing is enabled
trace_is_enabled() {
    [[ "$TRACING_ENABLED" == "true" ]] && [[ -n "$OTEL_ENDPOINT" ]]
}

# Log debug message (only when DEBUG=true)
trace_debug() {
    if [[ "${DEBUG:-false}" == "true" ]]; then
        echo "[TRACE DEBUG] $1" >&2
    fi
}

# Log info message
trace_info() {
    echo "[TRACE INFO] $1" >&2
}

# Log warning message
trace_warn() {
    echo "[TRACE WARN] $1" >&2
}

# Log error message
trace_error() {
    echo "[TRACE ERROR] $1" >&2
}

# Create a new span
# Usage: trace_span "operation_name" [attributes...]
# Returns: span_id in SPAN_ID variable
trace_span() {
    local operation_name="${1:-}"
    shift
    local attributes=("$@")

    local span_id
    span_id=$(generate_span_id)
    local parent_span_id="${CURRENT_SPAN_ID:-}"

    local span_json
    span_json=$(cat <<EOF
{
  "trace_id": "${SESSION_TRACE_ID:-}",
  "span_id": "${span_id}",
  "parent_span_id": "${parent_span_id:-}",
  "operation_name": "${operation_name}",
  "start_time": "$(timestamp_epoch_ns)",
  "service_name": "${OTEL_SERVICE_NAME}",
  "attributes": {}
}
EOF
)

    # Store span
    SPANS+=("$span_json")
    SPAN_STACK+=("$span_id")
    export CURRENT_SPAN_ID="$span_id"

    trace_debug "Span started: $operation_name (span_id: $span_id)"

    # Return span ID
    echo "$span_id"
}

# End a span
# Usage: trace_end "span_id" [status] [error_message]
trace_end() {
    local span_id="${1:-}"
    local status="${2:-OK}"
    local error_message="${3:-}"

    local end_time
    end_time=$(timestamp_epoch_ns)

    # Find and update the span
    local updated_spans=()
    local found=false

    for span in "${SPANS[@]}"; do
        if [[ "$span" == *"\"span_id\": \"$span_id\""* ]]; then
            # Update end_time and status
            span=$(echo "$span" | python3 -c "
import json, sys
data = json.load(sys.stdin)
data['end_time'] = '$end_time'
data['status'] = '$status'
if '$error_message':
    data['error_message'] = '$error_message'
print(json.dumps(data))
" 2>/dev/null || echo "$span")
            found=true
            trace_debug "Span ended: $span_id (status: $status)"
        fi
        updated_spans+=("$span")
    done

    if [[ "$found" == "true" ]]; then
        SPANS=("${updated_spans[@]}")
    fi

    # Pop from stack
    local new_stack=()
    local found_in_stack=false
    for sid in "${SPAN_STACK[@]}"; do
        if [[ "$found_in_stack" == "true" ]]; then
            new_stack+=("$sid")
        elif [[ "$sid" == "$span_id" ]]; then
            found_in_stack=true
        else
            new_stack+=("$sid")
        fi
    done
    SPAN_STACK=("${new_stack[@]}")

    # Set CURRENT_SPAN_ID to parent
    if [[ ${#SPAN_STACK[@]} -gt 0 ]]; then
        CURRENT_SPAN_ID="${SPAN_STACK[-1]}"
    else
        unset CURRENT_SPAN_ID
    fi
}

# Add attribute to current span
trace_attr() {
    local key="${1:-}"
    local value="${2:-}"

    if [[ -z "${CURRENT_SPAN_ID:-}" ]]; then
        trace_debug "trace_attr called but no active span"
        return
    fi

    # Update the current span with the attribute
    local updated_spans=()
    for span in "${SPANS[@]}"; do
        if [[ "$span" == *"\"span_id\": \"$CURRENT_SPAN_ID\""* ]]; then
            span=$(echo "$span" | python3 -c "
import json, sys
data = json.load(sys.stdin)
data['attributes']['$key'] = '$value'
print(json.dumps(data))
" 2>/dev/null || echo "$span")
        fi
        updated_spans+=("$span")
    done
    SPANS=("${updated_spans[@]}")
}

# Record an event within a span
trace_event() {
    local event_name="${1:-}"
    local span_id="${CURRENT_SPAN_ID:-}"

    if [[ -z "$span_id" ]]; then
        trace_debug "trace_event called but no active span"
        return
    fi

    trace_debug "Event recorded: $event_name (span: $span_id)"
}

# Export traces to OTLP endpoint
trace_export() {
    if ! trace_is_enabled; then
        trace_debug "Tracing not enabled, skipping export"
        return
    fi

    local payload
    payload=$(printf '%s\n' "${SPANS[@]}" | python3 -c "
import json, sys
spans = [json.loads(line) for line in sys.stdin if line.strip()]
print(json.dumps({
    'resourceSpans': [{
        'resource': {
            'attributes': [
                {'key': 'service.name', 'value': {'stringValue': '${OTEL_SERVICE_NAME}'}},
                {'key': 'service.version', 'value': {'stringValue': '1.0.0'}}
            ]
        },
        'scopeSpans': [{
            'spans': spans
        }]
    }]
}, indent=2))
" 2>/dev/null)

    if [[ -z "$payload" ]]; then
        trace_error "Failed to generate trace payload"
        return
    fi

    trace_debug "Exporting ${#SPANS[@]} spans to $OTEL_ENDPOINT"

    local response
    response=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -H "user-agent: doppler-manager-tracing/1.0" \
        -d "$payload" \
        "$OTEL_ENDPOINT/v1/traces" 2>&1) || {
        trace_warn "Failed to export traces: $response"
        return
    }

    trace_info "Traces exported successfully"
}

# Cleanup traces (called at script end)
trace_cleanup() {
    if [[ ${#SPANS[@]} -gt 0 ]]; then
        trace_export
    fi
    SPANS=()
    SPAN_STACK=()
    unset SESSION_TRACE_ID
    unset CURRENT_SPAN_ID
}

# Wrapper for doppler commands with tracing
trace_doppler() {
    local span_id
    span_id=$(trace_span "doppler.${1:-run}" "command" "${*:-}")

    local result
    local exit_code=0

    result=$(doppler "$@" 2>&1) || exit_code=$?

    if [[ "$exit_code" -eq 0 ]]; then
        trace_end "$span_id" "OK"
    else
        trace_end "$span_id" "ERROR" "$result"
    fi

    echo "$result"
    return "$exit_code"
}

# Wrapper for secret operations with tracing
trace_secret_access() {
    local operation="${1:-}"
    local secret_name="${2:-}"

    local span_id
    span_id=$(trace_span "secret.$operation" "secret_name" "$secret_name")

    trace_end "$span_id" "OK"
}

# Add trap to cleanup traces on exit
trap trace_cleanup EXIT

# Initialize tracing on source
trace_init
