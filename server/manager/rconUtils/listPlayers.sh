#!/bin/bash
#
# ARK Server List Players Script
# Lists connected players and returns a count
#
# Usage: ./listPlayers.sh
#
# =============================================================================

# Load environment variables and utilities
UTILS_PATH="$MANAGER_DIR/utils"
source "${UTILS_PATH}/colorPrinter.sh"
source "${UTILS_PATH}/processManager.sh"
source "${UTILS_PATH}/envManager.sh"

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
        print_header "👥 ARK Server Player List"
        echo ""
    fi
    
    # Check required environment variables
    if ! check_env_variables LIST_PLAYERS_REQUIRED_VARS $silent; then
        print_error "❌ Missing required environment variables"
        exit 1
    fi
    
    if [[ $silent -eq 0 ]]; then
        print_success "✅ Found running ARK server"
    fi
    
    # Get player list using rcon.sh
    if [[ $silent -eq 0 ]]; then
        print_info "Fetching player list..."
    fi
    local output=$(./rcon.sh "ListPlayers" --silent)
    local res=$?
    
    # Check for RCON timeout or failure - exit immediately if either occurs
    if [[ "$output" == *"RCON_TIMEOUT"* ]] || [[ $res -ne 0 ]]; then
        if [[ $silent -eq 0 ]]; then
            print_error "❌ Failed to get player list"
        fi
        exit 1
    fi
    
    # No Players Connected case - check different possible outputs
    if [[ "$output" == *"No Players"* ]] || [[ "$output" == *"No players"* ]] || [[ -z "$output" ]] || [[ "$output" =~ ^[[:space:]]*$ ]]; then
        if [[ $silent -eq 0 ]]; then
            print_success "✅ No players connected"
        fi
        echo "0"
        exit 0
    fi
    
    # Filter out any header lines or system messages and count actual player entries
    local filtered_output=$(echo "$output" | grep -v "No Players" | grep -v "^$" | grep -v "Players:")
    local num_players=$(echo "$filtered_output" | grep -c ".")
    
    if [[ $num_players -eq 0 ]]; then
        if [[ $silent -eq 0 ]]; then
            print_success "✅ No actual players connected detected"
        fi
        echo "0"
        exit 0
    fi
    
    if [[ $silent -eq 0 ]]; then
        print_success "✅ Found $num_players connected players"
        echo "Player list:"
        echo "$filtered_output"
    fi
    echo "$num_players"
    exit 0
}

# Execute the main function
main "$@"
