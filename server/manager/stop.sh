#!/bin/bash
#
# ARK Server Stop Script
# Gracefully stops a running ARK server instance
#
# Usage: ./stop.sh [options]
# Options:
#   --force         Skip player checks and force server shutdown
#   --help          Display this help message
#
# =============================================================================

# Load utilities
source "$MANAGER_DIR/utils/common.sh"

# =============================================================================
# CONFIGURATION
# =============================================================================

# Required environment variables
declare -a REQUIRED_VARS=(
    "SERVER_ADMIN_PASSWORD" # Admin password for RCON
    "NETWORK_RCON_PORT"     # RCON port for remote commands
)

# Optional environment variables
declare -a OPTIONAL_VARS=(
    "SYSTEM_SHUTDOWN_TIMEOUT" # Maximum time to wait for shutdown
    "SYSTEM_WARNING_TIME"     # Default countdown minutes before shutdown
)

# Set default values for optional variables
set_default_values() {
    SYSTEM_WARNING_TIME=${SYSTEM_WARNING_TIME:-2}
    SYSTEM_SHUTDOWN_TIMEOUT=${SYSTEM_SHUTDOWN_TIMEOUT:-30}
}

# =============================================================================
# FUNCTIONS
# =============================================================================

# Force shutdown ARK server and cleanup processes
force_shutdown() {
    local pid=$1
    print_warning "⚠️ Forcing server shutdown..."

    # Try SIGTERM first for a cleaner shutdown
    print_info "Sending SIGTERM to process $pid..."
    if kill -15 $pid >/dev/null 2>&1; then
        # Wait a short time to see if SIGTERM works
        local timer=0
        local timeout=10

        while [[ $timer -lt $timeout ]]; do
            loading "Waiting for process to terminate after SIGTERM... (${timer}s/${timeout}s)"
            if ! ps -p $pid >/dev/null 2>&1; then
                echo "" # Add newline after spinner
                print_success "✅ Server process terminated gracefully with SIGTERM"
                return 0
            fi
            sleep 1
            timer=$((timer + 1))
        done
        echo "" # Add newline after spinner
    fi

    # If SIGTERM didn't work, use SIGKILL and kill related processes
    print_warning "⚠️ SIGTERM did not work, using SIGKILL..."

    # Kill the main process and all related processes
    kill -9 $pid >/dev/null 2>&1
    pkill -9 -f "ArkAscendedServer.exe" >/dev/null 2>&1
    pkill -9 -f "AsaApiLoader.exe" >/dev/null 2>&1

    # Be more specific with wine processes - only kill wine processes related to ARK
    pkill -9 -f "wine.*ArkAscendedServer|wine.*AsaApiLoader" >/dev/null 2>&1

    # Add a success message after SIGKILL
    print_success "✅ Server forcefully terminated with SIGKILL"

    # Clean up temporary files
    rm -rf "${STEAM_DIR}/Steam/logs"/* 2>/dev/null || true
    rm -rf "${STEAM_DIR}/Steam/appcache/httpcache"/* 2>/dev/null || true
    rm -rf /tmp/SteamCMD_* 2>/dev/null || true

    print_success "✅ Server process forcefully terminated"
    return 0
}

# Send countdown notifications to players
notify_countdown() {
    local minutes=$1
    print_info "Starting ${minutes}-minute countdown before shutdown..."

    # Initial notification
    ark rcon "ServerChat Server shutdown in ${minutes} minutes" --silent

    # Full minutes notifications
    for ((i = minutes; i > 0; i--)); do
        sleep 60
        ark rcon "ServerChat Server shutdown in ${i} minute(s)" --silent
        print_info "Notified players: ${i} minute(s) remaining"
    done

    # Final countdown in seconds
    ark rcon "ServerChat Server shutting down in 30 seconds" --silent
    sleep 20
    ark rcon "ServerChat Server shutting down in 10 seconds" --silent
    sleep 5

    # Final 5-second countdown
    for ((i = 5; i > 0; i--)); do
        ark rcon "ServerChat ${i}" --silent
        sleep 1
    done

    ark rcon "ServerChat Server shutting down NOW!" --silent
    print_success "✅ Countdown completed"
}

# Save world data
save_world() {
    print_info "Saving world data..."

    # Send save command via RCON
    if ! ark rcon save --silent; then
        print_warning "⚠️ Failed to send save command"
        return 1
    fi

    print_info "Waiting for save to complete..."
    local save_wait=0
    local max_wait=30

    # Simple wait to allow save to complete
    while ((save_wait < max_wait)); do
        loading "Waiting for world save to complete... (${save_wait}s/${max_wait}s)"
        sleep 2
        save_wait=$((save_wait + 2))
    done
    echo "" # Add newline after spinner

    print_success "✅ World save completed"
    return 0
}

# Perform graceful shutdown
graceful_shutdown() {
    local pid=$1

    # Check for connected players
    print_info "Checking for connected players..."
    local player_info=$(capture_all_output ark rcon listPlayers --silent)

    # If there are errors or rcon is not responding, force shutdown
    if contains "$player_info" "with exit code: 1" || contains "$player_info" "failed" || contains "$player_info" "error" || contains "$player_info" "connection refused" || contains "$player_info" "not responding" || contains "$player_info" "RCON timeout"; then
        print_warning "⚠️ RCON command failed, check server logs for more information"
        force_shutdown $pid
        return $?
    fi

    if does_not_contain "$player_info" "No Players Connected"; then
        print_info "Players are connected, starting countdown"
        notify_countdown $SYSTEM_WARNING_TIME
    else
        print_info "No players connected, proceeding with shutdown"
    fi

    # Save world data
    save_world

    # Send shutdown command
    print_info "Sending shutdown command to server..."
    ark rcon doExit --silent

    # Wait for server to shut down
    print_info "Waiting for server to shut down..."
    local timer=0

    while ((timer < SYSTEM_SHUTDOWN_TIMEOUT)); do
        loading "Waiting for server to shut down... (${timer}s/${SYSTEM_SHUTDOWN_TIMEOUT}s)"

        if ! ps -p $pid >/dev/null 2>&1; then
            echo "" # Add newline after spinner
            print_success "✅ Server process terminated"
            return 0
        fi

        sleep 2
        timer=$((timer + 2))
    done

    echo "" # Add newline after spinner
    print_warning "⚠️ Server did not shut down gracefully within timeout"
    print_info "Proceeding with forced shutdown..."

    # Fall back to force shutdown if graceful shutdown fails
    force_shutdown $pid
    return $?
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

# Parse command line arguments
parse_args() {
    FORCE_FLAG=""

    for arg in "$@"; do
        case "$arg" in
        --force)
            FORCE_FLAG="--force"
            ;;
        --help)
            echo "Usage: ./stop.sh [options]"
            echo "Options:"
            echo "  --force         Skip player checks and force server shutdown"
            echo "  --help          Display this help message"
            exit 0
            ;;
        *)
            print_warning "⚠️ Unknown option: $arg"
            ;;
        esac
    done
}

# Main function
main() {

    # Print header
    print_script_header "🛑 ARK Server Shutdown"

    # Parse arguments
    parse_args "$@"

    # Check required environment variables
    check_required_env REQUIRED_VARS || exit 1
    check_optional_env OPTIONAL_VARS
    set_default_values

    # Check if server is running
    print_info "Checking server status..."
    local ark_server_pid=$(get_ark_server_pid)

    if [[ "$ark_server_pid" == "0" ]]; then
        print_warning "⚠️ No ARK server process found"
        exit 0
    fi

    print_success "✅ Found ARK server process with PID: $ark_server_pid"

    # Create shutdown flag
    create_flag "shutdown"

    # Two clear paths: force or graceful
    if [[ "$FORCE_FLAG" == "--force" ]]; then
        # Force path - aggressive shutdown
        force_shutdown $ark_server_pid
    else
        # Normal path - graceful shutdown with notifications
        graceful_shutdown $ark_server_pid
    fi

    print_success "🎮 ARK server has been stopped"
    return 0
}

# Execute the script
main "$@"
