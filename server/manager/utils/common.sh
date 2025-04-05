#!/bin/bash

# ARK Server Common Utilities
# Central utility script that loads all other utilities and provides common functions

# =============================================================================
# LOAD UTILITIES
# =============================================================================

# Define path to utilities directory
UTILS_PATH="$MANAGER_DIR/utils"

# Load essential utilities
source "${UTILS_PATH}/baseUtils.sh"    # Load base utilities first
source "${UTILS_PATH}/configLoader.sh" # !important: always load this after base utils to prevent circular dependencies
source "${UTILS_PATH}/colorPrinter.sh"
source "${UTILS_PATH}/processManager.sh"
source "${UTILS_PATH}/envManager.sh"
source "${UTILS_PATH}/fileManager.sh"
source "${UTILS_PATH}/logManager.sh"
source "${UTILS_PATH}/loadingAnimation.sh"
source "${UTILS_PATH}/flagFiles.sh"
source "${UTILS_PATH}/apiManager.sh"
source "${UTILS_PATH}/pluginManager.sh"

# =============================================================================
# COMMON VARIABLES
# =============================================================================

# Script information
SCRIPT_NAME=$(basename "$0")
SCRIPT_PID=$$
SCRIPT_START_TIME=$(date +%s)

# =============================================================================
# COMMON FUNCTIONS
# =============================================================================

# Check for silent flag in script arguments
# This function should be called at the beginning of scripts
check_silent_flag() {
    for arg in "$@"; do
        if [[ "$arg" == "--silent" ]]; then
            export COMMON_SILENT=true
            break
        fi
    done
}

# Default trap handler for cleanup
common_cleanup() {
    local exit_code=$?
    local duration=$(($(date +%s) - SCRIPT_START_TIME))

    # Only print completion message if not in silent mode
    if does_not_equal "$COMMON_SILENT" "true"; then
        print_info "Script ${SCRIPT_NAME} completed in ${duration} seconds with exit code: ${exit_code}"
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
