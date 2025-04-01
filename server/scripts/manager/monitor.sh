#!/bin/bash
#
# ARK Server Monitor Script
# Monitors the ARK server process and restarts it if it crashes
#
# =============================================================================

# Load environment variables and utilities
UTILS_PATH="$MANAGER_DIR/utils"
source "${UTILS_PATH}/colorPrinter.sh"
source "${UTILS_PATH}/processManager.sh"
source "${UTILS_PATH}/envManager.sh"

# =============================================================================
# CONFIGURATION
# =============================================================================

# Required environment variables for monitoring
declare -a MONITOR_REQUIRED_VARS=(
    "ARK_DIR"       # ARK installation directory
    "MANAGER_DIR"   # Manager scripts directory
    "LOG_FILE"      # Main server log file
    "API_LOG_FILE"  # API log file (if using API)
    "WINE_LOG_FILE" # Wine debug log file
    "MONITOR_LOG"   # Monitor log file
)

# Optional environment variables
declare -a MONITOR_OPTIONAL_VARS=(
    "INITIAL_STARTUP_DELAY" # Wait time before monitoring starts (seconds)
    "CHECK_INTERVAL"        # How often to check server (seconds)
    "RESTART_WAIT"          # How long to wait after restart (seconds)
    "STALE_LOCK_TIME"       # Minutes before considering a lock stale
    "RCON_PORT"             # RCON port for server status checks (optional)
    "ARK_ADMIN_PASSWORD"    # Admin password for RCON checks (optional)
    "UPDATE_CHECK_INTERVAL" # Hours between update checks
    "MAX_RESTART_ATTEMPTS"  # Maximum restart attempts before giving up

)

# Optional environment variables with defaults
INITIAL_STARTUP_DELAY=${INITIAL_STARTUP_DELAY:-120}       # Wait time before monitoring starts (seconds)
CHECK_INTERVAL=${CHECK_INTERVAL:-30}                      # How often to check server (seconds)
RESTART_WAIT=${RESTART_WAIT:-60}                          # How long to wait after restart (seconds)
STALE_LOCK_TIME=${STALE_LOCK_TIME:-30}                    # Minutes before considering a lock stale
UPDATE_CHECK_INTERVAL=${UPDATE_CHECK_INTERVAL:-12}        # Hours between update checks (default 12 hours)
MAX_RESTART_ATTEMPTS=${MAX_RESTART_ATTEMPTS:-3}           # Max restart attempts before giving up
RESTART_TIMESTAMP_FILE="${ARK_DIR}/restart_timestamp.tmp" # File to track restart timestamps

# Flag files used for state tracking
SERVER_START_FLAG="${ARK_DIR}/server_starting.flag" # Flag file created during server start
UPDATE_LOCK_FILE="${ARK_DIR}/updating.flag"         # Flag file created during updates
RESTART_FLAG="${ARK_DIR}/restart.flag"              # Flag file for restart in progress
NO_RESTART_FLAG="${ARK_DIR}/stop.flag"              # Flag to prevent automatic restarts

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Create log directory if it doesn't exist
mkdir -p "$(dirname "$MONITOR_LOG")" 2>/dev/null || true

# Function for cleanup on script exit
cleanup() {
    print_info "Monitor script exiting with code: $?"
    exit 0
}

# Function to check if an update is in progress
is_server_updating() {
    if [[ -f "$UPDATE_LOCK_FILE" ]]; then
        # Check if it's a stale lock (more than configured minutes old)
        if [[ $(find "$UPDATE_LOCK_FILE" -mmin +${STALE_LOCK_TIME} -print) ]]; then
            print_warning "⚠️ Found stale update lock, removing it"
            rm -f "$UPDATE_LOCK_FILE"
            return 1
        else
            # Lock exists and is not stale
            return 0
        fi
    fi
    return 1
}

# Check for restart timeout (nuclear option)
check_restart_timeout() {
    # If restart flag exists, check if we've been stuck for too long
    if [[ -f "$RESTART_FLAG" ]]; then
        # If timestamp file doesn't exist, create it with current time
        if [[ ! -f "$RESTART_TIMESTAMP_FILE" ]]; then
            date +%s >"$RESTART_TIMESTAMP_FILE"
            return 0
        fi

        # Otherwise, check how long it's been since the restart was initiated
        local start_time=$(cat "$RESTART_TIMESTAMP_FILE")
        local current_time=$(date +%s)
        local elapsed_time=$((current_time - start_time))

        # If it's been more than 5 minutes (300 seconds), force aggressive restart
        if [[ $elapsed_time -gt 300 ]]; then
            print_error "❌ CRITICAL: Restart timeout exceeded (${elapsed_time}s)"
            print_warning "⚠️ Forcing aggressive server restart"

            # Kill any running server processes
            pkill -9 -f "ArkAscendedServer.exe" >/dev/null 2>&1 || true
            pkill -9 -f "AsaApiLoader.exe" >/dev/null 2>&1 || true

            # Remove all flag files to ensure clean restart
            rm -f "$RESTART_FLAG" 2>/dev/null || true
            rm -f "$SERVER_START_FLAG" 2>/dev/null || true
            rm -f "$RESTART_TIMESTAMP_FILE" 2>/dev/null || true

            # Wait a moment for processes to terminate
            sleep 5

            # Attempt clean restart
            "${MANAGER_DIR}/start.sh" || print_error "❌ Even aggressive restart failed!"
        fi
    else
        # If no restart flag, remove the timestamp file if it exists
        if [[ -f "$RESTART_TIMESTAMP_FILE" ]]; then
            rm -f "$RESTART_TIMESTAMP_FILE"
        fi
    fi

    return 0
}

# Check if a first-launch Wine/MSVCP140.dll error is occurring
check_for_first_launch_error() {
    # Only run this check if we have access to log files
    if [[ -z "$WINE_LOG_FILE" ]] && [[ -z "$LOG_FILE" ]]; then
        return 1
    fi

    # Check Wine logs for MSVCP140.dll errors
    if [[ -n "$WINE_LOG_FILE" ]] && [[ -f "$WINE_LOG_FILE" ]]; then
        if grep -q "err:module:import_dll Loading library MSVCP140.dll.*failed" "$WINE_LOG_FILE"; then
            print_warning "⚠️ Detected MSVCP140.dll loading error (common first launch issue)"
            return 0
        fi
    fi

    # Check main log for startup errors
    if [[ -n "$LOG_FILE" ]] && [[ -f "$LOG_FILE" ]]; then
        if grep -q "Fatal error" "$LOG_FILE" | grep -q "first launch"; then
            print_warning "⚠️ Detected fatal error during first launch"
            return 0
        fi
    fi

    # Check if server process crashed without creating logs
    if [[ -n "$LOG_FILE" ]] && [[ ! -f "$LOG_FILE" ]]; then
        # Check if server was supposed to be running but no logs were created
        if [[ -f "$SERVER_START_FLAG" ]] && [[ "$(get_ark_server_pid)" == "0" ]]; then
            local flag_time=$(stat -c %Y "$SERVER_START_FLAG" 2>/dev/null || echo 0)
            local current_time=$(date +%s)
            local flag_age=$((current_time - flag_time))

            # If flag is older than 5 minutes but no logs, likely a first-launch crash
            if [[ $flag_age -gt 300 ]]; then
                print_warning "⚠️ Server start flag present but no logs or process found after 5 minutes"
                print_warning "⚠️ This may indicate a first-launch configuration issue"
                return 0
            fi
        fi
    fi

    return 1
}

# Handle recovery from first-launch errors
handle_first_launch_recovery() {
    print_header "⚙️ First Launch Recovery Procedure"

    print_info "Performing first-launch recovery..."

    # Kill any stuck processes
    print_info "Stopping any running server processes..."
    pkill -9 -f "ArkAscendedServer.exe" >/dev/null 2>&1 || true
    pkill -9 -f "AsaApiLoader.exe" >/dev/null 2>&1 || true
    pkill -9 -f "wine" >/dev/null 2>&1 || true

    # Remove flag files
    rm -f "$SERVER_START_FLAG" 2>/dev/null || true
    rm -f "$RESTART_FLAG" 2>/dev/null || true

    # Create a marker file to prevent repeated recovery attempts
    touch "${ARK_DIR}/first_launch_recovery_completed"

    # Wait a moment
    sleep 5

    # Restart the server with special flags if needed
    print_info "Restarting server after recovery..."
    "${MANAGER_DIR}/start.sh" || print_error "❌ Failed to restart after recovery"

    print_success "✅ First-launch recovery procedure completed"
    sleep 60 # Give the server time to start
}

# Function to check for updates
check_for_updates() {
    local should_display=${1:-true} # Whether to display status messages

    # Only proceed if UPDATE_CHECK_INTERVAL is set
    if [[ -z "$UPDATE_CHECK_INTERVAL" || "$UPDATE_CHECK_INTERVAL" == "0" ]]; then
        [[ "$should_display" == "true" ]] && print_info "Update checking is disabled"
        return 1
    fi

    # Create the file to store last check time if it doesn't exist
    local last_check_file="${ARK_DIR}/last_update_check.txt"
    if [[ ! -f "$last_check_file" ]]; then
        echo "0" >"$last_check_file"
    fi

    # Read the last check time
    local last_check_time=$(cat "$last_check_file")
    local current_time=$(date +%s)
    local check_interval_seconds=$((UPDATE_CHECK_INTERVAL * 3600)) # Convert hours to seconds

    # Only check if enough time has passed
    if [[ $((current_time - last_check_time)) -gt $check_interval_seconds ]]; then
        [[ "$should_display" == "true" ]] && print_info "Checking for ARK server updates..."

        # Update the last check time
        echo "$current_time" >"$last_check_file"

        # Call the update script with check-only mode if it exists
        if [[ -f "${MANAGER_DIR}/update.sh" ]]; then
            # We only want to check if an update is needed, not actually perform it
            if "${MANAGER_DIR}/update.sh" --check-only; then
                [[ "$should_display" == "true" ]] && print_warning "⚠️ Update available! Will perform update on next check."
                return 0
            else
                [[ "$should_display" == "true" ]] && print_success "✅ No update needed"
                return 1
            fi
        else
            [[ "$should_display" == "true" ]] && print_warning "⚠️ Update script not found at ${MANAGER_DIR}/update.sh"
            return 1
        fi
    else
        # Calculate the time until next check
        local time_until_next_check=$((check_interval_seconds - (current_time - last_check_time)))
        local hours=$((time_until_next_check / 3600))
        local minutes=$(((time_until_next_check % 3600) / 60))

        [[ "$should_display" == "true" ]] && print_info "Next update check in ${hours}h ${minutes}m"
        return 1
    fi
}

# =============================================================================
# MONITORING FUNCTIONS
# =============================================================================

# Function for more advanced server health check
check_server_health() {
    local ark_server_pid=$1

    # Skip health check if no PID provided
    if [[ -z "$ark_server_pid" || "$ark_server_pid" == "0" ]]; then
        return 1
    fi

    # Basic process check
    if ! ps -p "$ark_server_pid" >/dev/null; then
        print_warning "⚠️ Process with PID $ark_server_pid no longer exists"
        return 1
    fi

    # Check CPU usage (high CPU could indicate a frozen server)
    local cpu_usage=$(ps -p "$ark_server_pid" -o %cpu= | awk '{print int($1)}')
    if [[ $cpu_usage -eq 0 ]]; then
        print_warning "⚠️ Server CPU usage is 0% - may be frozen"
        # Don't immediately restart, this could be normal during idle periods
    fi

    # Memory check (extremely high memory could indicate a memory leak)
    local mem_usage=$(ps -p "$ark_server_pid" -o %mem= | awk '{print int($1)}')
    if [[ $mem_usage -gt 95 ]]; then
        print_warning "⚠️ Server memory usage is extremely high: ${mem_usage}%"
        # Only flag as an issue, don't auto-restart
    fi

    # Check if RCON is configured for deeper health check
    if [[ -n "$RCON_PORT" && -n "$ARK_ADMIN_PASSWORD" ]]; then
        # Only do RCON check occasionally (about once every 10 checks)
        if ((RANDOM % 10 == 0)); then
            print_info "Performing deep RCON health check..."
            # Using the existing rcon.sh script in the manager directory
            local rcon_result=$("${MANAGER_DIR}/rcon.sh" "info" --silent 2>&1)

            if [[ $? -eq 0 && "$rcon_result" != *"RCON_TIMEOUT"* && "$rcon_result" != *"RCON_FAILED"* ]]; then
                print_success "✅ Server is responsive via RCON"

                # Additional health check: Check online player count vs max players
                local player_info=$("${MANAGER_DIR}/rcon.sh" "listplayers" --silent 2>&1)
                if [[ "$player_info" == *"No Players Connected"* ]]; then
                    print_info "No players currently connected"
                else
                    # Count the number of players (assuming one player per line)
                    local player_count=$(echo "$player_info" | grep -v "No Players Connected" | wc -l)
                    print_info "Current online players: $player_count"
                fi

                return 0
            else
                print_warning "⚠️ Server unresponsive to RCON - will continue monitoring"
                return 2 # Partial health issue
            fi
        fi
    fi

    # Default return if we didn't perform deep health check
    return 0
}

# Main monitor function (enhanced with more advanced features)
monitor_server() {
    print_header "🔍 ARK Server Monitor"
    echo ""

    # Check required environment variables
    if ! check_env_variables MONITOR_REQUIRED_VARS 0; then
        print_error "❌ Missing required environment variables"
        exit 1
    fi

    # Check optional environment variables
    check_env_variables MONITOR_OPTIONAL_VARS 1

    print_info "Initial startup delay: ${INITIAL_STARTUP_DELAY} seconds"
    print_info "Check interval: ${CHECK_INTERVAL} seconds"
    print_info "Update check interval: ${UPDATE_CHECK_INTERVAL} hours"

    # Wait for the server to start up
    print_info "Waiting for server startup..."
    sleep $INITIAL_STARTUP_DELAY

    print_success "✅ Monitor active - checking server every ${CHECK_INTERVAL} seconds"

    # Initialize restart tracking
    local restart_attempts=0
    local last_restart_time=0
    local restart_cooldown=300 # 5 minutes cooldown between restart attempts

    # Main monitoring loop
    while true; do
        # Check for restart timeouts
        check_restart_timeout

        # Check if the server is running
        local ark_server_pid=$(get_ark_server_pid)

        # If the no_restart flag is present, skip server checks
        if [[ -f "$NO_RESTART_FLAG" ]]; then
            print_info "Server shutdown flag present, monitoring paused"
            sleep $CHECK_INTERVAL
            continue
        fi

        # If server is updating, wait and skip rest of checks
        if is_server_updating; then
            print_info "Server update in progress, waiting..."
            sleep $CHECK_INTERVAL
            continue
        fi

        # Check for first-launch errors
        if check_for_first_launch_error; then
            print_warning "⚠️ Detected first-launch errors, initiating recovery..."

            # Only attempt recovery if we haven't already tried
            if [[ ! -f "${ARK_DIR}/first_launch_recovery_completed" ]]; then
                handle_first_launch_recovery
            else
                print_info "Recovery already attempted once, will not retry automatically"
            fi

            # Skip rest of checks this cycle
            sleep $CHECK_INTERVAL
            continue
        fi

        # Check if the server process is running
        if [[ "$ark_server_pid" == "0" ]]; then
            # No server process found, check if we're currently starting
            if [[ -f "$SERVER_START_FLAG" ]]; then
                print_info "Server starting flag detected, waiting..."
                sleep $CHECK_INTERVAL
                continue
            fi

            # Check if we've exceeded max restart attempts
            local current_time=$(date +%s)
            if [[ $((current_time - last_restart_time)) -gt $restart_cooldown ]]; then
                # Reset attempts if cooldown has passed
                restart_attempts=0
            fi

            if [[ $restart_attempts -ge $MAX_RESTART_ATTEMPTS ]]; then
                print_error "❌ Maximum restart attempts ($MAX_RESTART_ATTEMPTS) reached!"
                print_warning "⚠️ Will try again after cooldown period"
                sleep $restart_cooldown
                restart_attempts=0
                continue
            fi

            # Server is not running and not starting, time to restart
            print_warning "⚠️ ARK server process not found! Initiating restart..."
            restart_attempts=$((restart_attempts + 1))
            last_restart_time=$(date +%s)

            # Attempt to restart the server
            print_info "Running start script (attempt $restart_attempts of $MAX_RESTART_ATTEMPTS)..."
            if "${MANAGER_DIR}/start.sh"; then
                print_success "✅ Server restart initiated successfully"
            else
                print_error "❌ Failed to restart the server"
            fi

            # Wait before checking again to give server time to start
            sleep $RESTART_WAIT
        else
            # Server is running - perform health check
            print_success "✅ Server running with PID: $ark_server_pid"

            # Perform advanced health check
            check_server_health "$ark_server_pid"

            # Check for updates (only on every 20th cycle to avoid spamming)
            if ((RANDOM % 20 == 0)); then
                check_for_updates
            fi

            # Reset restart attempts if server is stable
            restart_attempts=0

            # Wait until next check
            sleep $CHECK_INTERVAL
        fi
    done
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

# Set up trap to call cleanup on exit
trap cleanup EXIT INT TERM

# Start the monitoring process
monitor_server

# This should never be reached due to the infinite loop
exit 0
