#!/bin/bash

# Integration Test: Authentication Status Check
# Verifies check_status.sh correctly reports authentication state

set -euo pipefail

# Project root is three levels up from test script
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

echo "Testing authentication status check..."

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

output=$(bash "$PROJECT_ROOT/scripts/check_status.sh" 2>&1 || true)

# Parse JSON output
status=$(echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('status',''))" 2>/dev/null || echo "")

if [[ "$status" == "OK" ]] || [[ "$status" == "WARNING" ]]; then
    echo "PASS: Authentication status is valid: $status"
    rm -rf "$MOCK_DIR"
    exit 0
else
    echo "FAIL: Unexpected status: $status"
    echo "$output"
    rm -rf "$MOCK_DIR"
    exit 1
fi
