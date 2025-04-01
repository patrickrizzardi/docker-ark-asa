#!/bin/bash
#
# ARK Server Start Script
# Unified script to start either the standard server or API server
#
# Usage: ./start.sh [options]
# Options:
#   server|api           Specify server type to start (default: server)
#   --force-restart      Force restart if server is already running
#   --show-status        Show server status after starting
#   --skip-checks        Skip environment checks
#   --help               Display this help message
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

# Define required and optional environment variables for server start
declare -a START_REQUIRED_VARS=(
    "ARK_DIR"                # ARK installation directory
    "SERVER_MAP"             # Map to run
    "SESSION_NAME"           # Server session name
    "SERVER_PORT"            # Server port
    "WINE_LOG_FILE"          # Wine log file location
    "STEAM_COMPAT_DATA_PATH" # Steam compatibility data path
)

# Define optional environment variables with default values
declare -a START_OPTIONAL_VARS=(
    "MAX_PLAYERS"         # Maximum number of players
    "SERVER_PASSWORD"     # Server password
    "ARK_ADMIN_PASSWORD"  # Admin password
    "RCON_PORT"           # RCON port
    "QUERY_PORT"          # Query port
    "MODS"                # Mods to load
    "BATTLEYE"            # BattlEye anti-cheat
    "CLUSTER"             # Cluster ID
    "EVENT"               # Active event
    "ARK_EXTRA_OPTS"      # Extra server options
    "ARK_EXTRA_DASH_OPTS" # Extra dash options
    "STARTUP_TIMEOUT"     # Timeout for server startup
    "STARTUP_WAIT"        # Time to wait for server to initialize
)

# Set default values for optional variables
STARTUP_TIMEOUT=${STARTUP_TIMEOUT:-300}             # 5 minutes timeout for server to start
STARTUP_WAIT=${STARTUP_WAIT:-30}                    # 30 seconds initial wait for server to initialize
SERVER_TYPE="server"                                # Default to standard server if no type specified
SERVER_START_FLAG="${ARK_DIR}/server_starting.flag" # Flag file to indicate server is starting

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Function to display a spinner with a message
declare -a SPINNER=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
SPINNER_IDX=0

show_spinner() {
    local message="$1"
    local current_spinner=${SPINNER[$SPINNER_IDX]}
    SPINNER_IDX=$(((SPINNER_IDX + 1) % ${#SPINNER[@]}))

    printf "\r${current_spinner} ${message}"
}

# Function to create server start flag file
create_start_flag() {
    echo "$(date) - Server start initiated by PID $$" >"$SERVER_START_FLAG"
    print_success "✅ Created server start flag: $SERVER_START_FLAG"
}

# Function to remove server start flag file
remove_start_flag() {
    if [[ -f "$SERVER_START_FLAG" ]]; then
        rm -f "$SERVER_START_FLAG"
        print_success "✅ Removed server start flag"
    fi
}

# Function to verify server has started successfully
verify_server_started() {
    local timeout=$1
    local check_interval=5
    local elapsed=0

    print_info "Verifying server startup (timeout: ${timeout}s)..."

    while [ $elapsed -lt $timeout ]; do
        # Check for server process
        local ark_server_pid=$(get_ark_server_pid)
        if [[ "$ark_server_pid" != "0" ]]; then
            # Check if the server is actually responsive using RCON
            if [[ -n "$RCON_PORT" && -n "$ARK_ADMIN_PASSWORD" ]]; then
                show_spinner "Checking server responsiveness via RCON... (${elapsed}s/${timeout}s)"
                local rcon_output=$(./rcon.sh "info" --silent 2>&1)
                local rcon_status=$?

                if [[ $rcon_status -eq 0 && "$rcon_output" != *"RCON_TIMEOUT"* && "$rcon_output" != *"RCON_FAILED"* ]]; then
                    echo "" # Add a newline after the spinner
                    print_success "✅ Server verified as responsive via RCON"
                    return 0
                fi
            else
                # If RCON is not available, just check if process exists
                if is_process_running "ArkAscendedServer.exe" || is_process_running "AsaApiLoader.exe"; then
                    # Check if server is listening on its port
                    show_spinner "Checking if server is listening on port ${SERVER_PORT}... (${elapsed}s/${timeout}s)"

                    if ss -tuln | grep -q ":${SERVER_PORT}"; then
                        echo "" # Add a newline after the spinner
                        print_success "✅ Server verified as listening on port ${SERVER_PORT}"
                        return 0
                    fi
                fi
            fi
        fi

        # Server not yet fully started, wait and try again
        show_spinner "Waiting for server to start... (${elapsed}s/${timeout}s)"
        sleep $check_interval
        elapsed=$((elapsed + check_interval))
    done

    echo "" # Add a newline after the spinner
    print_error "❌ Server failed to start within ${timeout} seconds"
    return 1
}

# Function to check logs for startup errors
check_logs_for_errors() {
    local log_file="$1"
    local max_lines=${2:-50}

    if [ ! -f "$log_file" ]; then
        print_warning "⚠️ Log file not found: $log_file"
        return 1
    fi

    print_info "Checking logs for errors..."

    # Common error patterns to look for
    local errors=$(grep -i "error\|failed\|crash\|exception\|fatal\|cannot\|unable\|denied\|terminated\|segmentation fault" "$log_file" | tail -n $max_lines)

    if [ -n "$errors" ]; then
        print_warning "⚠️ Potential issues detected in log:"
        echo "$errors" | head -10

        # Look for specific known issues
        if grep -i "steam_api64.dll" "$log_file" >/dev/null; then
            print_warning "⚠️ Steam API issue detected - may indicate Steam initialization failure"
        fi

        if grep -i "battleye" "$log_file" >/dev/null; then
            print_warning "⚠️ BattlEye issue detected - consider using -NoBattlEye option"
        fi

        if grep -i "permission denied" "$log_file" >/dev/null; then
            print_warning "⚠️ Permission issues detected - check file permissions"
        fi

        return 1
    else
        print_success "✅ No major errors found in logs"
        return 0
    fi
}

# Function for cleanup on script exit
cleanup() {
    local exit_code=$?

    # Remove server start flag
    remove_start_flag

    print_info "Start script exiting with code: $exit_code"
    exit $exit_code
}

# =============================================================================
# SERVER MANAGEMENT FUNCTIONS
# =============================================================================

# Prepare environment
prepare_environment() {
    print_header "🔧 Preparing Environment"

    # Don't use eval to modify the STEAM_COMPAT_DATA_PATH as it's already set in Dockerfile
    # Just create the prefix directory if it doesn't exist
    mkdir -p "${WINEPREFIX}" 2>/dev/null || true

    # Create necessary log directories
    local log_dir=$(dirname "${WINE_LOG_FILE}")
    if [ ! -d "$log_dir" ]; then
        print_info "Creating log directory: $log_dir"
        mkdir -p "$log_dir" 2>/dev/null || true

        if [ ! -d "$log_dir" ]; then
            print_error "❌ Failed to create log directory: $log_dir"
            return 1
        fi
    fi

    # Verify the Wine environment is set correctly
    print_info "Verifying Wine environment..."
    if [ -z "$WINEARCH" ]; then
        export WINEARCH=win64
        print_warning "⚠️ WINEARCH not set, defaulting to $WINEARCH"
    else
        print_info "WINEARCH=${WINEARCH}"
    fi

    if [ -z "$WINEPREFIX" ]; then
        export WINEPREFIX="${STEAM_COMPAT_DATA_PATH}/pfx"
        print_warning "⚠️ WINEPREFIX not set, defaulting to $WINEPREFIX"
    else
        print_info "WINEPREFIX=${WINEPREFIX}"
    fi

    # Verify display is working
    print_info "Checking display setup..."
    if [ -z "$DISPLAY" ]; then
        export DISPLAY=:99
        print_warning "⚠️ DISPLAY not set, defaulting to $DISPLAY"
    else
        print_info "DISPLAY=${DISPLAY}"
    fi

    # Make sure server directory exists
    if [ ! -d "$ARK_DIR" ]; then
        print_error "❌ ARK directory does not exist: $ARK_DIR"
        return 1
    fi

    # Ensure executable directory exists
    local executable_dir="${ARK_DIR}/ShooterGame/Binaries/Win64"
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

    # Determine which executable to use based on server type
    if [ "$server_type" = "api" ]; then
        executable="AsaApiLoader.exe"
        print_header "🚀 Starting ARK API Server"
    else
        executable="ArkAscendedServer.exe"
        print_header "🚀 Starting ARK Game Server"
    fi

    local executable_path="${ARK_DIR}/ShooterGame/Binaries/Win64/${executable}"

    # Check if the executable exists
    if [ ! -f "$executable_path" ]; then
        print_error "❌ Executable not found: $executable_path"
        print_info "Please verify your ARK installation directory."
        return 1
    fi

    # Create a server start flag
    create_start_flag

    # Build the command string with server parameters
    local cmd="${SERVER_MAP}?listen?SessionName=${SESSION_NAME}?Port=${SERVER_PORT}"

    # Add optional parameters if they are set
    if [ -n "${MAX_PLAYERS}" ]; then
        cmd="${cmd}?MaxPlayers=${MAX_PLAYERS}"
    fi

    if [ -n "${SERVER_PASSWORD}" ]; then
        cmd="${cmd}?ServerPassword=${SERVER_PASSWORD}"
    fi

    if [ -n "${ARK_ADMIN_PASSWORD}" ]; then
        cmd="${cmd}?ServerAdminPassword=${ARK_ADMIN_PASSWORD}"
    fi

    if [ -n "${RCON_PORT}" ]; then
        cmd="${cmd}?RCONEnabled=True?RCONPort=${RCON_PORT}"
    fi

    if [ -n "${QUERY_PORT}" ]; then
        cmd="${cmd}?QueryPort=${QUERY_PORT}"
    fi

    # Add any extra options specified in the environment
    cmd="${cmd}${ARK_EXTRA_OPTS}"

    # Add server dash options
    local flags=""

    # Add mods if specified
    if [ -n "$MODS" ]; then
        flags="${flags} -mods=${MODS}"
        print_info "Loading mods: ${MODS}"
    fi

    # Add standard logging flags
    flags="${flags} -log -ServerRCONOutputTribeLogs -gameplaylogging -servergamelog -servergamelogincludetribelogs"

    # Configure BattlEye based on settings
    if [ "${BATTLEYE}" = "True" ] || [ "${BATTLEYE}" = "1" ] || [ "${BATTLEYE}" = "true" ]; then
        flags="${flags} -UseBattlEye"
        print_info "BattlEye anti-cheat enabled"
    else
        flags="${flags} -NoBattlEye"
        print_info "BattlEye anti-cheat disabled"
    fi

    # Configure max players for WinLive if specified
    if [ -n "${MAX_PLAYERS}" ]; then
        flags="${flags} -WinLiveMaxPlayers=${MAX_PLAYERS}"
    fi

    # Add cluster ID if specified
    if [ -n "${CLUSTER}" ]; then
        flags="${flags} -clusterid=${CLUSTER}"
        print_info "Using cluster ID: ${CLUSTER}"
    fi

    # Configure active event
    if [ -n "${EVENT}" ]; then
        flags="${flags} -ActiveEvent=${EVENT}"
        print_info "Active event set to: ${EVENT}"
    else
        flags="${flags} -ActiveEvent=None"
    fi

    # Add any extra dash options
    flags="${flags} ${ARK_EXTRA_DASH_OPTS}"

    # Display the full command for debugging
    print_info "Full command line: wine64 \"${executable_path}\" \"${cmd}\" ${flags}"

    # Truncate the log file to avoid confusion with previous runs
    if [ -f "${WINE_LOG_FILE}" ]; then
        print_info "Truncating existing log file: ${WINE_LOG_FILE}"
        echo "=== Server start at $(date) ===" >"${WINE_LOG_FILE}"
    fi

    # Start the server in the background
    print_info "Starting server process..."
    nohup wine64 "${executable_path}" "${cmd}" ${flags} >"${WINE_LOG_FILE}" 2>&1 &

    local wine_pid=$!
    print_info "Started process with PID: $wine_pid"

    # Check if process was created successfully
    if ! ps -p $wine_pid >/dev/null 2>&1; then
        print_error "❌ Failed to start server process"
        return 1
    fi

    # Give it a moment to initialize and check for immediate errors
    print_info "Giving server time to initialize (${STARTUP_WAIT}s)..."
    local wait_time=0
    local check_interval=5

    while [ $wait_time -lt $STARTUP_WAIT ]; do
        show_spinner "Waiting for server initialization... (${wait_time}s/${STARTUP_WAIT}s)"
        sleep $check_interval
        wait_time=$((wait_time + check_interval))

        # Check if process is still running
        if ! ps -p $wine_pid >/dev/null 2>&1; then
            echo "" # Add a newline after the spinner
            print_error "❌ Server process terminated during initialization"
            print_info "Checking logs for errors..."
            check_logs_for_errors "${WINE_LOG_FILE}" 100
            return 1
        fi
    done

    echo "" # Add a newline after the spinner

    # Check logs for any errors
    if ! check_logs_for_errors "${WINE_LOG_FILE}" 100; then
        print_warning "⚠️ Some issues were detected in logs, but server appears to be starting"
    fi

    # Verify server has actually started and is responsive
    if verify_server_started $STARTUP_TIMEOUT; then
        print_success "✅ Server successfully started"
        # Remove the starting flag as server is now running
        remove_start_flag
        return 0
    else
        print_error "❌ Server verification failed"
        print_info "Last 20 lines of the log:"
        tail -n 20 "${WINE_LOG_FILE}" 2>/dev/null || echo "Log file not available"
        return 1
    fi
}

# =============================================================================
# COMMAND LINE PARSING
# =============================================================================

# Parse command line arguments
parse_arguments() {
    FORCE_RESTART="no"
    SHOW_STATUS="no"
    SKIP_CHECKS="no"

    while [[ $# -gt 0 ]]; do
        case "$1" in
        api | server)
            SERVER_TYPE="$1"
            shift
            ;;
        --force-restart)
            FORCE_RESTART="yes"
            shift
            ;;
        --show-status)
            SHOW_STATUS="yes"
            shift
            ;;
        --skip-checks)
            SKIP_CHECKS="yes"
            shift
            ;;
        --help)
            echo "Usage: ./start.sh [options]"
            echo "Options:"
            echo "  server|api           Specify server type to start (default: server)"
            echo "  --force-restart      Force restart if server is already running"
            echo "  --show-status        Show server status after starting"
            echo "  --skip-checks        Skip environment checks"
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

# =============================================================================
# MAIN EXECUTION
# =============================================================================

# Set up trap to call cleanup on exit
trap cleanup EXIT INT TERM

# Main function
main() {
    clear # Start with a clean screen
    print_header "🎮 ARK Server Launcher"
    echo ""

    # Parse arguments
    parse_arguments "$@"

    # Skip environment checks if requested
    if [ "$SKIP_CHECKS" != "yes" ]; then
        # Check required environment variables
        if ! check_env_variables START_REQUIRED_VARS 0; then
            print_error "❌ Missing required environment variables"
            exit 1
        fi

        # Check optional environment variables
        check_env_variables START_OPTIONAL_VARS 1
    else
        print_warning "⚠️ Skipping environment variable checks"
    fi

    # Display server type
    if [ "$SERVER_TYPE" = "api" ]; then
        print_info "Starting ARK API server..."
    else
        print_info "Starting standard ARK server..."
    fi

    # Check if the server is already running before starting
    print_info "Checking server status..."
    local ark_server_pid=$(get_ark_server_pid)

    if [[ "$ark_server_pid" != "0" ]]; then
        print_warning "⚠️ ARK server is already running (PID: $ark_server_pid)"

        # Show additional information if the user wants to see status
        if [[ "$SHOW_STATUS" == "yes" ]]; then
            print_info "Server process information:"
            ps -f -p "$ark_server_pid"

            if [[ -n "$RCON_PORT" && -n "$ARK_ADMIN_PASSWORD" ]]; then
                print_info "Server RCON information:"
                ./rcon.sh "serverchat Server is running" --silent || print_warning "⚠️ RCON not responsive"
            fi

            # Show the server listen port
            print_info "Server listening port information:"
            ss -tuln | grep ":${SERVER_PORT}" || print_warning "⚠️ Server not listening on port ${SERVER_PORT}"

            exit 0
        fi

        # Ask for confirmation before force restart
        if [[ "$FORCE_RESTART" == "yes" ]]; then
            print_warning "⚠️ Force restart requested - stopping existing server..."
            if ! "${MANAGER_DIR}/stop.sh" --force; then
                print_error "❌ Failed to stop existing server"
                exit 1
            fi
            print_success "✅ Existing server stopped for restart"
        else
            print_info "Server is already running. Use --force-restart to stop and restart it."
            print_info "Or use --show-status to see server status."
            exit 0
        fi
    else
        print_info "No ARK server is currently running"
    fi

    # Prepare environment
    if ! prepare_environment; then
        print_error "❌ Failed to prepare environment"
        exit 1
    fi

    # Start server
    if start_server "$SERVER_TYPE"; then
        print_success "🎮 Server started successfully"
        echo ""
        print_info "The server will continue running in the background."
        print_info "Log file: ${WINE_LOG_FILE}"

        # Show status if requested
        if [ "$SHOW_STATUS" = "yes" ]; then
            print_info "Server status:"
            "${MANAGER_DIR}/status.sh"
        else
            print_info "To check server status, use: ./status.sh"
        fi

        print_info "To stop the server, use: ./stop.sh"
        print_info "You can safely exit this terminal session."
    else
        print_error "❌ Failed to start the server"
        exit 1
    fi

    # Explicitly exit with success
    exit 0
}

# Execute the main function with all arguments
main "$@"
