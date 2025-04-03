#!/bin/bash

# ARK Server Initialization Script
# Main entrypoint for ARK server container

# Ensure the script exits on any error
set -e

# Define absolute paths for utilities
UTILS_PATH="${MANAGER_DIR}/utils"

# Set executable flag on all utils just to be sure
chmod +x ${UTILS_PATH}/*.sh 2>/dev/null || true

# Load utilities with absolute paths
source "${UTILS_PATH}/colorPrinter.sh"
source "${UTILS_PATH}/apiManager.sh"
source "${UTILS_PATH}/logManager.sh"
source "${UTILS_PATH}/envManager.sh"
source "${UTILS_PATH}/pluginManager.sh"

# Process command line arguments
process_command_line_args() {
    if [ $# -gt 0 ]; then
        print_info "Executing command: $*"
        eval "$@"
        return 0
    fi
    return 1
}

# Main execution function
main() {
    print_header "🚀 Starting ARK Server Container"

    # If command is provided, run it and exit
    if process_command_line_args "$@"; then
        print_success "Command executed successfully, exiting"
        exit 0
    fi

    # Setup graceful shutdown handlers
    print_info "Setting up shutdown handlers..."
    setup_shutdown_handlers

    # Update ARK Server
    print_info "Checking for ARK server updates..."
    "${MANAGER_DIR}/update.sh"

    # Check and update server API
    print_info "Checking server API status..."
    check_and_update_server_api

    # Install or update plugins
    print_info "Checking plugins..."
    install_plugins "$ARK_DIR"

    print_header "✅ Server initialization complete"
    print_info "Starting server..."
    "${MANAGER_DIR}/start.sh"

    # Start the server monitor in the background
    echo "🔍 Starting server monitor..."
    "${MANAGER_DIR}/monitorManager.sh" start

    # Start tail logs
    print_info "Starting log monitoring..."
    tail_logs
}

# Run the main function with all arguments
main "$@" || {
    print_error "❌ Error during server startup: $?"
    exit 1
}
