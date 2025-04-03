#!/bin/bash
#
# ARK Server Stop Script
# Gracefully stops a running ARK server instance
#
# Usage: ./stop.sh [options]
# Options:
#   --force         Skip player checks and force server shutdown
#   --save-only     Only save the world, don't shut down the server
#   --countdown <minutes>  Use a countdown timer before shutdown
#   --restart       Indicate this is a restart operation (changes messages)
#   --help          Display this help message
#
# =============================================================================

# Load environment variables and utilities
UTILS_PATH="$MANAGER_DIR/utils"
source "${UTILS_PATH}/common.sh"

# =============================================================================
# CONFIGURATION
# =============================================================================

# Required environment variables for stopping the server
declare -a REQUIRED_VARS=(
    "SERVER_ADMIN_PASSWORD"   # Admin password for RCON
    "NETWORK_RCON_PORT"       # RCON port for remote commands
    "SYSTEM_SHUTDOWN_TIMEOUT" # Maximum time to wait for shutdown
)

# Optional environment variables
declare -a OPTIONAL_VARS=(
    "SYSTEM_SHUTDOWN_WARNING_TIME" # Default countdown minutes before shutdown
)

# Optional variables with defaults
SYSTEM_SHUTDOWN_WARNING_TIME=${SYSTEM_SHUTDOWN_WARNING_TIME:-5}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Function to check if save is complete by examining logs
save_complete_check() {
    local log_file="${ARK_DIR}/ShooterGame/Saved/Logs/ShooterGame.log"

    if [ ! -f "$log_file" ]; then
        print_warning "⚠️ Server log file not found"
        return 1
    fi

    if tail -n 20 "$log_file" | grep -q "World Save Complete"; then
        return 0
    else
        return 1
    fi
}

# Function to check if server has stopped properly by examining logs
server_stopped_check() {
    local log_file="${ARK_DIR}/ShooterGame/Saved/Logs/ShooterGame.log"

    if [ ! -f "$log_file" ]; then
        print_warning "⚠️ Server log file not found"
        return 1
    fi

    if tail -n 30 "$log_file" | grep -qi "server.*stopped\|exit.*success\|logfile.*closed"; then
        return 0
    else
        return 1
    fi
}

# Function to create shutdown flag file
create_shutdown_flag() {
    echo "$(date) - Server shutdown initiated by PID $$" >"$SHUTDOWN_COMPLETE_FLAG"
    print_success "✅ Created shutdown flag: $SERVER_SHUTDOWN_COMPLETE_FLAG"
}

# Function to clean up any remaining processes and resources
cleanup_processes() {
    print_info "Cleaning up any remaining processes..."

    # Kill any remaining wine processes
    pkill -9 -f "wine" >/dev/null 2>&1 || true
    pkill -9 -f "wineserver" >/dev/null 2>&1 || true

    # Clean temporary files
    print_info "Cleaning temporary files..."
    rm -rf "${STEAM_DIR}/Steam/logs"/* 2>/dev/null || true
    rm -rf "${STEAM_DIR}/Steam/appcache/httpcache"/* 2>/dev/null || true
    rm -rf /tmp/SteamCMD_* 2>/dev/null || true

    print_success "✅ Cleanup completed"
}

# =============================================================================
# SERVER MANAGEMENT FUNCTIONS
# =============================================================================

# Check for connected players
check_connected_players() {
    local force_flag="$1"

    if [[ "$force_flag" == "--force" ]]; then
        print_warning "Force flag detected - skipping player check"
        return 0
    fi

    print_info "Checking for connected players..."

    # Get player count from the listPlayers.sh script
    local player_count=$(ark rcon listPlayers --silent)
    local res=$?

    if [[ $res -ne 0 ]]; then
        print_error "❌ Failed to check connected players"

        if [[ "$force_flag" == "--force" ]]; then
            print_warning "Force flag detected - proceeding with shutdown anyway"
            return 0
        else
            print_error "❌ Cannot stop server without confirming player count"
            print_info "Use --force to override this check"
            return 1
        fi
    fi

    # Check if players are connected
    if [[ $player_count -gt 0 ]]; then
        print_warning "⚠️ Found $player_count connected players"

        print_info "To force shutdown with connected players, use --force"
        return 1
    else
        print_success "✅ No connected players detected"
    fi

    return 0
}

# Save world data with verification from logs
save_world_data() {
    local force_flag="$1"

    if [[ "$force_flag" == "--force" ]]; then
        print_warning "Force flag detected - skipping save check"
        return 0
    fi

    print_info "Saving world data..."

    # Send the save command via RCON
    if ! ark rcon save --silent; then
        print_error "❌ Failed to send save command"

        if [[ "$force_flag" == "--force" ]]; then
            print_warning "⚠️ Continuing with shutdown may result in data loss"
            print_warning "Force flag detected - proceeding with shutdown anyway"
            return 0
        else
            print_error "❌ Cannot stop server without saving world"
            print_info "Use --force to override this check"
            return 1
        fi
    fi

    # Wait for save to complete by checking logs
    print_info "Waiting for save to complete..."
    local save_wait=0
    local max_save_wait=60 # 1 minute max wait for save

    while ! save_complete_check && [ $save_wait -lt $max_save_wait ]; do
        show_spinner "Waiting for world save to complete... (${save_wait}s/${max_save_wait}s)"
        sleep 2
        save_wait=$((save_wait + 2))
    done
    echo "" # Add a newline after the spinner

    if [ $save_wait -lt $max_save_wait ]; then
        print_success "✅ World save completed successfully"
        return 0
    else
        print_warning "⚠️ World save timed out"
        print_error "❌ Cannot confirm world save completed"
        print_info "Use --force to override this check"
        return 1

    fi
}

# Send shutdown command and verify from logs
send_shutdown_command() {
    print_info "Sending shutdown command to server..."

    if ark rcon doExit --silent; then
        print_success "✅ Shutdown command sent successfully"
        return 0
    else
        print_error "❌ Failed to send shutdown command"
        print_warning "Server might be offline or not responding to RCON commands"
        return 1
    fi
}

# Wait for server process to terminate with visual feedback
wait_for_server_shutdown() {
    local pid=$1
    local timeout=$SYSTEM_SHUTDOWN_TIMEOUT

    print_info "Waiting up to ${timeout} seconds for server to shut down..."

    local timer=0
    local check_interval=2

    # First check logs for server stopped message
    while [[ $timer -lt $timeout ]]; do
        show_spinner "Waiting for server shutdown confirmation... (${timer}s/${timeout}s)"

        if server_stopped_check; then
            echo "" # Add a newline after the spinner
            print_success "✅ Server shutdown confirmed in logs"

            # Give the process a moment to actually terminate
            sleep 3

            if ! ps -p $pid >/dev/null 2>&1; then
                print_success "✅ Server process terminated"
                return 0
            fi

            # If we saw the shutdown in logs but process is still running,
            # wait a bit longer in case it's doing cleanup
            local extra_wait=0
            local max_extra_wait=20

            while [[ $extra_wait -lt $max_extra_wait ]]; do
                show_spinner "Server shutdown confirmed but process still exists, waiting... (${extra_wait}s/${max_extra_wait}s)"

                if ! ps -p $pid >/dev/null 2>&1; then
                    echo "" # Add a newline after the spinner
                    print_success "✅ Server process terminated after cleanup"
                    return 0
                fi

                sleep 2
                extra_wait=$((extra_wait + 2))
            done

            echo "" # Add a newline after the spinner
            print_warning "⚠️ Server shutdown confirmed in logs but process still exists"
            break
        fi

        # Also check if the process has terminated directly
        if ! ps -p $pid >/dev/null 2>&1; then
            echo "" # Add a newline after the spinner
            print_success "✅ Server process terminated"
            return 0
        fi

        sleep $check_interval
        timer=$((timer + check_interval))
    done

    echo "" # Add a newline after the spinner
    print_error "❌ Server did not stop within ${timeout} seconds"
    return 1
}

# Force kill the server process with cleanup
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
            show_spinner "Waiting for process to terminate after SIGTERM... (${timer}s/${timeout}s)"

            if ! ps -p $pid >/dev/null 2>&1; then
                echo "" # Add a newline after the spinner
                print_success "✅ Server process terminated gracefully with SIGTERM"
                return 0
            fi

            sleep 1
            timer=$((timer + 1))
        done
        echo "" # Add a newline after the spinner
    fi

    # If SIGTERM didn't work, use SIGKILL
    print_warning "⚠️ SIGTERM did not work, using SIGKILL..."
    if kill -9 $pid >/dev/null 2>&1; then
        print_success "✅ Server process forcefully terminated with SIGKILL"

        # Also kill any other related processes
        cleanup_processes

        return 0
    else
        print_error "❌ Failed to forcefully terminate server process"
        return 1
    fi
}

# Function to perform a countdown with player notifications
perform_countdown() {
    local minutes=$1
    local is_restart=$2

    # Determine message type based on restart flag
    local message="Server shutting down in"
    if [[ "$is_restart" == "true" ]]; then
        message="Server restarting in"
    fi

    print_info "Starting ${minutes}-minute countdown before shutdown..."

    # Initial notification
    ./rcon.sh "ServerChat ${message} ${minutes} minute(s)" --silent

    # Calculate total seconds
    local total_seconds=$((minutes * 60))
    local seconds_remaining=$total_seconds

    # Track when we last sent a notification to avoid duplicates
    local last_notification_time=$seconds_remaining
    local last_minute=-1

    # Main countdown loop
    while [ $seconds_remaining -gt 0 ]; do
        local minutes_remaining=$((seconds_remaining / 60))
        local seconds_in_minute=$((seconds_remaining % 60))

        # Only send notifications at specific intervals
        local should_notify=false

        # At 5-minute intervals when > 5 minutes
        if [ $minutes_remaining -ge 5 ] && [ $seconds_in_minute -eq 0 ] && [ $((minutes_remaining % 5)) -eq 0 ] && [ $minutes_remaining -ne $last_minute ]; then
            should_notify=true
        # At the 3 minute mark
        elif [ $minutes_remaining -eq 3 ] && [ $seconds_in_minute -eq 0 ] && [ $minutes_remaining -ne $last_minute ]; then
            should_notify=true
        # At the 1 minute mark
        elif [ $minutes_remaining -eq 1 ] && [ $seconds_in_minute -eq 0 ] && [ $minutes_remaining -ne $last_minute ]; then
            should_notify=true
        # At the 30 second mark
        elif [ $minutes_remaining -eq 0 ] && [ $seconds_in_minute -eq 30 ]; then
            should_notify=true
        # At the 10 second mark and counting down from 10 to 1
        elif [ $minutes_remaining -eq 0 ] && [ $seconds_in_minute -le 10 ] && [ $seconds_in_minute -gt 0 ]; then
            should_notify=true
        fi

        # Send notification if needed
        if [ "$should_notify" = "true" ]; then
            last_minute=$minutes_remaining

            # Format the time message
            local time_msg=""
            if [ $minutes_remaining -gt 0 ]; then
                time_msg="${minutes_remaining} minute(s)"
            else
                time_msg="${seconds_in_minute} second(s)"
            fi

            # Send the message via RCON
            ./rcon.sh "ServerChat ${message} ${time_msg}" --silent

            # Print to console
            print_info "Notified players: ${message} ${time_msg}"
        fi

        # Display countdown progress
        show_spinner "Countdown: ${minutes_remaining}m ${seconds_in_minute}s remaining"

        sleep 1
        ((seconds_remaining--))
    done

    echo "" # Add a newline after the spinner
    print_success "✅ Countdown completed"

    # Final notification
    if [[ "$is_restart" == "true" ]]; then
        ./rcon.sh "ServerChat Server is restarting NOW!" --silent
    else
        ./rcon.sh "ServerChat Server is shutting down NOW!" --silent
    fi

    return 0
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

# Parse arguments
parse_arguments() {
    FORCE_FLAG=""
    SAVE_ONLY="no"
    COUNTDOWN="no"
    COUNTDOWN_MINUTES=$SYSTEM_SHUTDOWN_WARNING_TIME
    IS_RESTART="false"

    while [[ $# -gt 0 ]]; do
        case "$1" in
        --force)
            FORCE_FLAG="--force"
            shift
            ;;
        --save-only)
            SAVE_ONLY="yes"
            shift
            ;;
        --countdown)
            COUNTDOWN="yes"
            # Check if next argument is a number for countdown minutes
            if [[ $# -gt 1 && "$2" =~ ^[0-9]+$ ]]; then
                COUNTDOWN_MINUTES="$2"
                shift
            fi
            shift
            ;;
        --restart)
            IS_RESTART="true"
            shift
            ;;
        --help)
            echo "Usage: ./stop.sh [options]"
            echo "Options:"
            echo "  --force         Skip player checks and force server shutdown"
            echo "  --save-only     Only save the world, don't shut down the server"
            echo "  --countdown <minutes>  Use a countdown timer before shutdown (default: $SYSTEM_SHUTDOWN_WARNING_TIME)"
            echo "  --restart       Indicate this is a restart operation (changes messages)"
            echo "  --help          Display this help message"
            exit 0
            ;;
        *)
            print_warning "⚠️ Unknown option: $1"
            shift
            ;;
        esac
    done
}

# Main function
main() {
    # Use common.sh function to print header
    print_script_header "🛑 ARK Server Shutdown"

    # Parse command-line arguments
    parse_arguments "$@"

    # Check required environment variables
    check_required_env REQUIRED_VARS || exit 1

    # Check optional environment variables
    check_optional_env OPTIONAL_VARS || exit 1

    print_info "Environment variables checked"

    # Check if server is running
    print_info "Checking server status..."
    local ark_server_pid=$(get_ark_server_pid)
    if [[ "$ark_server_pid" == "0" ]]; then
        print_warning "⚠️ No ARK server process found"
        exit 0
    fi

    print_success "✅ Found ARK server process with PID: $ark_server_pid"

    # When using force flag, skip all checks and go straight to shutdown
    if [[ "$FORCE_FLAG" == "--force" ]]; then
        print_warning "⚠️ Force flag detected - skipping player check and world save"

        # Still try to save the world
        print_info "Attempting world save before force shutdown..."
        ./rcon.sh "SaveWorld" --silent

        # Give it a moment to try to save
        sleep 5

        if force_shutdown $ark_server_pid; then
            create_shutdown_flag
            print_success "🎮 ARK server has been forcefully stopped"
            exit 0
        else
            print_error "❌ Failed to force kill the server"
            exit 1
        fi
    fi

    # Check for connected players
    if ! check_connected_players "$FORCE_FLAG"; then
        exit 1
    fi

    # If countdown is enabled, perform countdown with notifications
    if [[ "$COUNTDOWN" == "yes" ]]; then
        perform_countdown $COUNTDOWN_MINUTES $IS_RESTART
    fi

    # Save world data
    if ! save_world_data "$FORCE_FLAG"; then
        exit 1
    fi

    # If save-only mode, exit here
    if [[ "$SAVE_ONLY" == "yes" ]]; then
        print_success "✅ World saved successfully, not stopping server (--save-only was specified)"
        exit 0
    fi

    # Create a shutdown flag file to indicate shutdown is in progress
    create_shutdown_flag

    # Send shutdown command
    if send_shutdown_command; then
        # Wait for server to shut down gracefully
        if wait_for_server_shutdown $ark_server_pid; then
            cleanup_processes
            print_success "🎮 ARK server has been gracefully stopped"
            exit 0
        else
            # If graceful shutdown times out, ask for force kill
            print_warning "⚠️ Server did not respond to shutdown command within timeout period"

            echo ""
            print_info "Would you like to force kill the server? [y/N]"
            read -n 1 -r
            echo ""

            if [[ $REPLY =~ ^[Yy]$ ]]; then
                if force_shutdown $ark_server_pid; then
                    cleanup_processes
                    print_success "🎮 ARK server has been forcefully stopped"
                    exit 0
                else
                    print_error "❌ Failed to force kill the server"
                    exit 1
                fi
            else
                print_warning "⚠️ Server shutdown aborted by user"
                exit 1
            fi
        fi
    else
        # If shutdown command fails, offer force kill option
        echo ""
        print_info "Would you like to force kill the server? [y/N]"
        read -n 1 -r
        echo ""

        if [[ $REPLY =~ ^[Yy]$ ]]; then
            if force_shutdown $ark_server_pid; then
                cleanup_processes
                print_success "🎮 ARK server has been forcefully stopped"
                exit 0
            else
                print_error "❌ Failed to force kill the server"
                exit 1
            fi
        else
            print_warning "⚠️ Server shutdown aborted by user"
            exit 1
        fi
    fi
}

# Execute the main function with all arguments
main "$@"
