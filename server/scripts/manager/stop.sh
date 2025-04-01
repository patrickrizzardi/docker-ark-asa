#!/bin/bash
#
# ARK Server Stop Script
# Gracefully stops a running ARK server instance
#
# Usage: ./stop.sh [--force]
# - --force: Skip player checks and force server shutdown
#
# =============================================================================

# Load environment variables and utilities
UTILS_PATH="$MANAGER_DIR/utils"
source "${UTILS_PATH}/colorPrinter.sh"
source "${UTILS_PATH}/serverStatus.sh"
source "${UTILS_PATH}/envManager.sh"

# =============================================================================
# CONFIGURATION
# =============================================================================

# Required environment variables for stopping the server
declare -a STOP_REQUIRED_VARS=(
    "ARK_ADMIN_PASSWORD"     # Admin password for RCON
    "RCON_PORT"              # RCON port for remote commands
    "SERVER_SHUTDOWN_TIMEOUT" # Maximum time to wait for shutdown
)

# Get the container's IP address
get_container_ip() {
    local ip=$(hostname -I | awk '{print $1}')
    if [[ -z "$ip" ]]; then
        echo "0.0.0.0"  # Fallback to all interfaces
    else
        echo "$ip"
    fi
}

# RCON command setup
CONTAINER_IP=$(get_container_ip)
RCON_PATH="/home/arkuser/.local/bin/rcon"
RCON_CMDLINE=("${RCON_PATH}" -a "${CONTAINER_IP}:${RCON_PORT}" -p "${ARK_ADMIN_PASSWORD}" -t 5)

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Log RCON attempts for debugging
log_rcon_attempt() {
    local cmd="$1"
    local result="$2"
    local status="$3"
    
    print_info "RCON debug: Command: $cmd, Exit Code: $status, Output: $result"
}

# Check if RCON is available
check_rcon_available() {
    if [ -x "${RCON_PATH}" ]; then
        return 0
    elif command -v rcon >/dev/null 2>&1; then
        return 0
    else
        print_warning "⚠️ RCON command not found. Cannot communicate with server via RCON."
        print_info "To install RCON tools, you need to add the package to your Dockerfile."
        return 1
    fi
}

# Run an RCON command with retries and error handling
run_rcon_command() {
    local cmd="$1"
    
    # Check if rcon is available first
    if ! command -v "${RCON_PATH}" >/dev/null 2>&1; then
        echo "RCON_NOT_AVAILABLE"
        return 2
    fi
    
    local attempt=1
    local max_attempts=3
    local delay=2
    
    while [ $attempt -le $max_attempts ]; do
        print_info "Attempt $attempt of $max_attempts: Sending RCON command: $cmd"
        
        local output=$(${RCON_CMDLINE[@]} "$cmd" 2>&1)
        local status=$?
        
        log_rcon_attempt "$cmd" "$output" "$status"
        
        if [ $status -eq 0 ]; then
            echo "$output"
            return 0
        fi
        
        print_warning "RCON attempt $attempt failed. Waiting ${delay}s before retry..."
        sleep $delay
        attempt=$((attempt + 1))
        delay=$((delay * 2))  # Exponential backoff
    done
    
    # All attempts failed
    echo "RCON_FAILED"
    return 1
}

# =============================================================================
# SERVER MANAGEMENT FUNCTIONS
# =============================================================================

# Get server PID function
get_server_pid() {
    # Try to find wine64 running ArkAscendedServer.exe
    local ark_pid=$(ps aux | grep -v grep | grep -i "wine64.*ArkAscendedServer.exe" | awk '{print $2}' | head -1)
    if [[ -n "$ark_pid" ]]; then
        echo $ark_pid
        return 0
    fi

    # Try to find wine64 running AsaApiLoader.exe
    ark_pid=$(ps aux | grep -v grep | grep -i "wine64.*AsaApiLoader.exe" | awk '{print $2}' | head -1)
    if [[ -n "$ark_pid" ]]; then
        echo $ark_pid
        return 0
    fi

    # No server process found
    echo "0"
    return 1
}

# Save world data via RCON
save_world() {
    print_info "Saving world data..."
    
    # If rcon is not available, skip the check
    if ! command -v "${RCON_PATH}" >/dev/null 2>&1; then
        print_warning "⚠️ Cannot save world: RCON not available"
        return 1
    fi
    
    # Directly run the RCON command with full path
    local out=$("${RCON_PATH}" -a "${CONTAINER_IP}:${RCON_PORT}" -p "${ARK_ADMIN_PASSWORD}" -t 5 "SaveWorld" 2>&1)
    local res=$?
    
    if [[ $res == 0 && ( "$out" == *"World Saved"* || "$out" == *"world saved"* ) ]]; then
        print_success "✅ World saved successfully"
        return 0
    else
        print_error "❌ Failed to save world"
        print_warning "Server might be offline or not responding to RCON commands"
        return 1
    fi
}

# Check player count before stopping
check_player_count() {
    print_info "Checking for connected players..."
    
    # If rcon is not available, skip the check
    if ! command -v "${RCON_PATH}" >/dev/null 2>&1; then
        if [[ "$1" == "--force" ]]; then
            print_warning "⚠️ Cannot check player count: RCON not available"
            print_warning "Force flag detected - proceeding with shutdown anyway"
            return 0
        else
            print_warning "⚠️ Cannot check player count: RCON not available"
            print_warning "This could be dangerous if players are connected"
            print_info "To stop the server anyway, use: $(basename $0) --force"
            return 1
        fi
    fi
    
    local out=$(run_rcon_command "ListPlayers")
    local res=$?
    
    if [[ $res == 0 ]]; then
        # No Players Connected case - check different possible outputs
        if [[ "$out" == *"No Players"* ]] || [[ "$out" == *"No players"* ]] || [[ -z "$out" ]] || [[ "$out" =~ ^[[:space:]]*$ ]]; then
            print_success "✅ No players connected"
            return 0
        else
            # Filter out any header lines or system messages and count actual player entries
            local filtered_output=$(echo "$out" | grep -v "No Players" | grep -v "^$" | grep -v "Players:")
            local num_players=$(echo "$filtered_output" | grep -c ".")
            
            if [[ $num_players -eq 0 ]]; then
                print_success "✅ No actual players connected detected"
                return 0
            fi
            
            print_warning "⚠️ Server has $num_players connected players!"
            print_info "Player list: $filtered_output"
            
            if [[ "$1" == "--force" ]]; then
                print_warning "Force flag detected - proceeding with shutdown anyway"
                return 0
            else
                print_error "❌ Cannot stop server with players connected"
                print_info "Use --force to override this check"
                return 1
            fi
        fi
    elif [[ $res == 2 ]]; then
        # RCON not available was already reported
        return 1
    else
        print_warning "⚠️ Could not check player count (RCON failed)"
        if [[ "$1" == "--force" ]]; then
            print_warning "Force flag detected - proceeding with shutdown anyway"
            return 0
        else
            print_warning "Server may not be fully initialized or RCON isn't working"
            print_info "To stop the server anyway, use: $(basename $0) --force"
            return 1
        fi
    fi
}

# Send shutdown command via RCON
send_shutdown_command() {
    print_info "Sending shutdown command to server..."
    
    # If rcon is not available, skip the command
    if ! command -v "${RCON_PATH}" >/dev/null 2>&1; then
        print_warning "⚠️ Cannot send shutdown command: RCON not available"
        return 1
    fi
    
    local out=$(run_rcon_command "DoExit")
    local res=$?
    
    if [[ $res == 0 && ( "$out" == *"Exiting..."* || "$out" == *"exiting"* ) ]]; then
        print_success "✅ Shutdown command sent successfully"
        return 0
    elif [[ $res == 2 ]]; then
        # RCON not available was already reported
        return 1
    else
        print_error "❌ Failed to send shutdown command"
        print_warning "Server might be offline or not responding to RCON commands"
        return 1
    fi
}

# Wait for server process to terminate
wait_for_server_shutdown() {
    local pid=$1
    local timeout=$SERVER_SHUTDOWN_TIMEOUT
    
    print_info "Waiting up to ${timeout} seconds for server to shut down..."
    
    local timer=0
    local check_interval=5
    
    while [[ $timer -lt $timeout ]]; do
        if ! ps -p $pid > /dev/null 2>&1; then
            print_success "✅ Server stopped successfully"
            return 0
        fi
        
        print_info "Server still running, waiting ${check_interval} seconds..."
        sleep $check_interval
        timer=$((timer + check_interval))
    done
    
    print_error "❌ Server did not stop within ${timeout} seconds"
    return 1
}

# Force kill the server process
force_shutdown() {
    local pid=$1
    
    print_warning "⚠️ Forcing server shutdown..."
    
    if kill -9 $pid > /dev/null 2>&1; then
        print_success "✅ Server process forcefully terminated"
        return 0
    else
        print_error "❌ Failed to forcefully terminate server process"
        return 1
    fi
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

# Main function
main() {
    clear # Start with a clean screen
    print_header "🛑 ARK Server Shutdown"
    echo ""
    
    # Check required environment variables
    if ! check_env_variables STOP_REQUIRED_VARS 0; then
        print_error "❌ Missing required environment variables"
        exit 1
    fi
    
    # Parse arguments
    local force_flag=""
    if [[ "$1" == "--force" ]]; then
        force_flag="--force"
        print_warning "⚠️ Force mode enabled - will terminate server regardless of player count"
    fi
    
    # Check if server is running
    print_info "Checking server status..."
    local server_pid=$(get_server_pid)
    
    if [[ "$server_pid" == "0" ]]; then
        print_warning "⚠️ No ARK server process found"
        exit 0
    fi
    
    print_success "✅ Found ARK server process with PID: $server_pid"
    
    # Check process uptime to see if it's freshly started
    local process_start_time=$(ps -o etimes= -p $server_pid)
    if [[ $process_start_time -lt 60 ]]; then
        print_warning "⚠️ Server was started recently (${process_start_time} seconds ago)"
        print_info "Waiting 10 seconds for RCON to initialize..."
        sleep 10
    fi
    
    # Check for connected players (unless force flag is set)
    if ! check_player_count $force_flag; then
        exit 1
    fi
    
    # First try to save the world
    save_world
    
    # Send shutdown command
    if send_shutdown_command; then
        # Wait for server to shut down gracefully
        if wait_for_server_shutdown $server_pid; then
            print_success "🎮 ARK server has been gracefully stopped"
            exit 0
        else
            # If graceful shutdown times out, ask for force kill
            print_warning "⚠️ Server did not respond to shutdown command within timeout period"
            
            if [[ "$force_flag" == "--force" ]]; then
                force_shutdown $server_pid
                exit $?
            else
                echo ""
                print_info "To force kill the server, run: $(basename $0) --force"
                exit 1
            fi
        fi
    else
        # If shutdown command fails, offer force kill option
        if [[ "$force_flag" == "--force" ]]; then
            force_shutdown $server_pid
            exit $?
        else
            echo ""
            print_info "To force kill the server, run: $(basename $0) --force"
            exit 1
        fi
    fi
}

# Execute the main function with all arguments
main "$@" 