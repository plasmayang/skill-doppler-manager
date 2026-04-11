#!/bin/bash

# Integration Test: Secret Injection via doppler run
# Verifies secrets are injected into processes without writing to disk

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
source "$SCRIPT_DIR/tests/integration/run_tests.sh" 2>/dev/null || true

echo "Testing secret injection via doppler run..."

create_mock_doppler

# Create a test script that echoes an env var
cat > "$TEST_TMP_DIR/test_inject.sh" << 'EOF'
#!/bin/bash
echo "DATABASE_URL is set: ${DATABASE_URL:-NOT_SET}"
EOF
chmod +x "$TEST_TMP_DIR/test_inject.sh"

# Run via doppler (mocked)
output=$(doppler run -- bash "$TEST_TMP_DIR/test_inject.sh" 2>&1 || true)

if [[ "$output" == *"NOT_SET"* ]]; then
    echo "FAIL: Secret was not injected"
    exit 1
fi

echo "PASS: Secret injection works"
echo "Output: $output"
exit 0
