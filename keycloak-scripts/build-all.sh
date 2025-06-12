#!/bin/bash

# This script is intended to be run inside a Docker container context
# where the current directory is populated with META-INF and JS provider scripts.

rm -f custom-scripts.jar

# Ensure META-INF directory exists
if [ ! -d "META-INF" ]; then
    echo "Error: META-INF directory not found. It is required for the provider JAR."
    exit 1
fi

# Find all .js files in the current directory, excluding this script itself
# Using an array to correctly handle filenames if they were to have spaces (unlikely for .js)
js_provider_files=()
while IFS= read -r -d $'\0' file; do
    # Use basename to ensure we are not trying to match against a path if find returns ./script.js
    # and $(basename "$0") is just script.sh
    if [ "$(basename "$file")" != "$(basename "$0")" ]; then
        js_provider_files+=("$file")
    fi
done < <(find . -maxdepth 1 -type f -name "*.js" -print0)


if [ ${#js_provider_files[@]} -eq 0 ]; then
    echo "Error: No custom JavaScript provider files found to include in the JAR (excluding $(basename "$0")). At least one .js provider script is expected."
    exit 1
fi

echo "Found JavaScript files to include:"
printf " - %s\n" "${js_provider_files[@]}"

# Arguments for the jar command
jar_target_files=("META-INF/")
jar_target_files+=("${js_provider_files[@]}")

echo "Building custom-scripts.jar with the following contents:"
printf " - %s\n" "${jar_target_files[@]}"

# Create the JAR file
jar cf custom-scripts.jar "${jar_target_files[@]}"

# Verify the JAR was created
if [ ! -f custom-scripts.jar ]; then
    echo "Error: custom-scripts.jar was not built."
    exit 1
fi

echo "custom-scripts.jar built successfully."
