#!/bin/bash
#
# ARK Server RCON Command Script
# Sends RCON commands to the ARK server
#
# Usage: ./rcon.sh <command> [--silent]
# Example: ./rcon.sh "SaveWorld" --silent
#
# =============================================================================

# Load utilities
source "$MANAGER_DIR/utils/common.sh"

# Pass arguments to check_silent_flag to automatically handle silent mode
check_silent_flag "$@"

# =============================================================================
# CONFIGURATION
# =============================================================================

# Required environment variables
declare -a REQUIRED_VARS=(
    "SERVER_ADMIN_PASSWORD" # Admin password for RCON
    "NETWORK_RCON_PORT"     # RCON port for remote commands
)

# Parse command line arguments
parse_args() {
    COMMAND=""

    for arg in "$@"; do
        if does_not_equal "$arg" "--silent" && is_empty "$COMMAND"; then
            COMMAND="$arg"
        fi
    done

    # Command is required
    if is_empty "$COMMAND"; then
        print_error "No command provided"
        echo "Usage: ./rcon.sh <command> [--silent]"
        return 1
    fi

    return 0
}

# Setup RCON details and validate requirements
setup_rcon() {
    # Find RCON binary path
    RCON_PATH=""
    RCON_PATHS=(
        "/home/arkuser/.local/bin/rcon"
        "/usr/bin/rcon"
        "/usr/local/bin/rcon"
    )

    for path in "${RCON_PATHS[@]}"; do
        if file_exists "$path"; then
            RCON_PATH="$path"
            break
        fi
    done

    if is_empty "$RCON_PATH"; then
        print_error "RCON binary not found. Cannot communicate with server via RCON."
        print_info "To install RCON tools, you need to add the package to your Dockerfile."
        print_info "Searched in: ${RCON_PATHS[*]}"
        return 1
    fi

    if ! is_executable "$RCON_PATH"; then
        print_error "RCON binary at $RCON_PATH is not executable"
        return 1
    fi

    # Configure connection details
    RCON_TIMEOUT=${RCON_TIMEOUT:-5}
    CONTAINER_IP=$(hostname -I | awk '{print $1}')
    CONTAINER_IP=${CONTAINER_IP:-"0.0.0.0"}

    return 0
}

# Execute RCON command
execute_rcon() {
    # Construct command line
    local cmd_line=("$RCON_PATH" -a "${CONTAINER_IP}:${NETWORK_RCON_PORT}" -p "${SERVER_ADMIN_PASSWORD}" -t "$RCON_TIMEOUT" "$COMMAND")

    # Execute the command
    local output
    output=$(capture_all_output "${cmd_line[@]}")
    local status=$?

    # Handle error cases
    if does_not_equal "$status" "0"; then
        if contains "$output" "i/o timeout"; then
            print_error "RCON timeout - server not responding"
        elif contains "$output" "connection refused"; then
            print_error "RCON connection refused - server not accepting connections"
        elif contains "$output" "authentication failed"; then
            print_error "RCON authentication failed - incorrect password"
        else
            print_error "RCON command failed: $output"
        fi
        return 1
    fi

    # Return the output for successful commands
    echo "$output"
    return 0
}

# Main function
main() {
    # Parse arguments
    parse_args "$@" || return 1

    # Display header if not in silent mode
    if does_not_equal "$COMMON_SILENT" "true"; then
        print_script_header "ARK Server RCON Command"
    fi

    # Check required environment variables
    check_required_env REQUIRED_VARS || return 1

    # Setup RCON
    setup_rcon || return 1

    # Execute the command
    local result
    result=$(execute_rcon)
    local status=$?

    # Handle the result
    if equals "$status" "0"; then
        if does_not_equal "$COMMON_SILENT" "true"; then
            print_success "Command sent successfully"
            echo "Response:"
            echo "$result"
        else
            # In silent mode, just output the raw result
            echo "$result"
        fi
    fi

    return $status
}

# Run the main function
main "$@"
