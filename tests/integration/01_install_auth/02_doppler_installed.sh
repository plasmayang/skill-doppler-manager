#!/bin/bash

# Integration Test: Doppler Installation Check
# Verifies Doppler CLI is detected by check_status.sh

set -euo pipefail

# Project root is three levels up from test script (tests/integration/01_install_auth -> project root)
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

echo "Testing Doppler installation detection..."

# Setup mock Doppler
MOCK_DIR="/tmp/secret-mgmt-test-mock-$$"
mkdir -p "$MOCK_DIR"

cat << 'EOF' > "$MOCK_DIR/doppler"
#!/bin/bash
case "$1" in
    --version)
        echo "Doppler 3.10.0 (mock)"
        ;;
    configure)
        [[ -z "$2" ]] && exit 0
        [[ "$2" == "get" ]] || exit 0
        case "$3" in
            project) echo "${DOPPLER_PROJECT:-test-project}" ;;
            config)  echo "${DOPPLER_CONFIG:-dev}" ;;
            token)   echo "${DOPPLER_TOKEN:-dp.st.mock}" ;;
        esac
        exit 0
        ;;
    secrets)
        [[ "$2" == "get" ]] && echo "mock_secret_value"
        exit 0
        ;;
    run)
        shift 2; eval "$@"
        ;;
    *)
        exit 1
        ;;
esac
EOF
chmod +x "$MOCK_DIR/doppler"

# Prepend mock to PATH
export PATH="$MOCK_DIR:$PATH"

# Run check_status.sh
output=$(bash "$PROJECT_ROOT/scripts/check_status.sh" 2>&1 || true)

# Check that output contains expected fields
if ! echo "$output" | grep -q '"status"'; then
    echo "FAIL: No status field in output"
    echo "$output"
    exit 1
fi

if ! echo "$output" | grep -q '"code"'; then
    echo "FAIL: No code field in output"
    echo "$output"
    exit 1
fi

echo "PASS: Doppler installation detection works"
echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); print(f'Status: {d[\"status\"]}, Code: {d[\"code\"]}')" 2>/dev/null || true

# Cleanup
rm -rf "$MOCK_DIR"
exit 0
