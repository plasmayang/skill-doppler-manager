#!/bin/bash

# Integration Test: Zero-Leak - No Secrets in Shell History
# Verifies shell history doesn't contain secrets

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
source "$SCRIPT_DIR/tests/integration/run_tests.sh" 2>/dev/null || true

echo "Testing zero-leak: secrets not in shell history..."

create_mock_doppler

# Run a doppler command
doppler run -- echo "test" > /dev/null 2>&1 || true

# Check if the command was recorded in history (it shouldn't be with proper isolation)
# Since we're running in a mock environment, we just verify the mechanism exists

# The actual test would check ~/.bash_history or ~/.zsh_history
HISTORY_FILES=("$HOME/.bash_history" "$HOME/.zsh_history")
leaked=false

for hist_file in "${HISTORY_FILES[@]}"; do
    if [[ -f "$hist_file" ]] && [[ -s "$hist_file" ]]; then
        # Check for secret patterns in history
        if grep -lE "(API_KEY|SECRET|PASSWORD|TOKEN).*=" "$hist_file" 2>/dev/null; then
            leaked=true
            echo "FAIL: Potential secrets found in $hist_file"
        fi
    fi
done

if [[ "$leaked" == "true" ]]; then
    exit 1
fi

echo "PASS: No secrets in shell history"
exit 0
