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

# Check if restart is already in progress and handle accordingly
check_restart_status() {
    # Skip the check if force flag is provided
    if [[ $FORCE_RESTART -eq 1 ]]; then
        return 0
    fi

    # Check if a restart is already in progress
    if is_server_restarting; then
        print_warning "⚠️ Restart already in progress. Use --force to override."
        return 1
    fi

    return 0
}

# Perform signal-based restart (force restart)
perform_force_restart() {
    print_info "Performing signal-based restart (Force restart)..."

    ark stop --force

    # Wait a bit for the server to stop
    sleep 10

    # Start the server
    ark start

    return $?
}

# Perform clean restart (stop and start)
perform_clean_restart() {
    print_info "Performing clean restart (stop and start)..."

    # Stop the server
    # Saves happen automatically with the stop command
    ark stop
    local stop_result=$?

    if [[ $stop_result -ne 0 ]]; then
        print_error "❌ Failed to stop the server"
        return 1
    fi

    # Small delay to ensure everything is stopped
    sleep 5

    # Start the server
    ark start
    local start_result=$?

    if [[ $start_result -ne 0 ]]; then
        print_error "❌ Failed to start the server"
        return 1
    fi

    return 0
}

# Perform the restart
do_restart() {
    print_script_header "Restarting ARK Server"

    # Check if restart is already in progress
    if ! check_restart_status; then
        return 1
    fi

    # Create restart flag files
    create_restart_flags

    # Choose restart method based on force flag
    local restart_result=0
    if [[ $FORCE -eq 1 ]]; then
        perform_force_restart
        restart_result=$?
    else
        perform_clean_restart
        restart_result=$?
    fi

    # Remove restart flags
    remove_restart_flags

    if [[ $restart_result -ne 0 ]]; then
        print_error "❌ Restart process failed"
        return 1
    fi

    print_success "✅ Restart process completed"
    return 0
}

# Function for cleanup on script exit
cleanup() {
    local exit_code=$?

    # Remove server start flag
    remove_restart_flags

    print_info "Restart script exiting with code: $exit_code"
    exit $exit_code
}

# Set up trap to call cleanup on exit
trap cleanup EXIT INT TERM

# =============================================================================
# MAIN EXECUTION
# =============================================================================

main() {
    # Parse command line arguments
    parse_args "$@"

    # Check prerequisites
    check_required_env REQUIRED_VARS || exit 1

    # Perform restart
    if ! do_restart; then
        print_error "❌ Restart failed"
        exit 1
    fi

    print_success "✅ Restart completed successfully"
    return 0
}

# Run the main function
main "$@"
