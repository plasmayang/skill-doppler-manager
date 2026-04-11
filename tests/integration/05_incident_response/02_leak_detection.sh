#!/bin/bash

# Integration Test: Incident Response - Leak Detection Logging
# Verifies leak detection is logged properly

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
source "$SCRIPT_DIR/tests/integration/run_tests.sh" 2>/dev/null || true

echo "Testing incident response: leak detection logging..."

# Setup audit directory
export DOPPLER_AUDIT_DIR="$TEST_TMP_DIR/audit"
mkdir -p "$DOPPLER_AUDIT_DIR"

# Log a leak detection
if [[ -f "$SCRIPT_DIR/scripts/audit_secrets.sh" ]]; then
    bash "$SCRIPT_DIR/scripts/audit_secrets.sh" leak "PASTED_SECRET" "Integration test" "HIGH" 2>/dev/null || true

    # Check alert log
    if [[ -f "$DOPPLER_AUDIT_DIR/alerts.log" ]]; then
        if grep -q "LEAK_DETECTED" "$DOPPLER_AUDIT_DIR/alerts.log"; then
            if grep -q "HIGH" "$DOPPLER_AUDIT_DIR/alerts.log"; then
                echo "PASS: Leak detection was logged with correct severity"
                exit 0
            fi
        fi
        echo "FAIL: Leak detection not properly logged"
        exit 1
    else
        echo "FAIL: Alert log file not created"
        exit 1
    fi
else
    echo "SKIP: audit_secrets.sh not found"
    exit 0
fi
