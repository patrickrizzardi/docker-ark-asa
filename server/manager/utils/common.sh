#!/bin/bash

# ARK Server Common Utilities
# Central utility script that loads all other utilities and provides common functions

# =============================================================================
# LOAD UTILITIES
# =============================================================================

# Define path to utilities directory
UTILS_PATH="$MANAGER_DIR/utils"

# Load essential utilities
source "${UTILS_PATH}/colorPrinter.sh"
source "${UTILS_PATH}/processManager.sh"
source "${UTILS_PATH}/envManager.sh"
source "${UTILS_PATH}/fileManager.sh"
source "${UTILS_PATH}/logManager.sh"

source "${UTILS_PATH}/configLoader.sh"

# =============================================================================
# COMMON VARIABLES
# =============================================================================

# Script information
SCRIPT_NAME=$(basename "$0")
SCRIPT_PID=$$
SCRIPT_START_TIME=$(date +%s)

# Flag files
SERVER_START_FLAG="${ARK_DIR}/starting.flag"
SERVER_UPDATE_FLAG="${ARK_DIR}/updating.flag"
SERVER_RESTART_FLAG="${ARK_DIR}/restarting.flag"
SERVER_STOP_FLAG="${ARK_DIR}/stopping.flag"
SERVER_SAVE_FLAG="${ARK_DIR}/saving.flag"
SERVER_SHUTDOWN_COMPLETE_FLAG="${ARK_DIR}/shutdown_complete.flag"

# =============================================================================
# ERROR HANDLING & CLEANUP
# =============================================================================

# Default trap handler for cleanup
common_cleanup() {
    local exit_code=$?
    local duration=$(($(date +%s) - SCRIPT_START_TIME))

    print_info "Script ${SCRIPT_NAME} completed in ${duration} seconds with exit code: ${exit_code}"

    # Remove PID file if it exists and belongs to this script
    if [[ -f "${ARK_DIR}/${SCRIPT_NAME}.pid" ]]; then
        local pid=$(cat "${ARK_DIR}/${SCRIPT_NAME}.pid")
        if [[ "$pid" == "$SCRIPT_PID" ]]; then
            rm -f "${ARK_DIR}/${SCRIPT_NAME}.pid"
        fi
    fi

    # Execute script-specific cleanup if defined
    if type script_cleanup >/dev/null 2>&1; then
        script_cleanup
    fi

    exit $exit_code
}

# Set default trap for EXIT
trap common_cleanup EXIT

# Handle termination signals
handle_termination() {
    local signal=$1
    print_warning "⚠️ Received ${signal} signal"

    # Execute script-specific termination handler if defined
    if type script_terminate >/dev/null 2>&1; then
        script_terminate "$signal"
    fi

    exit 1
}

# Set traps for termination signals
trap 'handle_termination SIGTERM' SIGTERM
trap 'handle_termination SIGINT' SIGINT
trap 'handle_termination SIGHUP' SIGHUP

# Function to handle script errors
handle_error() {
    local line=$1
    local cmd=$2
    local code=$3

    print_error "❌ Error in ${SCRIPT_NAME} line ${line}: Command '${cmd}' exited with code ${code}"

    # Execute script-specific error handler if defined
    if type script_error >/dev/null 2>&1; then
        script_error "$line" "$cmd" "$code"
    fi
}

# Set trap for ERR if in strict mode
# Note: to enable strict mode, scripts should use "set -eE" at the beginning
trap 'handle_error ${LINENO} "${BASH_COMMAND}" $?' ERR

# =============================================================================
# COMMON FUNCTIONS
# =============================================================================

# Function to create a PID file for the script
create_pid_file() {
    local pid_file="${ARK_DIR}/${SCRIPT_NAME}.pid"
    echo "$SCRIPT_PID" >"$pid_file"
    print_info "Created PID file: $pid_file"
}

# Function to check if another instance of this script is running
is_script_running() {
    local pid_file="${ARK_DIR}/${SCRIPT_NAME}.pid"

    if [[ -f "$pid_file" ]]; then
        local pid=$(cat "$pid_file")

        # Check if PID is still active
        if ps -p "$pid" >/dev/null; then
            # Check if it's actually the right script and not a reused PID
            if ps -p "$pid" -o command= | grep -q "$SCRIPT_NAME"; then
                return 0 # Script is running
            fi
        fi

        # PID file exists but process doesn't or is wrong
        rm -f "$pid_file"
    fi

    return 1 # Script is not running
}

# Function to check if server is in a specific state based on flag files
is_server_starting() {
    [[ -f "$SERVER_START_FLAG" ]]
}

is_server_updating() {
    [[ -f "$UPDATE_LOCK_FILE" ]]
}

is_server_restarting() {
    [[ -f "$RESTART_FLAG" ]]
}

is_server_stopped() {
    [[ -f "$NO_RESTART_FLAG" ]]
}

# Function to format time duration
format_duration() {
    local seconds=$1
    local days=$((seconds / 86400))
    local hours=$(((seconds % 86400) / 3600))
    local minutes=$(((seconds % 3600) / 60))
    local sec=$((seconds % 60))

    if [[ $days -gt 0 ]]; then
        echo "${days}d ${hours}h ${minutes}m ${sec}s"
    elif [[ $hours -gt 0 ]]; then
        echo "${hours}h ${minutes}m ${sec}s"
    elif [[ $minutes -gt 0 ]]; then
        echo "${minutes}m ${sec}s"
    else
        echo "${sec}s"
    fi
}

# Function to create a spinner for long-running operations
declare -a SPINNER=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
SPINNER_IDX=0

show_spinner() {
    local message="$1"
    local current_spinner=${SPINNER[$SPINNER_IDX]}
    SPINNER_IDX=$(((SPINNER_IDX + 1) % ${#SPINNER[@]}))

    printf "\r${current_spinner} ${message}"
}

# Function to run a command with a spinner
run_with_spinner() {
    local command="$1"
    local message="$2"
    local interval=${3:-0.2}
    local spin_pid

    # Start the spinner in background
    (
        while true; do
            show_spinner "$message"
            sleep $interval
        done
    ) &
    spin_pid=$!

    # Ensure spinner is killed on exit
    trap "kill $spin_pid >/dev/null 2>&1; wait $spin_pid 2>/dev/null" EXIT

    # Run the command
    eval "$command"
    local result=$?

    # Stop the spinner (trap will also ensure this happens)
    kill $spin_pid >/dev/null 2>&1
    wait $spin_pid 2>/dev/null
    trap - EXIT # Remove the trap

    printf "\r%-80s\r" " " # Clear the spinner line

    return $result
}

# Function to print script header with consistent format
print_script_header() {
    local title="$1"
    local char="="
    local width=80
    local padding=$(((width - ${#title} - 2) / 2))
    local line=$(printf "%${width}s" | tr " " "$char")

    echo ""
    echo "$line"
    printf "%s %s %s\n" "$(printf "%${padding}s" | tr " " "$char")" "$title" "$(printf "%${padding}s" | tr " " "$char")"
    echo "$line"
    echo ""
}
