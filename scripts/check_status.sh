#!/bin/bash

# Check if Doppler CLI is installed
if ! command -v doppler &> /dev/null; then
    echo "Error: Doppler CLI is not installed. Please follow instructions in SOP.md."
    exit 1
fi

echo "Doppler CLI is installed."

# Check configuration
config_output=$(doppler configure 2>&1)
if [[ $? -ne 0 ]]; then
    echo "Error: Configuration check failed."
    echo "$config_output"
else
    echo "Current Configuration:"
    echo "$config_output" | grep -E "project|config|token"
fi

# Check secrets accessibility
echo "Testing connectivity with 'doppler secrets'..."
if doppler secrets &> /dev/null; then
    echo "Success: Authenticated and able to list secrets."
else
    echo "Warning: Unable to list secrets. Authentication might be missing or token might be invalid."
fi
