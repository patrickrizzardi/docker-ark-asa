#!/bin/bash
#
# ARK Server RCON Command Script
# Sends RCON commands to the ARK server
#
# Usage: ./rcon.sh <command> [--silent]
# Example: ./rcon.sh "SaveWorld" --silent
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

# Required environment variables
declare -a RCON_REQUIRED_VARS=(
    "ARK_ADMIN_PASSWORD"     # Admin password for RCON
    "RCON_PORT"              # RCON port for remote commands
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
    # Just check if the RCON binary exists, without executing it
    if [ -f "/home/arkuser/.local/bin/rcon" ] || [ -f "/usr/bin/rcon" ] || [ -f "/usr/local/bin/rcon" ]; then
        return 0
    else
        print_warning "⚠️ RCON binary not found. Cannot communicate with server via RCON."
        print_info "To install RCON tools, you need to add the package to your Dockerfile."
        return 1
    fi
}

# Run an RCON command with retries and error handling
run_rcon_command() {
    local cmd="$1"
    local silent=${2:-0}
    
    # Check if rcon is available first
    if ! command -v "${RCON_PATH}" >/dev/null 2>&1; then
        echo "RCON_NOT_AVAILABLE"
        return 2
    fi
    
    local attempt=1
    local max_attempts=3
    local delay=2
    
    while [ $attempt -le $max_attempts ]; do
        if [ "$silent" -eq 0 ]; then
            print_info "Attempt $attempt of $max_attempts: Sending RCON command: $cmd"
        fi
        
        local output=$(${RCON_CMDLINE[@]} "$cmd" 2>&1)
        local status=$?
        
        log_rcon_attempt "$cmd" "$output" "$status"
        
        # Check for timeout in output
        if [[ "$output" == *"i/o timeout"* ]]; then
            if [ "$silent" -eq 0 ]; then
                print_warning "RCON timeout on attempt $attempt"
            fi
            if [ $attempt -eq $max_attempts ]; then
                echo "RCON_TIMEOUT"
                return 1
            fi
            sleep $delay
            attempt=$((attempt + 1))
            delay=$((delay * 2))  # Exponential backoff
            continue
        fi
        
        if [ $status -eq 0 ]; then
            echo "$output"
            return 0
        fi
        
        if [ "$silent" -eq 0 ]; then
            print_warning "RCON attempt $attempt failed. Waiting ${delay}s before retry..."
        fi
        sleep $delay
        attempt=$((attempt + 1))
        delay=$((delay * 2))  # Exponential backoff
    done
    
    # All attempts failed
    echo "RCON_FAILED"
    return 1
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

# Main function
main() {
    # Check if silent mode is enabled
    local silent=0
    if [[ "$1" == "--silent" ]]; then
        silent=1
    fi
    
    # Only show header if not silent
    if [[ $silent -eq 0 ]]; then
        clear # Start with a clean screen
        print_header "🎮 ARK Server RCON Command"
        echo ""
    fi

    # Check required environment variables
    if ! check_env_variables RCON_REQUIRED_VARS $silent; then
        print_error "❌ Missing required environment variables"
        return 1
    fi
    
    # Get container IP
    local container_ip=$(get_container_ip)
    if [[ -z "$container_ip" ]]; then
        print_error "❌ Could not get container IP"
        return 1
    fi

    
    # Check if RCON is available
    if ! check_rcon_available; then
        print_error "❌ RCON command not available"
        return 1
    fi

    
    # Get command from arguments
    local command="$1"
    if [[ -z "$command" ]]; then
        print_error "❌ No command provided"
        print_info "Usage: ./rcon.sh \"<command>\" [--silent]"
        return 1
    fi
    
    # Run RCON command using the utility function
    local output
    output=$(run_rcon_command "$command" $silent)
    local res=$?
    
    # Handle special error cases
    case "$output" in
        "RCON_TIMEOUT")
            print_error "❌ RCON timeout"
            return 1
            ;;
        "RCON_NOT_AVAILABLE")
            print_error "❌ RCON command not available"
            return 1
            ;;
        "RCON_FAILED")
            print_error "❌ RCON command failed"
            return 1
            ;;
        *)
            if [[ $silent -eq 0 ]]; then
                print_success "✅ Command sent successfully"
                echo "Response:"
                echo "$output"
            else
                echo "$output"
            fi
            return 0
            ;;
    esac
}

# Execute the main function
main "$@" 