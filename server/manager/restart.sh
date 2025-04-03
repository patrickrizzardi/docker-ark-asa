#!/bin/bash
#
# ARK Server Restart Script
# Gracefully stops and then restarts an ARK server instance
#
# Usage: ./restart.sh [options]
# Options:
#   --clean       : Perform a clean restart (stops and starts the server)
#   --force       : Force restart even if restart is already in progress
#   --help        : Show this help message
#
# =============================================================================

# Enable strict mode
set -eE

# Load common utilities
UTILS_PATH="$MANAGER_DIR/utils"
source "${UTILS_PATH}/common.sh"

# =============================================================================
# CONFIGURATION
# =============================================================================

# Required environment variables for restarting the server
declare -a REQUIRED_VARS=(
    "ARK_DIR"     # ARK installation directory
    "MANAGER_DIR" # Manager scripts directory
)

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Display help message
show_help() {
    print_script_header "ARK Server Restart"

    echo "Usage: $(basename $0) [options]"
    echo ""
    echo "Options:"
    echo "  --clean           : Perform a clean restart (stops and starts the server)"
    echo "  --save-world      : Save the world before restarting"
    echo "  --force           : Force restart even if restart is already in progress"
    echo "  --help            : Show this help message"
    echo ""
    echo "This script performs a controlled restart of the ARK server."
}

# Parse command line arguments
parse_args() {
    FORCE=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
        --force)
            FORCE=1
            shift
            ;;
        --help | -h)
            show_help
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            show_help
            exit 1
            ;;
        esac
    done
}

# Script-specific cleanup function that will be called by common_cleanup
script_cleanup() {
    print_info "Cleaning up restart script resources..."

    # Remove flag files created by this script
    rm -f "$SERVER_SAVE_FLAG" 2>/dev/null || true
}

# =============================================================================
# CORE FUNCTIONS
# =============================================================================

# Create flag files for restart
# For start and stop flags, they will be created by the start and stop scripts
create_restart_flags() {
    # Create restart flag file
    touch "$SERVER_RESTART_FLAG"

    # Create timestamp file for monitoring restart timeouts
    date +%s >"${ARK_DIR}/restart_timestamp.tmp"

    print_info "Created restart flags"
}

# Remove restart flag files
# For start and stop flags, they will be removed by the start and stop scripts
remove_restart_flags() {
    rm -f "$SERVER_RESTART_FLAG" 2>/dev/null || true
    rm -f "${ARK_DIR}/restart_timestamp.tmp" 2>/dev/null || true

    print_info "Removed restart flags"
}

# Perform the restart
do_restart() {
    print_script_header "Restarting ARK Server"

    # Check if a restart is already in progress
    if is_server_restarting && [[ $FORCE_RESTART -eq 0 ]]; then
        print_warning "⚠️ Restart already in progress. Use --force to override."
        return 1
    fi

    # Create restart flag files
    create_restart_flags

    # Perform clean restart if requested, otherwise use signal-based restart
    if [[ $FORCE -eq 1 ]]; then
        print_info "Performing signal-based restart (Force restart)..."

        ark stop --force

        # Wait a bit for the server to stop
        run_with_spinner "sleep 10" "Waiting for server to stop..." 1.0

        # Start the server
        # run_with_spinner "ark start" "Starting server..." 1.0
    else
        print_info "Performing clean restart (stop and start)..."

        # Stop the server
        # Saves happen automatically with the stop command
        run_with_spinner "ark stop" "Stopping server..." 1.0

        # Small delay to ensure everything is stopped
        # sleep 5

        # Start the server
        # run_with_spinner "ark start" "Starting server..." 1.0
    fi

    # Remove restart flags
    remove_restart_flags

    print_success "✅ Restart process completed"
    return 0
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

main() {
    # Parse command line arguments
    parse_args "$@"

    # Check prerequisites
    check_required_env REQUIRED_VARS || exit 1

    # Perform restart
    do_restart

    print_success "✅ Restart completed successfully"
    return 0
}

# Run the main function
main "$@"
