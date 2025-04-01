#!/bin/bash

# Load utilities
UTILS_PATH="$MANAGER_DIR/utils"
source "${UTILS_PATH}/colorPrinter.sh"

# Get environment variables or set defaults
ARK_DIR=${ARK_DIR:-"/steam/steamapps/common/asa-server"}
STEAM_DIR=${STEAM_DIR:-"/steam"}
ASA_APPID=${ASA_APPID:-"2430930"}

# Update the ARK server using SteamCMD
update_ark_server() {
    print_info "Running SteamCMD to update ARK server..."
    
    if ! "$STEAM_DIR/steamcmd.sh" +force_install_dir "$ARK_DIR" +login anonymous +app_update "$ASA_APPID" +quit; then
        print_error "Error updating ARK server with SteamCMD"
        print_warning "Continuing with the rest of the setup..."
        # We continue execution even if Steam update fails
        return 1
    fi
    
    print_success "ARK server update completed"
    return 0
}

# Setup graceful shutdown handlers
setup_shutdown_handlers() {
    print_info "Setting up shutdown handlers..."
    
    # Function to handle shutdown signals
    shutdown_handler() {
        print_info "Received shutdown signal. Stopping server..."
        manager stop --saveworld
        exit 0
    }
    
    # Set up trap for common signals
    trap shutdown_handler SIGTERM SIGINT
    
    print_success "Shutdown handlers configured"
} 