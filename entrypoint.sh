#!/bin/sh
set -e

# Usage instructions:
# - volumes:
#     - ./your-conf.conf:/tmp/custom-conf.tpl:ro
#     - ../entrypoint.sh:/tmp/entrypoint.sh:ro
#     - ../.env:/tmp/env-file:ro
# - entrypoint: ["sh", "/tmp/entrypoint.sh"]
# - environment:
#     - CONFIG_OUTPUT_PATH=/config/your-conf.conf


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

    # Local IP for the ice4j mapping harvester.
    export _LOCAL_ADDRESS=$(ip route get 1 | grep -oP '(?<=src ).*' | awk '{ print $1 '})

    # Process the custom config template if it exists
    if [ -f /tmp/custom-conf.tpl ]; then
        # echo "Processing custom config template..."

        # Use CONFIG_OUTPUT_PATH or fall back to default
        output_path="${CONFIG_OUTPUT_PATH:-/config/custom-jvb.conf}"

        # Ensure the output directory exists
        output_dir=$(dirname "$output_path")
        mkdir -p "$output_dir"

        # Use tpl to process the template with environment variables
        tpl /tmp/custom-conf.tpl > "$output_path"

        echo "Custom config processed and saved to $output_path"
    else
        echo "Warning: No custom config template found at /tmp/custom-conf.tpl"
    fi
)

# Continue with the original container initialization
# The environment variables from the .env file are NOT available here
# due to the subshell isolation above
exec /init "$@"
