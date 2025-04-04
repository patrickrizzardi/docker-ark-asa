#!/bin/bash
#
# ARK Server List Players Script
# Gets the count of connected players
#
# Usage: ./listPlayers.sh [--debug]
#
# Return: Always outputs just the player count as a single number
#
# =============================================================================

# Load environment variables and utilities
source "${MANAGER_DIR}/utils/common.sh"

# =============================================================================
# MAIN EXECUTION
# =============================================================================

# Main function
main() {
    # Check for debug flag
    local debug=0
    if [[ "$1" == "--debug" ]]; then
        debug=1
    fi

    # Get player list using rcon command with added debug flag if needed
    local debug_flag=""
    [[ $debug -eq 1 ]] && debug_flag="--debug"
    
    local output=$(${MANAGER_DIR}/rcon.sh "ListPlayers" $debug_flag 2>&1)
    local res=$?

    # Debug logging
    if [[ $debug -eq 1 ]]; then
        echo "===== DEBUG: RCON COMMAND RESULT ====="
        echo "Exit code: $res"
        echo "Output:"
        echo "$output"
        echo "===== END DEBUG OUTPUT ====="
    fi

    # Handle various error conditions
    if [[ "$output" == *"RCON_TIMEOUT"* ]] || 
       [[ "$output" == *"RCON_CONNECTION_REFUSED"* ]] || 
       [[ "$output" == *"RCON_AUTH_FAILED"* ]] || 
       [[ "$output" == *"RCON_NOT_AVAILABLE"* ]] || 
       [[ "$output" == *"RCON_FAILED"* ]] || 
       [[ $res -ne 0 ]]; then
        
        [[ $debug -eq 1 ]] && echo "DEBUG: Detected RCON error condition"
        
        # Always return 0 players when RCON fails
        echo "0"
        exit 0
    fi

    # Check for empty or "no output" responses
    if [[ "$output" == "NO_OUTPUT" ]] || [[ -z "$output" ]] || [[ "$output" =~ ^[[:space:]]*$ ]]; then
        [[ $debug -eq 1 ]] && echo "DEBUG: No output from RCON command"
        echo "0"
        exit 0
    fi

    # No Players Connected case
    if [[ "$output" == *"No Players"* ]] || [[ "$output" == *"No players"* ]]; then
        [[ $debug -eq 1 ]] && echo "DEBUG: Detected 'No Players' message"
        echo "0"
        exit 0
    fi

    # Filter out initialization messages and system information
    local filtered_output=$(echo "$output" | 
        grep -v "Loading configuration" | 
        grep -v "Loaded .* ARK server environment variables" |
        grep -v "Checking required environment variables" |
        grep -v "All required environment variables are set" |
        grep -v "No Players" | 
        grep -v "^$" | 
        grep -v "Response:" |
        grep -v "Command sent successfully" |
        grep -v "Players:" |
        grep -v "===" |
        grep -v "Script rcon.sh")

    # Display filtered output in debug mode
    if [[ $debug -eq 1 ]]; then
        echo "===== DEBUG: FILTERED OUTPUT START ====="
        echo "$filtered_output"
        echo "===== DEBUG: FILTERED OUTPUT END ====="
    fi

    # Count lines that look like player entries (numbered list format)
    local player_count=$(echo "$filtered_output" | grep -E "^[0-9]+\." | wc -l)
    
    # If we didn't find any players in the numbered list format, try other patterns
    if [[ $player_count -eq 0 ]]; then
        # Try counting any non-empty line
        player_count=$(echo "$filtered_output" | grep -v "^$" | wc -l)
        
        # Show debug info about fallback count
        [[ $debug -eq 1 ]] && echo "DEBUG: Used fallback counting method, found $player_count lines"
    else
        [[ $debug -eq 1 ]] && echo "DEBUG: Found $player_count players using primary counting method"
    fi

    # Validate the count is non-negative
    if [[ $player_count -lt 0 ]]; then
        player_count=0
    fi

    # Output only the number
    echo "$player_count"
    exit 0
}

# Execute the main function
main "$@"
