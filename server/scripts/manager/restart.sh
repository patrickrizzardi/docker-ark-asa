#!/bin/bash
#
# ARK Server Restart Script
# Gracefully stops and then restarts an ARK server instance
#
# Usage: ./restart.sh [--force] [server|api]
# - --force: Skip player checks and force server shutdown
# - server|api: Specify server type to start (default: server)
#
# =============================================================================

# Source common utilities if they exist
if [ -d "$(dirname "$0")/utils" ]; then
    for util_file in "$(dirname "$0")/utils"/*.sh; do
        if [[ -f "$util_file" ]]; then
            source "$util_file"
        fi
    done
fi

# =============================================================================
# CONFIGURATION
# =============================================================================

# Required environment variables for restarting the server
declare -a RESTART_REQUIRED_VARS=(
    "ARK_ADMIN_PASSWORD"      # Admin password for RCON
    "RCON_PORT"               # RCON port for remote commands
    "SERVER_SHUTDOWN_TIMEOUT" # Maximum time to wait for shutdown
    "ARK_DIR"                 # ARK installation directory
    "SERVER_MAP"              # Map to run
    "SESSION_NAME"            # Server session name
    "SERVER_PORT"             # Server port
    "WINE_LOG_FILE"           # Wine log file location
    "STEAM_COMPAT_DATA_PATH"  # Steam compatibility data path
)

# Flag files
SERVER_START_FLAG="${ARK_DIR}/server_starting.flag"
RESTART_FLAG="${ARK_DIR}/restart.flag"
RESTART_CLEAN_FLAG="${ARK_DIR}/restart_clean.flag"
SERVER_SAVE_FLAG="${ARK_DIR}/server_save.flag"
RESTART_TIMESTAMP_FILE="${ARK_DIR}/restart_timestamp.tmp"

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Show usage information
show_usage() {
    echo "Usage: $(basename "$0") [options]"
    echo ""
    echo "Options:"
    echo "  --clean           : Perform a clean restart (stops and starts the server)"
    echo "  --save-world      : Save the world before restarting"
    echo "  --force           : Force restart even if restart is already in progress"
    echo "  --help            : Show this help message"
    echo ""
    echo "This script performs a controlled restart of the ARK server."
}

# Parse command-line arguments
parse_arguments() {
    CLEAN_RESTART=0
    SAVE_WORLD=0
    FORCE_RESTART=0

    while [[ $# -gt 0 ]]; do
        case $1 in
        --clean)
            CLEAN_RESTART=1
            shift
            ;;
        --save-world)
            SAVE_WORLD=1
            shift
            ;;
        --force)
            FORCE_RESTART=1
            shift
            ;;
        --help)
            show_usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            show_usage
            exit 1
            ;;
        esac
    done
}

# =============================================================================
# RESTART FUNCTIONS
# =============================================================================

# Create a restart flag file to inform monitor of restart intent
create_restart_flag() {
    # Create restart flag file
    touch "$RESTART_FLAG"

    # Create timestamp file for monitoring restart timeouts
    date +%s >"$RESTART_TIMESTAMP_FILE"

    # If clean restart is requested, create that flag too
    if [[ $CLEAN_RESTART -eq 1 ]]; then
        touch "$RESTART_CLEAN_FLAG"
    fi

    # Create save flag if requested
    if [[ $SAVE_WORLD -eq 1 ]]; then
        touch "$SERVER_SAVE_FLAG"
    fi
}

# Remove restart flag
remove_restart_flag() {
    rm -f "$RESTART_FLAG" 2>/dev/null || true
    rm -f "$RESTART_CLEAN_FLAG" 2>/dev/null || true
    rm -f "$SERVER_SAVE_FLAG" 2>/dev/null || true
}

# Perform the restart
do_restart() {
    print_header "🔄 Restarting ARK Server"

    # Check if a restart is already in progress
    if [[ -f "$RESTART_FLAG" && $FORCE_RESTART -eq 0 ]]; then
        print_warning "⚠️ Restart already in progress. Use --force to override."
        return 1
    fi

    # Create restart flag file
    create_restart_flag

    # If the monitor is active, it will handle the restart process
    if is_monitor_active; then
        print_info "Monitor is active, notifying it to handle restart..."
        print_success "✅ Restart request submitted to monitor"
        print_info "Monitor will handle server restart process"
        return 0
    fi

    # Otherwise, we need to handle the restart ourselves
    print_info "No active monitor detected, handling restart directly"

    # Save world if requested
    if [[ $SAVE_WORLD -eq 1 ]]; then
        print_info "Saving world before restart..."
        "${MANAGER_DIR}/rcon.sh" "saveworld" --silent || true
        sleep 5
    fi

    # Perform clean restart if requested, otherwise use signal-based restart
    if [[ $CLEAN_RESTART -eq 1 ]]; then
        print_info "Performing clean restart (stop and start)..."

        # Stop the server
        "${MANAGER_DIR}/stop.sh" --force

        # Small delay to ensure everything is stopped
        sleep 5

        # Start the server
        "${MANAGER_DIR}/start.sh"
    else
        print_info "Performing signal-based restart..."

        # Get server PID
        local ark_pid=$(get_ark_server_pid)

        if [[ "$ark_pid" != "0" ]]; then
            # Send restart signal to the server process
            print_info "Sending SIGTERM to ARK server process..."
            kill -15 "$ark_pid"

            # Check if the monitor is active
            if is_monitor_active; then
                print_info "Monitor will handle server restart"
            else
                # Wait a bit for the server to stop
                sleep 10

                # Start the server
                print_info "Starting server after signal-based shutdown..."
                "${MANAGER_DIR}/start.sh"
            fi
        else
            print_warning "⚠️ No running ARK server found to restart"
            print_info "Starting server..."
            "${MANAGER_DIR}/start.sh"
        fi
    fi

    # Remove restart flags
    remove_restart_flag

    print_success "✅ Restart process completed"
    return 0
}

# =============================================================================
# MAIN FUNCTION
# =============================================================================

main() {
    # Parse command-line arguments
    parse_arguments "$@"

    # Check required environment variables
    if ! check_env_variables RESTART_REQUIRED_VARS; then
        print_error "❌ Missing required environment variables"
        exit 1
    fi

    # Perform restart
    do_restart
    return $?
}

# Execute main function with all arguments
main "$@"
exit $?
