#!/bin/bash

# ARK Server JSON Configuration Loader
# Reads configuration from JSON file and exports as environment variables

# Path to utilities
UTILS_PATH="${MANAGER_DIR:-/manager}/utils"
source "${UTILS_PATH}/colorPrinter.sh"

# Set strict mode
set -eo pipefail

# Main function to load config
load_config() {
    local CONFIG_FILE="/ark-server-config.json"

    # Check if config file exists
    if [ ! -f "$CONFIG_FILE" ]; then
        print_error "Configuration file not found: $CONFIG_FILE"
        return 1
    fi

    # Check if jq is available
    if ! command -v jq &>/dev/null; then
        print_error "jq is not installed. Cannot parse JSON config."
        return 1
    fi

    # Validate the JSON format
    if ! jq . "$CONFIG_FILE" &>/dev/null; then
        print_error "Invalid JSON format in $CONFIG_FILE"
        return 1
    fi

    # Parse JSON and export variables
    declare -A config_vars

    # Handle special cases first

    # Handle extra dash options - convert array to string with "-" prefix
    # Format: EXTRA_DASH_OPTIONS="-option1 -option2 -option3"
    local extra_dash_options=$(jq -r '.gameplay.extra_dash_options | if type=="array" then map("-" + .) | join(" ") else "" end' "$CONFIG_FILE" 2>/dev/null)
    if [[ -n "$extra_dash_options" && "$extra_dash_options" != "null" && "$extra_dash_options" != "" ]]; then
        config_vars["GAMEPLAY_EXTRA_DASH_OPTIONS"]="$extra_dash_options"
        export GAMEPLAY_EXTRA_DASH_OPTIONS="$extra_dash_options"
    fi

    # Handle extra options - convert object to string with "?key=value" format
    # Format: EXTRA_OPTIONS="?option1=value1 ?option2=value2 ?option3=value3"
    local extra_options=$(jq -r '.gameplay.extra_options | if type=="object" then to_entries | map("?" + .key + "=" + (.value|tostring)) | join("") else "" end' "$CONFIG_FILE" 2>/dev/null)
    if [[ -n "$extra_options" && "$extra_options" != "null" && "$extra_options" != "" ]]; then
        config_vars["GAMEPLAY_EXTRA_OPTIONS"]="$extra_options"
        export GAMEPLAY_EXTRA_OPTIONS="$extra_options"
    fi

    # Handle mods - convert array to comma-separated string
    # Format: MODS="936660,936661,936662"
    local mods=$(jq -r '.gameplay.mods | if type=="array" then join(",") else "" end' "$CONFIG_FILE" 2>/dev/null)
    if [[ -n "$mods" && "$mods" != "null" && "$mods" != "" ]]; then
        config_vars["GAMEPLAY_MODS"]="$mods"
        export GAMEPLAY_MODS="$mods"
    fi

    # Get root level keys from the JSON
    local json_keys
    json_keys=$(jq -r 'keys[]' "$CONFIG_FILE" 2>/dev/null)

    # Process each section with nested properties
    for section in $json_keys; do
        # Skip empty sections
        [ -z "$section" ] && continue

        # Get keys in this section
        local section_keys
        section_keys=$(jq -r --arg s "$section" '.[$s] | keys[]' "$CONFIG_FILE" 2>/dev/null)

        if [ $? -eq 0 ] && [ -n "$section_keys" ]; then
            # Process each key in the section
            for key in $section_keys; do
                # Skip empty keys
                [ -z "$key" ] && continue

                # Skip our special cases that were already handled
                if [[ "$section" == "gameplay" && ("$key" == "extra_dash_options" || "$key" == "extra_options" || "$key" == "mods") ]]; then
                    continue
                fi

                # Extract the value for this key
                local value
                value=$(jq -r --arg s "$section" --arg k "$key" '.[$s][$k]' "$CONFIG_FILE")

                # Skip null values
                [[ "$value" == "null" ]] && continue

                # Create environment variable name (ARK_SECTION_KEY)
                local env_var_name
                env_var_name="$(echo "${section}_${key}" | tr '[:lower:]' '[:upper:]')"

                # Add to our associative array
                config_vars["$env_var_name"]="$value"

                # Export the variable in the current shell
                export "$env_var_name"="$value"
            done
        fi
    done

    # Check if we found any config variables
    if [ ${#config_vars[@]} -eq 0 ]; then
        print_warning "No valid configuration variables found in $CONFIG_FILE"
    fi

    # Always add a test variable to confirm script execution
    config_vars["CONFIG_LOADER_TEST"]="test_value_$(date +%s)"
    export CONFIG_LOADER_TEST="${config_vars["CONFIG_LOADER_TEST"]}"

    # Export all the variables to current environment (for Docker)
    for var_name in "${!config_vars[@]}"; do
        export "${var_name}"="${config_vars[$var_name]}"
    done

    return 0
}

load_config
