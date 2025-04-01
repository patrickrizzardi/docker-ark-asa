#!/bin/bash

# Load utilities
UTILS_PATH="$MANAGER_DIR/utils"
source "${UTILS_PATH}/colorPrinter.sh"

# Default process names to check
DEFAULT_PROCESS_NAMES=("ShooterGameServer","GameThread")

# Check if the ARK server is currently running
# Params:
#   $1 - silent mode (1 = silent, 0 = verbose) - optional
#   $2 - comma-separated process names to check - optional
is_server_running() {
    local silent=${1:-0}
    local process_names_str=${2:-"ShooterGameServer,GameThread"}
    
    # Convert comma-separated string to array
    IFS=',' read -r -a process_names <<< "$process_names_str"
    
    local is_running=1
    
    # Check for server processes using pgrep which is more reliable
    for process_name in "${process_names[@]}"; do
        # Use a more specific pattern to avoid matching processes that aren't actually running the game
        # Look for wine64 command running the actual executable
        if pgrep -f "wine64.*/.*${process_name}($| )" >/dev/null 2>&1; then
            is_running=0
            break
        fi
    done
    
    # Print status message unless silent
    if [ "$silent" -eq 0 ]; then
        if [ "$is_running" -eq 0 ]; then
            print_warning "ARK server is currently running."
        else
            print_success "ARK server is not running."
        fi
    fi
    
    return $is_running
}

# Ensures the server is in the expected running state before proceeding
# Params:
#   $1 - should_be_running (0 = should be running, 1 = should be stopped)
#   $2 - silent mode (1 = silent, 0 = verbose) - optional
#   $3 - comma-separated process names to check - optional
# Returns:
#   0 if server is in expected state, 1 otherwise
ensure_server_state() {
    local should_be_running=$1
    local silent=${2:-0}
    local process_names=${3:-"AsaApiLoader.exe,ArkAscendedServer.exe"}
    
    # Check if server is running (silently)
    is_server_running 1 "$process_names"
    local is_running=$?
    
    # If state matches expectation, return success
    if [ $is_running -eq $should_be_running ]; then
        if [ "$silent" -eq 0 ]; then
            if [ $should_be_running -eq 1 ]; then
                print_success "Server is stopped as required."
            else
                print_success "Server is running as required."
            fi
        fi
        return 0
    fi
    
    # Otherwise, print error and return failure
    if [ $should_be_running -eq 0 ]; then
        print_error "${BOLD}Error: ARK Server is not running, but it needs to be for this operation."
        print_warning "Please start the server before proceeding."
    else
        print_error "${BOLD}Error: ARK Server is currently running, but it needs to be stopped for this operation."
        print_warning "Please stop the server before proceeding."
    fi
    
    return 1
}

# Ensure server is stopped before proceeding
# Params:
#   $1 - silent mode (1 = silent, 0 = verbose) - optional
#   $2 - comma-separated process names to check - optional
# Returns:
#   0 if server is stopped, 1 if running
ensure_server_stopped() {
    ensure_server_state 1 "$@"
}

# Ensure server is running before proceeding
# Params:
#   $1 - silent mode (1 = silent, 0 = verbose) - optional
#   $2 - comma-separated process names to check - optional
# Returns:
#   0 if server is running, 1 if stopped
ensure_server_running() {
    ensure_server_state 0 "$@"
} 