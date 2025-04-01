#!/bin/bash
#
# ARK Server Restore Backup Utility
# Restores a selected backup archive to the ARK saved game data

# Load environment variables and utilities
UTILS_PATH="$MANAGER_DIR/utils"

source "${UTILS_PATH}/colorPrinter.sh"
source "${UTILS_PATH}/serverStatus.sh"
source "${UTILS_PATH}/envManager.sh"

SAVED_DIR="$ARK_DIR/ShooterGame/Saved"
TEMP_EXTRACT_PATH="$BACKUP_PATH/temp-extract"

# Define required and optional environment variables for backup
declare -a BACKUP_REQUIRED_VARS=(
    "ARK_DIR"
    "BACKUP_PATH"
    "MANAGER_DIR"
)

# Lists available backup files with numbers
list_backup_files() {
    print_header "Available backup archives:"

    # Check if backup directory exists
    if [ ! -d "$BACKUP_PATH" ]; then
        print_error "Backup directory $BACKUP_PATH does not exist."
        exit 1
    fi

    # Get all backup files ending with .tar.gz
    local backup_files=($(find "$BACKUP_PATH" -name "*.tar.gz" -type f | sort -r))

    if [ "${#backup_files[@]}" -eq 0 ]; then
        print_warning "No backup archives found."
        exit 0
    fi

    # Display backups with numbers
    local index=1
    for file in "${backup_files[@]}"; do
        filename=$(basename "$file")
        # Extract date and time from filename for better display
        if [[ $filename =~ ([0-9]{4}-[0-9]{2}-[0-9]{2})_([0-9]{2}-[0-9]{2}-[0-9]{2}) ]]; then
            date_part="${BASH_REMATCH[1]}"
            time_part="${BASH_REMATCH[2]}"
            echo -e "${BOLD}\033[0;35m$index)${NC} ${CYAN}$filename${NC} ${YELLOW}[$date_part at ${time_part//-/:}]${NC}"
        else
            echo -e "${BOLD}\033[0;35m$index)${NC} ${CYAN}$filename${NC}"
        fi
        index=$((index + 1))
    done

    echo ""
    return 0
}

# Main function to run the restore process
main() {
    clear # Start with a clean screen
    print_header "🔄 ARK Server Backup Restoration Tool"
    echo ""

    # Check required environment variables
    if ! check_env_variables BACKUP_REQUIRED_VARS 0; then        
        exit 1
    fi
    
    # Check if server is running
    print_info "Checking server status..."
    if ! ensure_server_stopped; then
        print_error "${BOLD}❌ Cannot proceed with backup restoration while the server is running."
        print_warning "Please stop the ARK server first and try again."
        exit 1
    fi
    
    echo "" # Add a newline for visual separation
    
    # List available backups
    list_backup_files
    
    # Using direct function calls instead of command substitution
    # for better control of prompts and output
    select_backup
    
    # No need to capture output since we store it in a global variable
    if ! confirm_restore; then
        echo "" # Add a newline for visual separation
        print_warning "Restoration cancelled by user."
        exit 0
    fi
    
    # Restore the selected backup
    restore_backup "$SELECTED_BACKUP_FILENAME"
}

# Global variable to store selected backup
SELECTED_BACKUP_FILENAME=""

# Prompts the user to select a backup file and sets the global variable
select_backup() {
    local backup_files=($(find "$BACKUP_PATH" -name "*.tar.gz" -type f | sort -r))
    local backup_count=${#backup_files[@]}
    
    # Check if any backups exist
    if [ "$backup_count" -eq 0 ]; then
        print_warning "No backup archives found."
        exit 0
    fi
    
    # Display prompt for selection
    print_info "Enter the number of the backup you want to restore (1-$backup_count):"
    echo -e "${CYAN}> ${NC}\c"
    
    # Get user input
    read -r selection
    echo "" # Add a newline after input
    
    # Validate input
    if ! [[ "$selection" =~ ^[0-9]+$ ]]; then
        print_error "Invalid selection. Please enter a valid number."
        exit 1
    fi
    
    local selected_index=$((selection - 1))
    
    if [ "$selected_index" -lt 0 ] || [ "$selected_index" -ge "$backup_count" ]; then
        print_error "Invalid selection. Please enter a number between 1 and $backup_count."
        exit 1
    fi
    
    local selected_file=${backup_files[$selected_index]}
    if [ -z "$selected_file" ]; then
        print_error "Selected backup not found."
        exit 1
    fi
    
    # Set the global variable instead of returning a value
    SELECTED_BACKUP_FILENAME=$(basename "$selected_file")
    print_success "You selected: ${CYAN}$SELECTED_BACKUP_FILENAME${NC}"
    return 0
}

# Confirms with the user before restoring
confirm_restore() {
    local selected_backup="$SELECTED_BACKUP_FILENAME"
    
    print_warning "⚠️  Warning: Restoring backup ${CYAN}$selected_backup${NC}${YELLOW} will overwrite current saved data!${NC}"
    echo -e "${BOLD}${YELLOW}Are you sure you want to proceed? (y/N): ${NC}\c"
    
    read -r answer
    
    if [[ "${answer,,}" == "y" ]]; then
        return 0
    else
        return 1
    fi
}

# Ensures parent directory structure exists
ensure_parent_directory_exists() {
    local target_dir="$1"
    
    print_info "Creating parent directory structure if needed..."
    local parent_dir=$(dirname "$target_dir")
    
    if [ ! -d "$parent_dir" ]; then
        print_warning "Parent directory $parent_dir doesn't exist, creating..."
        mkdir -p "$parent_dir"
    fi
}

# Extracts archive directly to target location
extract_directly_to_target() {
    local archive_path="$1"
    local target_dir="$2"
    
    print_info "Extracting directly to final location..."
    
    tar -xzf "$archive_path" -C "$(dirname "$target_dir")" 2>/tmp/tar_error.log
    
    if [ $? -eq 0 ]; then
        print_success "Archive extracted successfully to final location"
        return 0
    else
        local error_msg=$(cat /tmp/tar_error.log)
        print_error "Direct extraction failed: $error_msg"
        return 1
    fi
}

# Extracts archive to temporary location
extract_archive() {
    local archive_path="$1"
    local extract_path="$2"
    
    print_info "Extracting ${archive_path} to ${extract_path}..."
    
    # Ensure extract path exists
    if [ ! -d "$extract_path" ]; then
        mkdir -p "$extract_path"
    fi
    
    tar -xzf "$archive_path" -C "$extract_path" 2>/tmp/tar_error.log
    
    if [ $? -eq 0 ]; then
        print_success "Archive extracted successfully"
        return 0
    else
        local error_msg=$(cat /tmp/tar_error.log)
        print_error "Extraction failed: $error_msg"
        return 1
    fi
}

# Cleans up temporary extraction directory
cleanup_temp_directory() {
    print_info "Cleaning up temporary files..."
    if [ -d "$TEMP_EXTRACT_PATH" ]; then
        rm -rf "$TEMP_EXTRACT_PATH"
    fi
}

# Restores a backup archive to the saved directory
restore_backup() {
    local selected_backup="$1"
    local archive_path="$BACKUP_PATH/$selected_backup"
    
    # Check if archive exists
    if [ ! -f "$archive_path" ]; then
        print_error "Backup archive $archive_path does not exist."
        exit 1
    fi
    
    echo "" # Add a newline for visual separation
    print_header "📦 Restoring Backup: ${CYAN}$selected_backup${NC}"
    
    # Extract archive to temp folder
    print_info "📤 Step 1/3: Extracting backup to temporary location..."
    if ! extract_archive "$archive_path" "$TEMP_EXTRACT_PATH"; then
        print_error "${BOLD}❌ Failed to extract backup to temporary location."
        cleanup_temp_directory
        exit 1
    fi
    
    # Ensure parent directories exist then extract directly
    print_info "📥 Step 2/3: Preparing target directory structure..."
    ensure_parent_directory_exists "$SAVED_DIR"
    
    print_info "📁 Step 3/3: Restoring to game directory..."
    if ! extract_directly_to_target "$archive_path" "$SAVED_DIR"; then
        print_error "${BOLD}❌ Failed to restore backup to final location."
        cleanup_temp_directory
        exit 1
    fi
    
    # Clean up and report success
    cleanup_temp_directory
    echo "" # Add a newline for visual separation
    print_success "${BOLD}✅ Backup restored successfully!"
}

# Execute the restore process
main "$@"
