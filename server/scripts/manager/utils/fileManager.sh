#!/bin/bash

# Load utilities
UTILS_PATH="$MANAGER_DIR/utils"
source "${UTILS_PATH}/colorPrinter.sh"

# Function to safely move files across filesystems
# If rename fails due to cross-device link, falls back to copy + delete
safe_move() {
    local src="$1"
    local dest="$2"
    
    # Create destination directory if it doesn't exist
    mkdir -p "$(dirname "$dest")"
    
    # First try with mv (faster if on same filesystem)
    if ! mv "$src" "$dest" 2>/dev/null; then
        # Check if it's a cross-device issue
        if [ $? -eq 1 ]; then
            print_info "Cross-device move detected, copying instead: $src -> $dest"
            # Fall back to copy + delete if across filesystems
            cp "$src" "$dest" && rm "$src"
            if [ $? -ne 0 ]; then
                print_error "Failed to copy and delete $src"
                return 1
            fi
        else
            print_error "Failed to move $src to $dest"
            return 1
        fi
    fi
    
    return 0
} 