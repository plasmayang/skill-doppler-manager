#!/bin/bash

# Integration Test: Incident Response - Emergency Seal
# Verifies emergency seal protocol runs correctly

set -euo pipefail

# Project root is three levels up from test script
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
TEST_TMP_DIR="${TEST_TMP_DIR:-/tmp/secret-mgmt-integration-test}"
export DOPPLER_AUDIT_DIR="$TEST_TMP_DIR/audit"
mkdir -p "$DOPPLER_AUDIT_DIR"

echo "Testing incident response: emergency seal..."

# Run emergency seal
if [[ -f "$PROJECT_ROOT/scripts/emergency_seal.sh" ]]; then
    output=$(bash "$PROJECT_ROOT/scripts/emergency_seal.sh" 2>&1 || true)

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
