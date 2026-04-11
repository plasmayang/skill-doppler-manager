#!/bin/bash

# Integration Test: Incident Response - Emergency Seal
# Verifies emergency seal protocol runs correctly

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
source "$SCRIPT_DIR/tests/integration/run_tests.sh" 2>/dev/null || true

echo "Testing incident response: emergency seal..."

# Setup incident directory
export DOPPLER_AUDIT_DIR="$TEST_TMP_DIR/audit"
mkdir -p "$DOPPLER_AUDIT_DIR"

# Run emergency seal
if [[ -f "$SCRIPT_DIR/scripts/emergency_seal.sh" ]]; then
    output=$(bash "$SCRIPT_DIR/scripts/emergency_seal.sh" 2>&1 || true)

    # Check for incident ID
    if ! echo "$output" | grep -q "INC-"; then
        echo "FAIL: No incident ID generated"
        exit 1
    fi

    # Check for report generation
    if ! echo "$output" | grep -q "report.md"; then
        echo "FAIL: No incident report generated"
        exit 1
    fi

    echo "PASS: Emergency seal protocol executed"
    echo "$output" | head -10
    exit 0
else
    echo "SKIP: emergency_seal.sh not found"
    exit 0
fi
