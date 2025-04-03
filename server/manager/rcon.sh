#!/bin/bash
#
# ARK Server RCON Command Script
# Sends RCON commands to the ARK server
#
# Usage: ./rcon.sh <command> [--silent]
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

# Optional environment variables
declare -a OPTIONAL_VARS=(
    "RCON_TIMEOUT"      # Timeout in seconds for RCON commands
    "RCON_MAX_ATTEMPTS" # Maximum number of retry attempts
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
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Log RCON attempts for debugging
log_rcon_attempt() {
    local cmd="$1"
    local result="$2"
    local status="$3"

    print_info "RCON debug: Command: $cmd, Exit Code: $status, Output: $result"
}

# Check if RCON is available
check_rcon_available() {
    if [ -z "$RCON_PATH" ]; then
        print_warning "⚠️ RCON binary not found. Cannot communicate with server via RCON."
        print_info "To install RCON tools, you need to add the package to your Dockerfile."
        return 1
    fi

    if [ ! -x "$RCON_PATH" ]; then
        print_warning "⚠️ RCON binary at $RCON_PATH is not executable."
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
        if [ "$silent" -eq 0 ]; then
            print_info "Attempt $attempt of $RCON_MAX_ATTEMPTS: Sending RCON command: $cmd"
        fi

        local output=$(${RCON_CMDLINE[@]} "$cmd" 2>&1)
        local status=$?

        log_rcon_attempt "$cmd" "$output" "$status"

        # Check for timeout in output
        if [[ "$output" == *"i/o timeout"* ]]; then
            if [ "$silent" -eq 0 ]; then
                print_warning "RCON timeout on attempt $attempt"
            fi

            if [ $attempt -eq $RCON_MAX_ATTEMPTS ]; then
                echo "RCON_TIMEOUT"
                return 1
            fi

            sleep $delay
            attempt=$((attempt + 1))
            delay=$((delay * 2)) # Exponential backoff
            continue
        fi

        # Command succeeded
        if [ $status -eq 0 ]; then
            echo "$output"
            return 0
        fi

        # Command failed but we can retry
        if [ "$silent" -eq 0 ]; then
            print_warning "RCON attempt $attempt failed. Waiting ${delay}s before retry..."
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
    COMMAND=""

    # Parse arguments
    for arg in "$@"; do
        if [[ "$arg" == "--silent" ]]; then
            SILENT=1
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
    echo "Usage: ./rcon.sh <command> [--silent]"
    echo "Example: ./rcon.sh \"SaveWorld\" --silent"
    echo ""
    echo "Options:"
    echo "  <command>   RCON command to send to the server"
    echo "  --silent    Run in silent mode (no status messages)"
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

# Script-specific cleanup function that will be called by common_cleanup
script_cleanup() {
    # Nothing to clean up for RCON
    :
}

# Set up trap to call cleanup on exit
trap script_cleanup EXIT INT TERM

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

    # Check required environment variables
    check_required_env REQUIRED_VARS || exit 1

    # Check optional environment variables
    check_optional_env OPTIONAL_VARS

    # Set default values
    set_rcon_defaults

    # Run RCON command
    local output
    output=$(run_rcon_command "$COMMAND" $SILENT)
    local res=$?

    # Handle special error cases
    case "$output" in
    "RCON_TIMEOUT")
        print_error "❌ RCON timeout"
        return 1
        ;;
    "RCON_NOT_AVAILABLE")
        print_error "❌ RCON command not available"
        return 1
        ;;
    "RCON_FAILED")
        print_error "❌ RCON command failed"
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
