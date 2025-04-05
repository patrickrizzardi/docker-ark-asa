#!/bin/bash
# TODO

# ARK Server Initialization Script
# Main entrypoint for ARK server container

# Ensure the script exits on any error
set -e

# Define absolute paths for utilities
source "${MANAGER_DIR}/utils/common.sh"

# Set executable flag on all files and directories in the manager directory
chmod +x ${MANAGER_DIR}/*.sh 2>/dev/null || true
chmod +x ${MANAGER_DIR}/utils/*.sh 2>/dev/null || true

# Process command line arguments
process_command_line_args() {
    if [ $# -gt 0 ]; then
        print_info "Executing command: $*"
        eval "$@"
        return 0
    fi
    return 1
}

setup_shutdown_handlers() {
    print_info "Setting up shutdown handlers..."

    # Function to handle shutdown signals
    shutdown_handler() {
        print_info "Received shutdown signal. Stopping server..."
        "${MANAGER_DIR}/stop.sh"
        exit 0
    }

    # Set up trap for common signals
    trap shutdown_handler SIGTERM SIGINT

    print_success "Shutdown handlers configured"
}

# Main execution function
main() {
    print_script_header "🚀 Starting ARK Server Container"

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

    print_script_header "✅ Server initialization complete"
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
