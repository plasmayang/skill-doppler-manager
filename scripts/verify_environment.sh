#!/bin/bash

# Doppler Manager - Deep Environment Verification
# Performs comprehensive validation of the secret management environment

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Output functions
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[PASS]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[FAIL]${NC} $1"; }

# Track overall status
ISSUES_FOUND=0

echo "=============================================="
echo "  Doppler Environment Deep Verification"
echo "=============================================="
echo ""

# 1. Check Doppler CLI installation
info "Checking Doppler CLI installation..."
if ! command -v doppler &> /dev/null; then
    error "Doppler CLI not found in PATH"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
    echo ""
    echo "=============================================="
    echo "  Verification Summary"
    echo "=============================================="
    error "Found $ISSUES_FOUND issue(s) that should be addressed"
    echo ""
    echo "Run 'scripts/check_status.sh' for structured error codes."
    echo "Refer to 'references/SOP.md' for resolution steps."
    exit 1
fi
DOPPLER_VERSION=$(doppler --version 2>/dev/null | head -1 || echo "unknown")
success "Doppler CLI installed: $DOPPLER_VERSION"
echo ""

# 2. Check authentication status
info "Checking authentication status..."
set +e  # Temporarily disable set -e to capture exit code
AUTH_STATUS=$(doppler configure 2>&1)
AUTH_EXIT=$?
set -e  # Re-enable set -e

if [[ $AUTH_EXIT -eq 0 ]]; then
    success "Authenticated with Doppler"

    # Determine token type
    TOKEN=$(doppler configure get token --plain 2>/dev/null || echo "")
    if echo "$TOKEN" | grep -q "^dp\.st\."; then
        info "Token type: Service Token (recommended for CI/CD)"
    elif echo "$TOKEN" | grep -q "^dp\.pt\."; then
        warn "Token type: Personal Token (may expire - consider Service Token for automation)"
    elif [[ -n "$TOKEN" ]]; then
        info "Token type: $TOKEN"
    fi
else
    error "Not authenticated: $AUTH_STATUS"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
fi
echo ""

# 3. Check project and config
info "Checking project configuration..."
PROJECT=$(doppler configure get project --plain 2>/dev/null || echo "")
CONFIG=$(doppler configure get config --plain 2>/dev/null || echo "")

if [[ -z "$PROJECT" ]] || [[ -z "$CONFIG" ]]; then
    warn "No project/config set for current directory"
    warn "Run 'doppler setup' to configure"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
else
    success "Project: $PROJECT"
    success "Config: $CONFIG"

    # Validate they look like proper values
    if echo "$PROJECT" | grep -qiE "^(error|null|none|undefined)$"; then
        error "Project name appears invalid"
        ISSUES_FOUND=$((ISSUES_FOUND + 1))
    fi
fi
echo ""

# 4. Check for legacy .env files (potential secret contamination)
info "Checking for legacy .env files (security risk)..."
ENV_FILES=$(find . -maxdepth 3 -name ".env" -type f 2>/dev/null | grep -v node_modules || true)
if [[ -n "$ENV_FILES" ]]; then
    warn "Found .env files that may contain secrets:"
    echo "$ENV_FILES" | while read -r f; do
        echo "  - $f"
    done
    warn "Consider removing these and using Doppler exclusively"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
else
    success "No .env files found in project"
fi
echo ""

# 5. Check shell history for potential secrets
info "Checking shell history for secret patterns..."
HISTORY_FILES=(
    "$HOME/.bash_history"
    "$HOME/.zsh_history"
    "$HOME/.history"
)

SECRETS_FOUND=0
for hist_file in "${HISTORY_FILES[@]}"; do
    if [[ -f "$hist_file" ]]; then
        # Look for common secret patterns
        if grep -lE "(API_KEY|SECRET|PASSWORD|TOKEN).*=" "$hist_file" 2>/dev/null; then
            warn "Potential secrets found in $hist_file"
            SECRETS_FOUND=$((SECRETS_FOUND + 1))
        fi
    fi
done

if [[ $SECRETS_FOUND -eq 0 ]]; then
    success "No obvious secrets in shell history"
else
    warn "Recommend running: history -c (after backing up if needed)"
fi
echo ""

# 6. Check Doppler workspace access
info "Checking workspace and project access..."
if [[ -n "$PROJECT" ]] && [[ -n "$CONFIG" ]]; then
    SECRETS_COUNT=$(doppler secrets --quiet 2>/dev/null | wc -l || echo "0")
    if [[ "$SECRETS_COUNT" -gt 0 ]]; then
        success "Can access secrets ($SECRETS_COUNT secrets in config)"
    else
        warn "Could not enumerate secrets or config is empty"
    fi
fi
echo ""

# 7. Check network connectivity
info "Checking Doppler API connectivity..."
if curl -s --max-time 5 "https://api.doppler.com/v3/health" > /dev/null 2>&1; then
    success "Doppler API is reachable"
else
    warn "Cannot reach Doppler API (check network/VPN)"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
fi
echo ""

# Summary
echo "=============================================="
echo "  Verification Summary"
echo "=============================================="
if [[ $ISSUES_FOUND -eq 0 ]]; then
    success "Environment verification passed!"
    echo ""
    echo "Ready to use 'doppler run -- <command>' for secret injection."
    exit 0
else
    error "Found $ISSUES_FOUND issue(s) that should be addressed"
    echo ""
    echo "Run 'scripts/check_status.sh' for structured error codes."
    echo "Refer to 'references/SOP.md' for resolution steps."
    exit 1
fi