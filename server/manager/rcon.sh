#!/bin/bash
#
# ARK Server RCON Command Script
# Sends RCON commands to the ARK server
#
# Usage: ./rcon.sh <command> [options]
# Options:
#   --silent      Don't display headers or informational messages
#   --debug       Show detailed debugging information
#
# Example: ./rcon.sh "SaveWorld" --silent
#
# =============================================================================

# Load environment variables and utilities
UTILS_PATH="$MANAGER_DIR/utils"
source "${UTILS_PATH}/common.sh"

# =============================================================================
# CONFIGURATION
# =============================================================================

# Required environment variables
declare -a REQUIRED_VARS=(
    "SERVER_ADMIN_PASSWORD" # Admin password for RCON
    "NETWORK_RCON_PORT"     # RCON port for remote commands
)

# Set default values for optional variables
set_rcon_defaults() {
    # Default values
    RCON_TIMEOUT=${RCON_TIMEOUT:-5}           # Default timeout in seconds
    RCON_MAX_ATTEMPTS=${RCON_MAX_ATTEMPTS:-3} # Default max attempts

    # Get the container's IP address
    local ip=$(hostname -I | awk '{print $1}')
    CONTAINER_IP=${ip:-"0.0.0.0"} # Fallback to all interfaces if empty

    # RCON paths to check
    RCON_PATHS=(
        "/home/arkuser/.local/bin/rcon"
        "/usr/bin/rcon"
        "/usr/local/bin/rcon"
    )

    # Find the first available RCON binary
    RCON_PATH=""
    for path in "${RCON_PATHS[@]}"; do
        if [ -f "$path" ]; then
            RCON_PATH="$path"
            break
        fi
    done

    # Setup RCON command line arguments
    RCON_CMDLINE=("${RCON_PATH}" -a "${CONTAINER_IP}:${NETWORK_RCON_PORT}" -p "${SERVER_ADMIN_PASSWORD}" -t ${RCON_TIMEOUT})

    # Debug output
    if [[ $DEBUG -eq 1 ]]; then
        print_info "Debug: Using RCON binary: $RCON_PATH"
        print_info "Debug: Connection details: ${CONTAINER_IP}:${NETWORK_RCON_PORT}"
        print_info "Debug: Timeout: ${RCON_TIMEOUT} seconds"
        print_info "Debug: Max attempts: ${RCON_MAX_ATTEMPTS}"
        # Print command without password
        print_info "Debug: Command (masked): ${RCON_PATH} -a ${CONTAINER_IP}:${NETWORK_RCON_PORT} -p ******** -t ${RCON_TIMEOUT}"
    fi
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Log RCON attempts for debugging
log_rcon_attempt() {
    local cmd="$1"
    local result="$2"
    local status="$3"

    if [[ $DEBUG -eq 1 ]]; then
        print_info "RCON debug: Command sent: $cmd"
        print_info "RCON debug: Exit Code: $status"
        print_info "RCON debug: Raw Output: $result"
    fi
}

# Check if RCON is available
check_rcon_available() {
    if [ -z "$RCON_PATH" ]; then
        print_warning "⚠️ RCON binary not found. Cannot communicate with server via RCON."
        if [[ $DEBUG -eq 1 ]]; then
            print_info "Debug: Searched in these locations:"
            for path in "${RCON_PATHS[@]}"; do
                echo "  - $path"
            done
        fi
        print_info "To install RCON tools, you need to add the package to your Dockerfile."
        return 1
    fi

    if [ ! -x "$RCON_PATH" ]; then
        print_warning "⚠️ RCON binary at $RCON_PATH is not executable."
        if [[ $DEBUG -eq 1 ]]; then
            ls -la "$RCON_PATH"
        fi
        return 1
    fi

    return 0
}

# Run an RCON command with retries and error handling
run_rcon_command() {
    local cmd="$1"
    local silent=${2:-0}

    # Check if rcon is available first
    if ! check_rcon_available; then
        echo "RCON_NOT_AVAILABLE"
        return 2
    fi

    local attempt=1
    local delay=2

    while [ $attempt -le $RCON_MAX_ATTEMPTS ]; do
        if [ "$silent" -eq 0 ] || [ "$DEBUG" -eq 1 ]; then
            print_info "Attempt $attempt of $RCON_MAX_ATTEMPTS: Sending RCON command: $cmd"
        fi

        # Run the command with very verbose debugging if requested
        if [[ $DEBUG -eq 1 ]]; then
            print_info "Debug: Full command line: ${RCON_CMDLINE[*]} \"$cmd\""
            print_info "Debug: Starting RCON command execution..."
        fi

        local output=$(${RCON_CMDLINE[@]} "$cmd" 2>&1)
        local status=$?

        log_rcon_attempt "$cmd" "$output" "$status"

        # Check for various error conditions
        if [[ "$output" == *"i/o timeout"* ]]; then
            # Connection timeout
            if [ "$silent" -eq 0 ] || [ "$DEBUG" -eq 1 ]; then
                print_warning "RCON timeout on attempt $attempt"
                if [[ $DEBUG -eq 1 ]]; then
                    print_info "Debug: Timeout details - ${RCON_TIMEOUT}s elapsed"
                    print_info "Debug: Server may not be ready or RCON port is incorrect"
                fi
            fi

            if [ $attempt -eq $RCON_MAX_ATTEMPTS ]; then
                echo "RCON_TIMEOUT"
                return 1
            fi
        elif [[ "$output" == *"connection refused"* ]] || [[ "$output" == *"Connection refused"* ]]; then
            # Connection refused
            if [ "$silent" -eq 0 ] || [ "$DEBUG" -eq 1 ]; then
                print_warning "RCON connection refused on attempt $attempt"
                if [[ $DEBUG -eq 1 ]]; then
                    print_info "Debug: Server may not be running or RCON port is incorrect"
                fi
            fi

            if [ $attempt -eq $RCON_MAX_ATTEMPTS ]; then
                echo "RCON_CONNECTION_REFUSED"
                return 1
            fi
        elif [[ "$output" == *"authentication failed"* ]] || [[ "$output" == *"Authentication failed"* ]]; then
            # Authentication failure
            if [ "$silent" -eq 0 ] || [ "$DEBUG" -eq 1 ]; then
                print_warning "RCON authentication failed on attempt $attempt"
                if [[ $DEBUG -eq 1 ]]; then
                    print_info "Debug: Incorrect RCON password"
                fi
            fi

            if [ $attempt -eq $RCON_MAX_ATTEMPTS ]; then
                echo "RCON_AUTH_FAILED"
                return 1
            fi
        elif [[ -z "$output" ]]; then
            # Empty response
            if [ "$silent" -eq 0 ] || [ "$DEBUG" -eq 1 ]; then
                print_warning "RCON returned empty response on attempt $attempt"
                if [[ $DEBUG -eq 1 ]]; then
                    print_info "Debug: Command may have had no output, or connection may have failed"
                fi
            fi

            # For empty responses, check the status code to determine success
            if [ $status -eq 0 ]; then
                # Empty output but success status - the command worked but returned nothing
                echo "NO_OUTPUT"
                return 0
            fi

            if [ $attempt -eq $RCON_MAX_ATTEMPTS ]; then
                echo "RCON_EMPTY_RESPONSE"
                return 1
            fi
        elif [ $status -eq 0 ]; then
            # Command succeeded with output
            echo "$output"
            return 0
        fi

        # If we got here, the command failed but we can retry
        if [ "$silent" -eq 0 ] || [ "$DEBUG" -eq 1 ]; then
            print_warning "RCON attempt $attempt failed. Waiting ${delay}s before retry..."
            if [[ $DEBUG -eq 1 ]]; then
                print_info "Debug: Error details: $output"
                print_info "Debug: Exit code: $status"
            fi
        fi

        sleep $delay
        attempt=$((attempt + 1))
        delay=$((delay * 2)) # Exponential backoff
    done

    # All attempts failed
    echo "RCON_FAILED"
    return 1
}

# Parse arguments and set flags
parse_arguments() {
    # Default values
    SILENT=0
    DEBUG=0
    COMMAND=""

    # Parse arguments
    for arg in "$@"; do
        if [[ "$arg" == "--silent" ]]; then
            SILENT=1
        elif [[ "$arg" == "--debug" ]]; then
            DEBUG=1
            # Debug mode overrides silent mode for detailed output
            SILENT=0
        elif [[ -z "$COMMAND" ]]; then
            COMMAND="$arg"
        fi
    done

    # Check if command is provided
    if [[ -z "$COMMAND" ]]; then
        return 1
    fi

    return 0
}

# Print usage information
print_usage() {
    echo "Usage: ./rcon.sh <command> [options]"
    echo "Example: ./rcon.sh \"SaveWorld\" --silent"
    echo ""
    echo "Options:"
    echo "  <command>   RCON command to send to the server"
    echo "  --silent    Run in silent mode (no status messages)"
    echo "  --debug     Show detailed debugging information"
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

# Main function
main() {
    # Parse arguments
    if ! parse_arguments "$@"; then
        print_error "❌ No command provided"
        print_usage
        return 1
    fi

    # Only show header if not silent
    if [[ $SILENT -eq 0 ]]; then
        print_script_header "🎮 ARK Server RCON Command"
        echo ""
    fi

    # Show debug info about environment
    if [[ $DEBUG -eq 1 ]]; then
        print_info "Debug: Environment variables:"
        print_info "Debug: MANAGER_DIR: $MANAGER_DIR"
        print_info "Debug: ARK_DIR: $ARK_DIR"
        print_info "Debug: SERVER_ADMIN_PASSWORD: ********"
        print_info "Debug: NETWORK_RCON_PORT: $NETWORK_RCON_PORT"
        print_info "Debug: RCON_TIMEOUT: $RCON_TIMEOUT"
        print_info "Debug: RCON_MAX_ATTEMPTS: $RCON_MAX_ATTEMPTS"
    fi

    # Check required environment variables
    check_required_env REQUIRED_VARS || exit 1

    # Set default values
    set_rcon_defaults

    # Debug connection test if requested
    if [[ $DEBUG -eq 1 ]]; then
        print_info "Debug: Testing network connectivity..."
        print_info "Debug: Container IP: $CONTAINER_IP"
        print_info "Debug: Target port: $NETWORK_RCON_PORT"

        # Try using a built-in bash method instead of nc
        if (</dev/tcp/$CONTAINER_IP/$NETWORK_RCON_PORT) 2>/dev/null; then
            print_info "Debug: Port is open and connection test succeeded"
        else
            print_warning "Debug: Connection test failed - port may be closed or server not listening"
        fi
    fi

    # Run RCON command
    local output
    output=$(run_rcon_command "$COMMAND" $SILENT)
    local res=$?

    # Handle special error cases
    case "$output" in
    "RCON_TIMEOUT")
        print_error "❌ RCON timeout - server not responding within ${RCON_TIMEOUT} seconds"
        if [[ $DEBUG -eq 1 ]]; then
            print_info "Debug: Try increasing RCON_TIMEOUT or check if server is running"
        fi
        return 1
        ;;
    "RCON_CONNECTION_REFUSED")
        print_error "❌ RCON connection refused - server not accepting connections"
        if [[ $DEBUG -eq 1 ]]; then
            print_info "Debug: Make sure the server is running and RCON port is correct"
            print_info "Debug: Current RCON port: ${NETWORK_RCON_PORT}"
        fi
        return 1
        ;;
    "RCON_AUTH_FAILED")
        print_error "❌ RCON authentication failed - incorrect password"
        if [[ $DEBUG -eq 1 ]]; then
            print_info "Debug: Check the SERVER_ADMIN_PASSWORD environment variable"
        fi
        return 1
        ;;
    "RCON_EMPTY_RESPONSE")
        print_warning "⚠️ RCON command returned no output but may have failed"
        if [[ $DEBUG -eq 1 ]]; then
            print_info "Debug: Command may have been rejected or not recognized by the server"
        fi
        return 1
        ;;
    "NO_OUTPUT")
        if [[ $SILENT -eq 0 ]]; then
            print_success "✅ Command sent successfully"
            print_info "Command had no output (e.g., No players online)"
        fi
        return 0
        ;;
    "RCON_NOT_AVAILABLE")
        print_error "❌ RCON command not available - RCON client not found"
        return 1
        ;;
    "RCON_FAILED")
        print_error "❌ All RCON command attempts failed"
        if [[ $DEBUG -eq 1 ]]; then
            print_info "Debug: Try increasing RCON_MAX_ATTEMPTS or check server status"
        fi
        return 1
        ;;
    *)
        if [[ $SILENT -eq 0 ]]; then
            print_success "✅ Command sent successfully"
            echo "Response:"
            echo "$output"
        else
            echo "$output"
        fi
        return 0
        ;;
    esac
}

# Execute the main function
main "$@"
