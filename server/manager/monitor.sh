#!/bin/bash
#
# ARK Server Monitor Script
# Monitors the ARK server process and restarts it if it crashes
#
# =============================================================================

# Load environment variables and utilities
source "$(dirname "$0")/common.sh"

# =============================================================================
# CONFIGURATION
# =============================================================================

# Required environment variables for monitoring
declare -a MONITOR_REQUIRED_VARS=(
    "ARK_DIR"     # ARK installation directory
    "MANAGER_DIR" # Manager scripts directory
)

# Optional environment variables
declare -a MONITOR_OPTIONAL_VARS=(
    "LOG_FILE"                     # Main server log file
    "API_LOG_FILE"                 # API log file (if using API)
    "WINE_LOG_FILE"                # Wine debug log file
    "MONITOR_LOG"                  # Monitor log file
    "SYSTEM_INITIAL_STARTUP_DELAY" # Wait time before monitoring starts (seconds)
    "SYSTEM_CHECK_INTERVAL"        # How often to check server (seconds)
    "SYSTEM_RESTART_WAIT"          # How long to wait after restart (seconds)
    "SYSTEM_STALE_LOCK_TIME"       # Minutes before considering a lock stale
    "NETWORK_RCON_PORT"            # RCON port for server status checks (optional)
    "SERVER_ADMIN_PASSWORD"        # Admin password for RCON checks (optional)
    "SYSTEM_UPDATE_CHECK_INTERVAL" # Hours between update checks
    "SYSTEM_MAX_RESTART_ATTEMPTS"  # Maximum restart attempts before giving up
    "SYSTEM_STARTUP_WAIT"          # Time to wait for server to initialize (seconds)
)

# Set default values for optional variables
set_monitor_defaults() {
    # Default values for monitoring
    SYSTEM_INITIAL_STARTUP_DELAY=${SYSTEM_INITIAL_STARTUP_DELAY:-300} # Wait time before monitoring starts (seconds)
    SYSTEM_RESTART_WAIT=${SYSTEM_RESTART_WAIT:-120}                   # How long to wait after restart (seconds)
    SYSTEM_STALE_LOCK_TIME=${SYSTEM_STALE_LOCK_TIME:-30}              # Minutes before considering a lock stale
    SYSTEM_UPDATE_CHECK_INTERVAL=${SYSTEM_UPDATE_CHECK_INTERVAL:-12}  # Hours between update checks (default 12 hours)
    SYSTEM_MAX_RESTART_ATTEMPTS=${SYSTEM_MAX_RESTART_ATTEMPTS:-3}     # Max restart attempts before giving up
    SYSTEM_CHECK_INTERVAL=${SYSTEM_CHECK_INTERVAL:-30}                # How often to check server (seconds)
    SYSTEM_STARTUP_WAIT=${SYSTEM_STARTUP_WAIT:-60}                    # Time to wait for server to initialize (seconds)

    # Set default log file paths if not specified
    LOG_FILE=${LOG_FILE:-"${ARK_DIR}/ShooterGame/Saved/Logs/ShooterGame.log"}
    MONITOR_LOG=${MONITOR_LOG:-"${ARK_DIR}/logs/server_monitor.log"}

    # Create log directory if it doesn't exist
    mkdir -p "$(dirname "$MONITOR_LOG")" 2>/dev/null || true
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Function for cleanup on script exit
cleanup() {
    print_info "Monitor script exiting with code: $?"
    exit 0
}

# Check for restart timeout (nuclear option)
check_restart_timeout() {
    local restart_timestamp_file="${ARK_DIR}/restart_timestamp.tmp"

    # If restart flag doesn't exist, remove timestamp file and return
    if ! flag_exists "restart"; then
        print_warning "⚠️ Restart flag not found, removing timestamp file"
        if [[ -f "$restart_timestamp_file" ]]; then
            rm -f "$restart_timestamp_file"
        fi
        return 0
    fi

    # If timestamp file doesn't exist, create it with current time
    if [[ ! -f "$restart_timestamp_file" ]]; then
        date +%s >"$restart_timestamp_file"
        return 0
    fi

    # Check how long it's been since the restart was initiated
    local start_time=$(cat "$restart_timestamp_file")
    local current_time=$(date +%s)
    local elapsed_time=$((current_time - start_time))

    # If it's been less than 5 minutes (300 seconds), not a timeout yet
    if [[ $elapsed_time -le 300 ]]; then
        return 0
    fi

    # If it's been more than 5 minutes, force aggressive restart
    print_error "❌ CRITICAL: Restart timeout exceeded (${elapsed_time}s)"
    print_warning "⚠️ Forcing aggressive server restart"

    # Kill any running server processes
    ark stop --force || print_error "❌ Failed to forcefully terminate server process"

    # Remove all flag files to ensure clean restart
    remove_flag "restart"
    remove_flag "start"
    remove_flag "save"
    remove_flag "stop"
    rm -f "$restart_timestamp_file" 2>/dev/null || true

    # Wait a moment for processes to terminate
    sleep 5

    # Attempt clean restart
    ark start || print_error "❌ Even aggressive restart failed!"

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
        if ! flag_exists "start"; then
            return 1
        fi

        if [[ "$(get_ark_server_pid)" != "0" ]]; then
            return 1
        fi

        local flag_time=$(get_flag_timestamp "start")
        local current_time=$(date +%s)
        local flag_age=$((current_time - flag_time))

        # If flag is older than 5 minutes but no logs, likely a first-launch crash
        if [[ $flag_age -gt 300 ]]; then
            print_warning "⚠️ Server start flag present but no logs or process found after 5 minutes"
            print_warning "⚠️ This may indicate a first-launch configuration issue"
            return 0
        fi
    fi

    return 1
}

# Handle recovery from first-launch errors
handle_first_launch_recovery() {
    print_script_header "⚙️ First Launch Recovery Procedure"

    print_info "Performing first-launch recovery..."

    # Kill any stuck processes
    print_info "Stopping any running server processes..."
    ark stop --force || print_error "❌ Failed to forcefully terminate server process"

    # Remove flag files
    remove_flag "start"
    remove_flag "restart"

    # Create a marker file to prevent repeated recovery attempts
    create_flag "first_launch_recovery_completed"

    # Wait a moment
    sleep 5

    # Restart the server with special flags if needed
    print_info "Restarting server after recovery..."
    ark start || print_error "❌ Failed to restart after recovery"

    print_success "✅ First-launch recovery procedure completed"
    sleep SYSTEM_STARTUP_WAIT
}

# Function to check if it's time to check for updates
is_update_check_due() {
    local should_display=${1:-"true"} # Whether to display status messages

    # If update checking is disabled, return early
    if [[ -z "$SYSTEM_UPDATE_CHECK_INTERVAL" || "$SYSTEM_UPDATE_CHECK_INTERVAL" == "0" ]]; then
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
    local check_interval_seconds=$((SYSTEM_UPDATE_CHECK_INTERVAL * 3600)) # Convert hours to seconds

    # If not enough time has passed, return early
    if [[ $((current_time - last_check_time)) -le $check_interval_seconds ]]; then
        # Calculate the time until next check
        local time_until_next_check=$((check_interval_seconds - (current_time - last_check_time)))
        local hours=$((time_until_next_check / 3600))
        local minutes=$(((time_until_next_check % 3600) / 60))

        [[ "$should_display" == "true" ]] && print_info "Next update check in ${hours}h ${minutes}m"
        return 1
    fi

    # Time to check for updates
    return 0
}

# Function to check for updates
check_for_updates() {
    local should_display=${1:-"true"} # Whether to display status messages

    # Check if it's time to check for updates
    if ! is_update_check_due "$should_display"; then
        return 1
    fi

    [[ "$should_display" == "true" ]] && print_info "Checking for ARK server updates..."

    # Update the last check time
    echo "$(date +%s)" >"${ARK_DIR}/last_update_check.txt"

    # Call the update script with check-only mode
    if ! ark update --check-only; then
        [[ "$should_display" == "true" ]] && print_success "✅ No update needed"
        return 1
    fi

    [[ "$should_display" == "true" ]] && print_warning "⚠️ Update available! Will perform update on next check."
    return 0
}

# =============================================================================
# MONITORING FUNCTIONS
# =============================================================================

# Function for more advanced server health check
check_server_health() {
    local ark_server_pid=$(get_ark_server_pid)

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

    # Skip RCON check if not configured
    if [[ -z "$RCON_PORT" || -z "$ARK_ADMIN_PASSWORD" ]]; then
        return 0
    fi

    # Only do RCON check occasionally (about once every 10 checks)
    if ((RANDOM % 10 != 0)); then
        return 0
    fi

    print_info "Performing deep RCON health check..."
    # Using the existing rcon.sh script in the manager directory
    local rcon_result=$("${MANAGER_DIR}/rcon.sh" "info" --silent 2>&1)

    if [[ $? -ne 0 || "$rcon_result" == *"RCON_TIMEOUT"* || "$rcon_result" == *"RCON_FAILED"* ]]; then
        print_warning "⚠️ Server unresponsive to RCON - will continue monitoring"
        return 2 # Partial health issue
    fi

    print_success "✅ Server is responsive via RCON"

    # Additional health check: Check online player count vs max players
    local player_info=$("${MANAGER_DIR}/rcon.sh" "listplayers" --silent 2>&1)
    if [[ "$player_info" == *"No Players Connected"* ]]; then
        print_info "No players currently connected"
        return 0
    fi

    # Count the number of players (assuming one player per line)
    local player_count=$(echo "$player_info" | grep -v "No Players Connected" | wc -l)
    print_info "Current online players: $player_count"
    return 0
}

# Function to attempt server restart
restart_server() {
    local restart_attempts=$1
    local max_attempts=$2

    print_warning "⚠️ ARK server process not found! Initiating restart..."
    print_info "Running start script (attempt $restart_attempts of $max_attempts)..."

    if ! "${MANAGER_DIR}/start.sh"; then
        print_error "❌ Failed to restart the server"
        return 1
    fi

    print_success "✅ Server restart initiated successfully"
    return 0
}

# Function to handle when the server is not running
handle_server_not_running() {
    local restart_attempts=$1
    local max_attempts=$2
    local last_restart_time=$3
    local restart_cooldown=$4

    # Check if we're currently starting
    if [[ -f "$SERVER_START_FLAG" ]]; then
        print_info "Server starting flag detected, waiting..."
        return 0
    fi

    # Check if we've exceeded max restart attempts
    local current_time=$(date +%s)
    if [[ $((current_time - last_restart_time)) -le $restart_cooldown ]]; then
        # Not enough time has passed since last restart attempt
        return 1
    fi

    # Reset attempts if cooldown has passed
    if [[ $((current_time - last_restart_time)) -gt $restart_cooldown ]]; then
        restart_attempts=0
    fi

    if [[ $restart_attempts -ge $max_attempts ]]; then
        print_error "❌ Maximum restart attempts ($max_attempts) reached!"
        print_warning "⚠️ Will try again after cooldown period"
        sleep $restart_cooldown
        return 1
    fi

    # Attempt to restart the server
    restart_server $((restart_attempts + 1)) $max_attempts

    # Return updated values through a semi-colon separated string
    echo "$((restart_attempts + 1));$(date +%s)"
    return 0
}

# Function to handle when the server is running
handle_server_running() {
    local ark_server_pid=$1

    print_success "✅ Server running with PID: $ark_server_pid"

    # Perform advanced health check
    check_server_health "$ark_server_pid"

    # Check for updates (only on every 20th cycle to avoid spamming)
    if ((RANDOM % 20 == 0)); then
        check_for_updates
    fi

    return 0
}

# Main monitor loop - separated from setup
monitor_loop() {
    local restart_attempts=0
    local last_restart_time=0
    local restart_cooldown=300 # 5 minutes cooldown between restart attempts

    print_success "✅ Monitor active - checking server every ${SYSTEM_CHECK_INTERVAL} seconds"

    # Main monitoring loop
    while true; do
        # Check for restart timeouts
        check_restart_timeout

        # If the shutdown flag is present, pause monitoring
        if flag_exists "shutdown"; then
            print_info "Server shutdown flag present, monitoring paused"
            sleep $SYSTEM_CHECK_INTERVAL
            continue
        fi

        # If server is updating, wait and skip rest of checks
        if flag_exists "update"; then
            print_info "Server update in progress, waiting..."
            sleep $SYSTEM_CHECK_INTERVAL
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
            sleep $SYSTEM_CHECK_INTERVAL
            continue
        fi

        # Check if the server process is running
        local ark_server_pid=$(get_ark_server_pid)

        if [[ "$ark_server_pid" == "0" ]]; then
            # Handle case when server is not running
            local result=$(handle_server_not_running "$restart_attempts" "$SYSTEM_MAX_RESTART_ATTEMPTS" "$last_restart_time" "$SYSTEM_RESTART_WAIT")
            local status=$?

            if [[ $status -eq 0 && -n "$result" ]]; then
                # Update tracking variables from result
                IFS=';' read -r restart_attempts last_restart_time <<<"$result"
            fi

            # Wait before checking again to give server time to start
            sleep $SYSTEM_RESTART_WAIT
        else
            # Handle case when server is running
            handle_server_running "$ark_server_pid"

            # Reset restart attempts if server is stable
            restart_attempts=0

            # Wait until next check
            sleep $SYSTEM_CHECK_INTERVAL
        fi
    done
}

# Main monitor function
monitor_server() {
    print_script_header "🔍 ARK Server Monitor"
    echo ""

    # Check required environment variables
    check_required_env MONITOR_REQUIRED_VARS || exit 1

    # Check optional environment variables and set defaults
    check_optional_env MONITOR_OPTIONAL_VARS
    set_monitor_defaults

    # Display configuration
    print_info "Initial startup delay: ${SYSTEM_INITIAL_STARTUP_DELAY} seconds"
    print_info "Check interval: ${SYSTEM_CHECK_INTERVAL} seconds"
    print_info "Update check interval: ${SYSTEM_UPDATE_CHECK_INTERVAL} hours"

    # Wait for the server to start up
    print_info "Waiting for server startup..."
    sleep $SYSTEM_INITIAL_STARTUP_DELAY

    # Start the main monitoring loop
    monitor_loop
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
