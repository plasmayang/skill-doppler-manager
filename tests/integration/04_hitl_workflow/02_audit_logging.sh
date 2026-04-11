#!/bin/bash

# Integration Test: HITL - Audit Logging on Secret Access
# Verifies secret access is properly logged

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
source "$SCRIPT_DIR/tests/integration/run_tests.sh" 2>/dev/null || true

echo "Testing HITL: audit logging..."

create_mock_doppler

# Initialize audit
export DOPPLER_AUDIT_DIR="$TEST_TMP_DIR/audit"
mkdir -p "$DOPPLER_AUDIT_DIR"

# Log an access
if [[ -f "$SCRIPT_DIR/scripts/audit_secrets.sh" ]]; then
    bash "$SCRIPT_DIR/scripts/audit_secrets.sh" access "TEST_SECRET" "integration_test" "true" 2>/dev/null || true

    # Check audit log
    if [[ -f "$DOPPLER_AUDIT_DIR/audit.log" ]]; then
        if grep -q "TEST_SECRET" "$DOPPLER_AUDIT_DIR/audit.log"; then
            echo "PASS: Secret access was logged"
            exit 0
        else
            echo "FAIL: Secret access not found in audit log"
            exit 1
        fi
    else
        echo "FAIL: Audit log file not created"
        exit 1
    fi
else
    echo "SKIP: audit_secrets.sh not found"
    exit 0
fi
