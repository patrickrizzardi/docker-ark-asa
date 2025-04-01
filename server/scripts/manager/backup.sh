#!/bin/bash

# ARK Server Backup Utility
# Creates compressed backups of the ARK saved game data

# Ensure the script exits on any error
set -e

# Load utilities
UTILS_PATH="$MANAGER_DIR/utils"
source "${UTILS_PATH}/colorPrinter.sh"
source "${UTILS_PATH}/envManager.sh"

# Define required and optional environment variables for backup
declare -a BACKUP_REQUIRED_VARS=(
    "ARK_DIR"
    "BACKUP_PATH"
    "MAX_BACKUPS"
    "MANAGER_DIR"
)

# Creates a formatted timestamp for the backup filename
get_timestamp() {
    date +"%Y-%m-%d_%H-%M-%S"
}

# Creates a backup path if it doesn't exist
create_backup_path_if_not_exists() {
    if [ ! -d "$BACKUP_PATH" ]; then
        mkdir -p "$BACKUP_PATH"
        print_info "Created backup directory: $BACKUP_PATH"
    fi
}

# Creates a backup of the ARK saved data
create_backup() {
    # Create a copy of the save folder to the backup path
    local copy_path="$BACKUP_PATH/Saved"
    
    print_info "Creating copy of save folder to $copy_path..."
    mkdir -p "$copy_path"
    cp -r "$ARK_DIR/ShooterGame/Saved" "$BACKUP_PATH/"
    
    # Compress the copy
    local archive_name=$(get_timestamp)
    local archive_path="$BACKUP_PATH/${archive_name}.tar.gz"
    
    print_info "Compressing $copy_path to $archive_path..."
    tar -czf "$archive_path" -C "$(dirname "$copy_path")" "$(basename "$copy_path")"
    
    print_success "Compression completed successfully"
    
    # Remove the copy that isn't compressed
    print_info "Removing copy of save folder..."
    rm -rf "$copy_path"
    
    print_success "Backup created successfully: ${CYAN}$archive_path${NC}"
}

# Prunes old backups to maintain only the specified number
prune_old_backups() {
    # Skip if MAX_BACKUPS is 0 or less
    if [ "$MAX_BACKUPS" -le 0 ]; then
        return
    fi
    
    # List all backup files sorted by modification time (newest first)
    local backup_files=($(ls -t "$BACKUP_PATH"/*.tar.gz 2>/dev/null))
    local backup_count=${#backup_files[@]}
    
    print_info "Found $backup_count backup files"
    
    # Delete older backups if exceeding max limit
    if [ "$backup_count" -gt "$MAX_BACKUPS" ]; then
        local files_to_remove=$((backup_count - MAX_BACKUPS))
        print_info "Removing $files_to_remove old backups..."
        
        for ((i=MAX_BACKUPS; i<backup_count; i++)); do
            print_warning "Removing old backup: ${backup_files[$i]}"
            rm -f "${backup_files[$i]}"
        done
    fi
    
    print_success "Backup cleanup completed"
}

# Main backup process
main() {
    print_header "🚀 Starting ARK Server backup process..."
    
    # Check required environment variables
    if ! check_env_variables BACKUP_REQUIRED_VARS 0; then        
        exit 1
    fi
    
    # Check optional environment variables (warnings only)
    check_env_variables BACKUP_OPTIONAL_VARS 1
    
    create_backup_path_if_not_exists
    
    # Create and compress backup
    create_backup
    
    # Clean up old backups
    prune_old_backups
    
    # Log success
    print_header "✅ Backup completed successfully"
}

# Execute the backup
main || {
    print_header "❌ Backup failed: $?"
    exit 1
} 