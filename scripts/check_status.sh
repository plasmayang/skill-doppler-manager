#!/bin/bash

# Ensure Doppler CLI is installed
if ! command -v doppler &> /dev/null; then
    echo "STATUS: ERROR - Doppler CLI is not installed."
    exit 1
fi

# Check configuration and authentication status
# We capture stderr to /dev/null to keep output clean
if ! doppler configure &> /dev/null; then
    echo "STATUS: ERROR - Doppler CLI is installed but not authenticated or configured."
    exit 1
fi

# Extract Project and Config for context (using doppler configure plain output)
PROJECT=$(doppler configure get project --plain 2>/dev/null)
CONFIG=$(doppler configure get config --plain 2>/dev/null)

if [[ -z "$PROJECT" ]] || [[ -z "$CONFIG" ]]; then
    echo "STATUS: WARNING - Authenticated, but no default Project or Config is set for this directory."
    exit 0
fi

echo "STATUS: OK - Authenticated (Project: ${PROJECT}, Config: ${CONFIG})"
exit 0
