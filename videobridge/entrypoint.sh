#!/bin/sh
set -e

# echo "Processing custom JVB configuration..."

# Process custom config in an isolated environment
(
    # Source the environment file to get variables for template processing
    if [ -f /tmp/env-file ]; then
        set -a  # Automatically export all variables
        . /tmp/env-file
        set +a  # Stop auto-exporting
        echo "Loaded environment variables from /tmp/env-file"
    else
        echo "Warning: No .env file found at /tmp/env-file"
    fi

    # Process the custom JVB config template if it exists
    if [ -f /tmp/custom-jvb.conf.tpl ]; then
        # echo "Processing custom JVB config template..."

        # Ensure the config directory exists
        mkdir -p /config

        # Use tpl to process the template with environment variables
        tpl /tmp/custom-jvb.conf.tpl > /config/custom-jvb.conf

        # Set proper ownership for the processed config
        chown jvb:jitsi /config/custom-jvb.conf 2>/dev/null || true

        echo "Custom JVB config processed and saved to /config/custom-jvb.conf"
    else
        echo "Warning: No custom JVB config template found at /tmp/custom-jvb.conf.tpl"
    fi
)

# echo "Custom config processing complete. Starting normal container initialization..."

# Continue with the original container initialization
# The environment variables from the .env file are NOT available here
# due to the subshell isolation above
exec /init "$@"
