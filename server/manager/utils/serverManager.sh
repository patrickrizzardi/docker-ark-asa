#!/bin/bash

# Load utilities
UTILS_PATH="$MANAGER_DIR/utils"
source "${UTILS_PATH}/colorPrinter.sh"

# Setup graceful shutdown handlers
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
