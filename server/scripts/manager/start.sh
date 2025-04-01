#!/bin/bash
#
# ARK Server Start Script
# Unified script to start either the standard server or API server

# Load environment variables and utilities
UTILS_PATH="$MANAGER_DIR/utils"
source "${UTILS_PATH}/colorPrinter.sh"
source "${UTILS_PATH}/serverStatus.sh"
source "${UTILS_PATH}/envManager.sh"

# Define required and optional environment variables for server start
declare -a START_REQUIRED_VARS=(
    "ARK_DIR"
    "SERVER_MAP"
    "SESSION_NAME"
    "SERVER_PORT"
    "WINE_LOG_FILE"
    "STEAM_COMPAT_DATA_PATH"
)

# Define optional environment variables with default values
declare -a START_OPTIONAL_VARS=(
    "MAX_PLAYERS"
    "SERVER_PASSWORD"
    "ARK_ADMIN_PASSWORD"
    "RCON_PORT"
    "QUERY_PORT"
    "MODS"
    "BATTLEYE"
    "CLUSTER"
    "EVENT"
    "ARK_EXTRA_OPTS"
    "ARK_EXTRA_DASH_OPTS"
)

# Set default values
SERVER_TYPE="${1:-server}"  # Default to standard server if no type specified

# Prepare environment
prepare_environment() {
    # Don't use eval to modify the STEAM_COMPAT_DATA_PATH as it's already set in Dockerfile
    # Just create the prefix directory if it doesn't exist
    mkdir -p "${WINEPREFIX}" 2>/dev/null || true
    
    # Create necessary log directories
    local log_dir=$(dirname "${WINE_LOG_FILE}")
    mkdir -p "$log_dir" 2>/dev/null || true
    
    # Verify the Wine environment is set correctly
    print_info "Verifying Wine environment..."
    print_info "WINEARCH=${WINEARCH}"
    print_info "WINEPREFIX=${WINEPREFIX}"
    print_info "DISPLAY=${DISPLAY}"
}

# Check if server is already running and exit if it is
check_server_not_running() {
    local server_type=$1
    local process_names="ArkAscendedServer.exe,AsaApiLoader.exe"
    
    print_info "Checking if ARK server is already running..."
    
    # Use the serverStatus.sh utility to check if server is running
    if ! is_server_running 1 "$process_names"; then
        print_success "No ARK server is currently running. Safe to proceed."
        return 0
    else
        print_error "❌ ARK server is already running!"
        print_warning "Please stop the running server before starting a new one."
        return 1
    fi
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
    
    # Ensure Wine prefix directory exists
    mkdir -p "${STEAM_COMPAT_DATA_PATH}/pfx" 2>/dev/null || true
    
    # Create Wine log directory if it doesn't exist
    local log_dir=$(dirname "${WINE_LOG_FILE}")
    mkdir -p "$log_dir" 2>/dev/null || true
    
    # Verify display is working
    print_info "Checking display setup..."
    if [ -z "$DISPLAY" ]; then
        export DISPLAY=:99
        print_warning "Display not set, defaulting to $DISPLAY"
    fi
    
    # Build the command string directly here instead of using a function
    local cmd="${SERVER_MAP}?listen?SessionName=${SESSION_NAME}?Port=${SERVER_PORT}"
    
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

    cmd="${cmd}${ARK_EXTRA_OPTS}"

    # Server dash options
    local flags=""
    if [ -n "$MODS" ]; then
        flags="${flags} -mods=${MODS}"
    fi

    flags="${flags} -log -ServerRCONOutputTribeLogs -gameplaylogging -servergamelog -servergamelogincludetribelogs"

    # If BATTLEYE is set to True, 1 or true start server with -UseBattlEye
    if [ "${BATTLEYE}" = "True" ] || [ "${BATTLEYE}" = "1" ] || [ "${BATTLEYE}" = "true" ]; then
        flags="${flags} -UseBattlEye"
    else
        flags="${flags} -NoBattlEye"
    fi

    if [ -n "${MAX_PLAYERS}" ]; then
        flags="${flags} -WinLiveMaxPlayers=${MAX_PLAYERS}"
    fi

    if [ -n "${CLUSTER}" ]; then
        flags="${flags} -clusterid=${CLUSTER}"
    fi

    if [ -n "${EVENT}" ]; then
        flags="${flags} -ActiveEvent=${EVENT}"
    else
        flags="${flags} -ActiveEvent=None"
    fi

    flags="${flags} ${ARK_EXTRA_DASH_OPTS}"

    # Debug info
    print_info "Command arguments:"
    print_info "Main command: ${cmd}"
    print_info "Flags: ${flags}"
    
    # Ensure we're formatting the command properly
    print_info "Full command line: wine64 \"${executable_path}\" ${cmd} ${flags}"
    
    # Kill any existing ARK processes to ensure clean start
    pkill -f "${executable}" >/dev/null 2>&1 || true
    sleep 2
    
    # Start the server in the background without using eval 
    # We start a separate bash process to execute the command
    nohup wine64 "${executable_path}" "${cmd}" ${flags} >"${WINE_LOG_FILE}" 2>&1 &
    
    local wine_pid=$!
    print_info "Started process with PID: $wine_pid"
    
    # Check the log file for problems right away
    sleep 1
    if [ -f "${WINE_LOG_FILE}" ]; then
        local errors=$(grep -i "err\|fail\|terminate" "${WINE_LOG_FILE}" 2>/dev/null)
        if [ -n "$errors" ]; then
            print_warning "Potential issues detected in log:"
            echo "$errors" | head -5
        fi
    fi
    
    # Give it a moment to start and check if process is still running
    print_info "Waiting for server to initialize..."
    sleep 5  # Increased sleep time to allow more startup time
    if ps -p $wine_pid > /dev/null 2>&1; then
        print_success "✅ Server process started successfully with PID: $wine_pid"
        print_info "Log file: ${WINE_LOG_FILE}"
        
        # Add a message about how to monitor the server
        print_info "To monitor server status, use: tail -f ${WINE_LOG_FILE}"
        
        return 0
    else 
        print_error "❌ Server process failed to start or terminated immediately"
        print_info "Check log file for details: ${WINE_LOG_FILE}"
        print_info "Last 10 lines of the log:"
        tail -n 10 "${WINE_LOG_FILE}" 2>/dev/null || echo "Log file not available"
        return 1
    fi
}

# Main function
main() {
    clear # Start with a clean screen
    
    # Check required environment variables
    if ! check_env_variables START_REQUIRED_VARS 0; then
        print_error "❌ Missing required environment variables"
        exit 1
    fi
    
    # Check optional environment variables and print warnings
    if ! check_env_variables START_OPTIONAL_VARS 1; then
        print_warning "⚠️ Some optional environment variables are not set"
        echo ""
    fi
    
    # Determine server type from argument
    if [ "$1" = "api" ]; then
        SERVER_TYPE="api"
        print_info "Starting ARK API server..."
    else
        SERVER_TYPE="server"
        print_info "Starting standard ARK server..."
    fi
    
    # Check if server is already running
    if ! check_server_not_running "$SERVER_TYPE"; then
        exit 1
    fi
    
    # Prepare environment
    prepare_environment
    
    # Start server
    if start_server "$SERVER_TYPE"; then
        print_success "🎮 Server startup initiated successfully"
        echo ""
        print_info "The server will continue running in the background."
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