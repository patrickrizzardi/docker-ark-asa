#!/bin/bash
#
# ARK Server Save Script
# Saves the current world state
#
# Usage: ./save.sh
#
# =============================================================================

# Load environment variables and utilities
UTILS_PATH="$MANAGER_DIR/utils"
source "${UTILS_PATH}/colorPrinter.sh"
source "${UTILS_PATH}/processManager.sh"

# =============================================================================
# MAIN EXECUTION
# =============================================================================

# Main function
main() {
    clear # Start with a clean screen
    print_header "💾 ARK Server Save"
    echo ""   
    
    # Save the world using rcon.sh
    print_info "Saving world..."
    if ./rcon.sh "SaveWorld" --silent; then
        print_success "✅ World saved successfully"
        exit 0
    else
        print_error "❌ Failed to save world"
        print_warning "Server might be unresponsive or RCON is not properly configured"
        exit 1
    fi
}

# Execute the main function
main
