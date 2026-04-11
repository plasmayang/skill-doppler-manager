#!/bin/bash

# Integration Test: HITL - Audit Logging on Secret Access
# Verifies secret access is properly logged

set -euo pipefail

# Project root is three levels up from test script
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
TEST_TMP_DIR="${TEST_TMP_DIR:-/tmp/secret-mgmt-integration-test}"
export DOPPLER_AUDIT_DIR="$TEST_TMP_DIR/audit"
mkdir -p "$DOPPLER_AUDIT_DIR"

echo "Testing HITL: audit logging..."

# Setup mock Doppler
MOCK_DIR="/tmp/secret-mgmt-test-mock-$$"
mkdir -p "$MOCK_DIR"

cat << 'EOF' > "$MOCK_DIR/doppler"
#!/bin/bash
case "$1" in
    --version) echo "Doppler 3.10.0 (mock)" ;;
    configure) [[ -z "$2" ]] && exit 0; [[ "$2" == "get" ]] || exit 0
        case "$3" in project) echo "test-project" ;; config) echo "dev" ;; token) echo "dp.st.mock" ;; esac; exit 0 ;;
    secrets) [[ "$2" == "get" ]] && echo "mock_secret_value"; exit 0 ;;
    run) shift 2; eval "$@" ;;
    *) exit 1 ;;
esac
EOF
chmod +x "$MOCK_DIR/doppler"
export PATH="$MOCK_DIR:$PATH"

# Log an access
if [[ -f "$PROJECT_ROOT/scripts/audit_secrets.sh" ]]; then
    bash "$PROJECT_ROOT/scripts/audit_secrets.sh" access "TEST_SECRET" "integration_test" "true" 2>/dev/null || true

    # Check audit log
    if [[ -f "$DOPPLER_AUDIT_DIR/audit.log" ]]; then
        if grep -q "TEST_SECRET" "$DOPPLER_AUDIT_DIR/audit.log"; then
            echo "PASS: Secret access was logged"
            rm -rf "$MOCK_DIR"
            exit 0
        else
            echo "FAIL: Secret access not found in audit log"
            rm -rf "$MOCK_DIR"
            exit 1
        fi
    else
        echo "FAIL: Audit log file not created"
        rm -rf "$MOCK_DIR"
        exit 1
    fi
else
    echo "SKIP: audit_secrets.sh not found"
    rm -rf "$MOCK_DIR"
    exit 0
fi
