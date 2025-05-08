#!/bin/bash
#
# ARK Server Start Script
# Unified script to start either the standard server or API server
#
# Usage: ./start.sh [options]
# Options:
#   server|api           Specify server type to start (default: server)
#   --help               Display this help message
#
# =============================================================================

# Load environment variables and utilities
source "$MANAGER_DIR/utils/common.sh"

# =============================================================================
# CONFIGURATION
# =============================================================================

# Define required and optional environment variables for server start
declare -a REQUIRED_VARS=(
    "ARK_SAVE_DIR"           # ARK installation directory
    "STEAM_COMPAT_DATA_PATH" # Steam compatibility data path
    "WINE_LOG_FILE"          # Wine log file location

)

# Define optional environment variables with default values
declare -a OPTIONAL_VARS=(
    "SERVER_MAP"                  # Map to run
    "SERVER_SESSION_NAME"         # Server session name
    "SERVER_PASSWORD"             # Server password
    "SERVER_ADMIN_PASSWORD"       # Admin password
    "SERVER_CLUSTER_ID"           # Cluster ID
    "NETWORK_SERVER_PORT"         # Server port
    "NETWORK_QUERY_PORT"          # Query port
    "NETWORK_RCON_PORT"           # RCON port
    "GAMEPLAY_MAX_PLAYERS"        # Maximum number of players
    "GAMEPLAY_BATTLEYE"           # BattlEye anti-cheat
    "GAMEPLAY_MODS"               # Mods to load
    "GAMEPLAY_EXTRA_OPTIONS"      # Extra server options
    "GAMEPLAY_EXTRA_DASH_OPTIONS" # Extra dash options
    "SYSTEM_STARTUP_TIMEOUT"      # Timeout for server startup before it is considered failed
    "SYSTEM_STARTUP_WAIT"         # Time to wait for server to initialize before starting the countdown to check if the server is running
    "API_ENABLED"                 # API server enabled
    "API_PLUGINS"                 # API plugins
)

# Set default values for optional variables
set_default_values() {
    # Server variables
    SERVER_MAP=${SERVER_MAP:-"TheIsland_WP"}
    SERVER_SESSION_NAME=${SERVER_SESSION_NAME:-"ARK Server"}
    SERVER_PASSWORD=${SERVER_PASSWORD:-""}
    SERVER_ADMIN_PASSWORD=${SERVER_ADMIN_PASSWORD:-""}

    # Network variables
    NETWORK_SERVER_PORT=${NETWORK_SERVER_PORT:-7777}
    NETWORK_QUERY_PORT=${NETWORK_QUERY_PORT:-27015}
    NETWORK_RCON_PORT=${NETWORK_RCON_PORT:-27020}

    # Gameplay variables
    GAMEPLAY_MAX_PLAYERS=${GAMEPLAY_MAX_PLAYERS:-70}
    GAMEPLAY_BATTLEYE=${GAMEPLAY_BATTLEYE:-"true"}

    # System variables
    SYSTEM_STARTUP_TIMEOUT=${SYSTEM_STARTUP_TIMEOUT:-300}
    SYSTEM_STARTUP_WAIT=${SYSTEM_STARTUP_WAIT:-60}

    # API variables
    API_ENABLED=${API_ENABLED:-"false"}
    API_PLUGINS=${API_PLUGINS:-""}
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Function to verify server has started successfully
verify_server_started() {
    local timeout=$1
    local check_interval=5
    local elapsed=0

    print_info "Verifying server startup (timeout: ${timeout}s)..."

    while [ $elapsed -lt $timeout ]; do
        # Check for server process
        local ark_server_pid=$(get_ark_server_pid)
        if does_not_equal "$ark_server_pid" "0"; then
            # Check if the server is actually responsive using RCON
            if is_not_empty "$NETWORK_RCON_PORT" && is_not_empty "$SERVER_ADMIN_PASSWORD"; then
                loading "Checking server responsiveness via RCON... (${elapsed}s/${timeout}s)"
                local rcon_output=$(capture_all_output ark rcon info --silent)
                local rcon_status=$?

                if equals "$rcon_status" "0" && does_not_contain "$rcon_output" "RCON_TIMEOUT" && does_not_contain "$rcon_output" "RCON_FAILED"; then
                    echo "" # Add a newline after the spinner
                    print_success "✅ Server verified as responsive via RCON"
                    return 0
                fi
            else
                # If RCON is not available, just check if process exists

                # Check if server is listening on its port
                loading "Checking if server is listening on port ${SERVER_PORT}... (${elapsed}s/${timeout}s)"

                if ss -tuln | grep -q ":${SERVER_PORT}"; then
                    echo "" # Add a newline after the spinner
                    print_success "✅ Server verified as listening on port ${SERVER_PORT}"
                    return 0
                fi

            fi
        fi

        # Server not yet fully started, wait and try again
        loading "Waiting for server to start... (${elapsed}s/${timeout}s)"
        sleep $check_interval
        elapsed=$((elapsed + check_interval))
    done

    echo "" # Add a newline after the spinner
    print_error "❌ Server failed to start within ${timeout} seconds"
    return 1
}

# Function to get the most recent log file matching a pattern
get_most_recent_log() {
    local log_pattern="$1"

    # If pattern doesn't contain wildcards, just return it if it exists
    if [[ "$log_pattern" != *"*"* ]]; then
        if [ -f "$log_pattern" ]; then
            echo "$log_pattern"
        fi
        return
    fi

    # Find all files matching the pattern
    local matching_files=($log_pattern)

    # Check if any files were found
    if [ ${#matching_files[@]} -eq 0 ] || [ "${matching_files[0]}" = "$log_pattern" ]; then
        return
    fi

    # Find the most recent file
    local most_recent=""
    local latest_time=0

    for file in "${matching_files[@]}"; do
        if [ -f "$file" ]; then
            local file_time=$(stat -c %Y "$file")
            if [ "$file_time" -gt "$latest_time" ]; then
                latest_time=$file_time
                most_recent=$file
            fi
        fi
    done

    echo "$most_recent"
}

# Function to check logs for startup errors
check_logs_for_errors() {
    local log_pattern="$1"

    # Get the most recent log file matching the pattern
    local recent_log=$(get_most_recent_log "$log_pattern")

    if [ -z "$recent_log" ]; then
        print_warning "⚠️ No log files found matching pattern: $log_pattern"
        return 0 # Return success as this isn't critical
    fi

    print_info "Checking entire log file: $recent_log"

    # Common error patterns to look for - scan entire file (no tail limit)
    local errors=$(grep -i "error\|failed\|crash\|exception\|fatal\|cannot\|unable\|denied\|terminated\|segmentation fault" "$recent_log")

    if [ -n "$errors" ]; then
        print_warning "⚠️ Potential issues detected in log:"
        echo "$errors" | head -20 # Show more lines since we're checking the entire file

        # Look for specific known issues
        if grep -i "steam_api64.dll" "$recent_log" >/dev/null; then
            print_warning "⚠️ Steam API issue detected - may indicate Steam initialization failure"
        fi

        if grep -i "battleye" "$recent_log" >/dev/null; then
            print_warning "⚠️ BattlEye issue detected - consider using -NoBattlEye option"
        fi

        if grep -i "permission denied" "$recent_log" >/dev/null; then
            print_warning "⚠️ Permission issues detected - check file permissions"
        fi

        return 1
    fi

    print_success "✅ No major errors found in logs"
    return 0
}

# Function for cleanup on script exit
cleanup() {
    local exit_code=$?

    # Remove server start flag
    remove_flag "start"

    print_info "Start script exiting with code: $exit_code"
    exit $exit_code
}

# =============================================================================
# SERVER MANAGEMENT FUNCTIONS
# =============================================================================

# Prepare environment
prepare_environment() {
    print_script_header "🔧 Preparing Environment"

    # Verify the Wine environment is set correctly
    print_info "Verifying Wine environment..."
    if [ -z "$WINEARCH" ]; then
        export WINEARCH=win64
        print_warning "⚠️ WINEARCH not set, defaulting to $WINEARCH"
    fi

    if [ -z "$WINEPREFIX" ]; then
        export WINEPREFIX="${STEAM_COMPAT_DATA_PATH}/pfx"
        print_warning "⚠️ WINEPREFIX not set, defaulting to $WINEPREFIX"
    fi

    # Verify display is working
    print_info "Checking display setup..."
    if [ -z "$DISPLAY" ]; then
        export DISPLAY=:99
        print_warning "⚠️ DISPLAY not set, defaulting to $DISPLAY"
    fi

    # Make sure server directory exists
    if [ ! -d "$ARK_SAVE_DIR" ]; then
        print_error "❌ ARK directory does not exist: $ARK_SAVE_DIR"
        return 1
    fi

    # Ensure executable directory exists
    local executable_dir="${ARK_SAVE_DIR}/ShooterGame/Binaries/Win64"
    if [ ! -d "$executable_dir" ]; then
        print_error "❌ Server executables directory does not exist: $executable_dir"
        print_info "Please make sure the server is properly installed"
        return 1
    fi

    print_success "✅ Environment preparation complete"
    return 0
}

# Start the appropriate server executable
start_server() {
    local server_type="$1"
    local executable=""

    # Define log file paths
    LOG_FILE="${WINE_LOG_FILE:-${ARK_SAVE_DIR}/ShooterGame/Saved/Logs/wine.log}"
    GAME_LOG_FILE="${ARK_SAVE_DIR}/ShooterGame/Saved/Logs/ServerGame.*.log"
    API_LOG_FILE="${ARK_SAVE_DIR}/ShooterGame/Binaries/Win64/logs/ArkApi_*.log"
    CRASH_LOG_FILE="${ARK_SAVE_DIR}/ShooterGame/Saved/Logs/Crash*.log"

    # Determine which executable to use based on server type
    if [ "$server_type" = "api" ]; then
        executable="AsaApiLoader.exe"
        print_script_header "🚀 Starting ARK API Server"
    else
        executable="ArkAscendedServer.exe"
        print_script_header "🚀 Starting ARK Game Server"
    fi

    local executable_path="${ARK_SAVE_DIR}/ShooterGame/Binaries/Win64/${executable}"

    # Check if the executable exists
    if [ ! -f "$executable_path" ]; then
        print_error "❌ Executable not found: $executable_path"
        print_info "Please verify your ARK installation directory."
        return 1
    fi

    # Build the command string with server parameters
    local cmd="${SERVER_MAP}?listen?SessionName=${SERVER_SESSION_NAME}"

    # Add optional parameters if they are set
    if [ -n "${GAMEPLAY_MAX_PLAYERS}" ]; then
        cmd="${cmd}?MaxPlayers=${GAMEPLAY_MAX_PLAYERS}"
    fi

    if [ -n "${SERVER_PASSWORD}" ]; then
        cmd="${cmd}?ServerPassword=${SERVER_PASSWORD}"
    fi

    if [ -n "${NETWORK_RCON_PORT}" ]; then
        cmd="${cmd}?RCONEnabled=True?RCONPort=${NETWORK_RCON_PORT}"
    fi

    if [ -n "${NETWORK_QUERY_PORT}" ]; then
        cmd="${cmd}?QueryPort=${NETWORK_QUERY_PORT}"
    fi

    # IMPORTANT: According to https://ark.wiki.gg/wiki/Dedicated_server_setup this must be the last argument, otherwise it will parse
    # all other arguments after this as part of the password
    if [ -n "${SERVER_ADMIN_PASSWORD}" ]; then
        cmd="${cmd}?ServerAdminPassword=${SERVER_ADMIN_PASSWORD}"
    fi

    # Add any extra options specified in the environment
    cmd="${cmd}${GAMEPLAY_EXTRA_OPTIONS}"

    # Add server dash options
    local flags=""

    # Add mods if specified
    if [ -n "${GAMEPLAY_MODS}" ]; then
        flags="${flags} -mods=${GAMEPLAY_MODS}"
        print_info "Loading mods: ${GAMEPLAY_MODS}"
    fi

    # Add standard logging flags
    flags="${flags} -log -ServerRCONOutputTribeLogs -gameplaylogging -servergamelog -servergamelogincludetribelogs -port=${NETWORK_SERVER_PORT}"

    # Configure BattlEye based on settings
    if [ "${GAMEPLAY_BATTLEYE}" = "True" ] || [ "${GAMEPLAY_BATTLEYE}" = "1" ] || [ "${GAMEPLAY_BATTLEYE}" = "true" ]; then
        flags="${flags} -UseBattlEye"
        print_info "BattlEye anti-cheat enabled"
    else
        flags="${flags} -NoBattlEye"
        print_info "BattlEye anti-cheat disabled"
    fi

    # Configure max players for WinLive if specified
    if [ -n "${GAMEPLAY_MAX_PLAYERS}" ]; then
        flags="${flags} -WinLiveMaxPlayers=${GAMEPLAY_MAX_PLAYERS}"
    fi

    # Add cluster ID if specified
    if [ -n "${SERVER_CLUSTER_ID}" ]; then
        flags="${flags} -clusterid=${SERVER_CLUSTER_ID}"
        print_info "Using cluster ID: ${SERVER_CLUSTER_ID}"
    fi

    # Add query port if specified
    if [ -n "${NETWORK_QUERY_PORT}" ]; then
        flags="${flags} -NitradoQueryPort=${NETWORK_QUERY_PORT}"
    fi

    # Add any extra dash options
    flags="${flags} ${GAMEPLAY_EXTRA_DASH_OPTIONS}"

    # Display the full command for debugging
    print_info "Full command line: wine64 \"${executable_path}\" \"${cmd}\" ${flags}"

    # Ensure the log directory exists
    if dir_does_not_exist "${ARK_SAVE_DIR}/ShooterGame/Saved/Logs"; then
        print_info "Creating log directory: ${ARK_SAVE_DIR}/ShooterGame/Saved/Logs"
        mkdir -p "${ARK_SAVE_DIR}/ShooterGame/Saved/Logs"
    fi

    # Ensure the log file exists
    if file_does_not_exist "${LOG_FILE}"; then
        print_info "Creating log file: ${LOG_FILE}"
        touch "${LOG_FILE}"
    fi

    # Start the server in the background and create a server start flag
    print_info "Starting server process..."
    create_flag "start"
    nohup wine64 "${executable_path}" "${cmd}" ${flags} >"${LOG_FILE}" 2>&1 &

    local wine_pid=$!
    print_info "Started process with PID: $wine_pid"

    # Check if process was created successfully
    if ! ps -p $wine_pid >/dev/null 2>&1; then
        print_error "❌ Failed to start server process"
        return 1
    fi

    # Wait for server initialization
    if ! wait_for_initialization $wine_pid; then
        return 1
    fi

    # Check logs for any errors
    print_info "Analyzing server logs for startup issues..."

    # Check the main Wine log that should always exist
    print_info "Checking main wine log..."
    check_logs_for_errors "${LOG_FILE}"

    # Check game logs (may not exist on first start)
    print_info "Checking most recent game log..."
    check_logs_for_errors "${GAME_LOG_FILE}"

    # Only check API logs if running API server
    if [ "$server_type" = "api" ]; then
        print_info "Checking most recent API log..."
        check_logs_for_errors "${API_LOG_FILE}"
    fi

    # Check for crash logs
    print_info "Checking for recent crash logs..."
    check_logs_for_errors "${CRASH_LOG_FILE}"

    # Note: We continue even if errors are found, as they might be non-fatal

    # Verify server has actually started and is responsive
    if ! verify_server_started $SYSTEM_STARTUP_TIMEOUT; then
        print_error "❌ Server verification failed"
        print_info "Last 20 lines of the log:"
        tail -n 20 "${LOG_FILE}" 2>/dev/null || echo "Log file not available"
        return 1
    fi

    print_success "✅ Server successfully started"
    # Remove the starting flag as server is now running
    remove_flag "start"
    return 0
}

# Wait for server to initialize
wait_for_initialization() {
    local wine_pid=$1
    print_info "Giving server time to initialize (${SYSTEM_STARTUP_WAIT}s)..."

    local wait_time=0
    local check_interval=5

    while [ $wait_time -lt $SYSTEM_STARTUP_WAIT ]; do
        loading "Waiting for server initialization... (${wait_time}s/${SYSTEM_STARTUP_WAIT}s)"
        sleep $check_interval
        wait_time=$((wait_time + check_interval))

        # Check if process is still running
        if ! ps -p $wine_pid >/dev/null 2>&1; then
            echo "" # Add a newline after the spinner
            print_error "❌ Server process terminated during initialization"
            print_info "Checking logs for errors..."
            check_logs_for_errors "${LOG_FILE}"
            return 1
        fi
    done

    echo "" # Add a newline after the spinner
    return 0
}

# =============================================================================
# COMMAND LINE PARSING
# =============================================================================

# Parse command line arguments
parse_arguments() {
    FORCE_RESTART="no"
    SHOW_STATUS="no"
    SKIP_CHECKS="no"
    # Default to standard server if not specified
    SERVER_TYPE="server"

    while [[ $# -gt 0 ]]; do
        case "$1" in
        api | server)
            SERVER_TYPE="$1"
            shift
            ;;
        --help)
            echo "Usage: ./start.sh [options]"
            echo "Options:"
            echo "  server|api           Specify server type to start (default: server)"
            echo "  --help               Display this help message"
            exit 0
            ;;
        *)
            print_warning "⚠️ Unknown option: $1"
            shift
            ;;
        esac
    done
}

# Check if server is already running
check_server_running() {
    print_info "Checking server status..."
    local ark_server_pid=$(get_ark_server_pid)

    if equals "$ark_server_pid" "0"; then
        print_info "No ARK server is currently running"
        return 0
    fi

    print_warning "⚠️ ARK server is already running (PID: $ark_server_pid)"
    print_info "Server is already running. Use \`ark restart\` to restart it."
    return 1
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

# Set up trap to call cleanup on exit
trap cleanup EXIT INT TERM

# Main function
main() {
    # Use common.sh function to print header
    print_script_header "🎮 ARK Server Launcher"

    # Parse arguments
    parse_arguments "$@"

    # Check required environment variables
    check_required_env REQUIRED_VARS || exit 1

    # Check optional environment variables
    check_optional_env OPTIONAL_VARS

    # Set default values for optional variables
    set_default_values

    # Display server type
    if [ "$SERVER_TYPE" = "api" ]; then
        print_info "Starting ARK API server..."
    else
        print_info "Starting standard ARK server..."
    fi

    # Check if the server is already running before starting
    check_server_running || exit 1

    # Prepare environment
    if ! prepare_environment; then
        print_error "❌ Failed to prepare environment"
        exit 1
    fi

    # Start server
    if ! start_server "$SERVER_TYPE"; then
        print_error "❌ Failed to start the server"
        exit 1
    fi

    print_success "🎮 Server started successfully"
    echo ""
    print_info "The server will continue running in the background."
    print_info "Log file: ${WINE_LOG_FILE}"

    print_info "To check server status, use: \`ark status\`"
    print_info "To stop the server, use: \`ark stop\`"
    print_info "You can safely exit this terminal session."

    # Remove the shutdown flag so the monitor can detect the server is running
    remove_flag "shutdown"

    # Explicitly exit with success
    exit 0
}

# Execute the main function with all arguments
main "$@"
