#!/bin/bash
# ARK Server Restore Utility
# Restores a selected backup archive to the ARK saved game data
#
# =============================================================================

# Load utilities
UTILS_PATH="$MANAGER_DIR/utils"
source "${UTILS_PATH}/common.sh"

# =============================================================================
# CONFIGURATION
# =============================================================================

# Required environment variables for restore
declare -a REQUIRED_VARS=(
    "ARK_DIR"     # ARK installation directory
    "BACKUP_PATH" # Path to store backups
    "MANAGER_DIR" # Manager scripts directory
)

# Optional environment variables
declare -a OPTIONAL_VARS=(
    "BACKUP_NAME_PREFIX" # Prefix for backup filenames
)

# Default values for optional variables
set_default_values() {
    BACKUP_NAME_PREFIX=${BACKUP_NAME_PREFIX:-"ark-backup"}
    RESTORE_FLAG_FILE="${ARK_DIR}/restore_in_progress.flag"
}

# Function to create restore flag file
create_restore_flag() {
    echo "$(date) - Restore started by PID $$" >"$RESTORE_FLAG_FILE"
    print_success "✅ Created restore flag: $RESTORE_FLAG_FILE"
}

# Function to remove restore flag file
remove_restore_flag() {
    [ -f "$RESTORE_FLAG_FILE" ] && rm -f "$RESTORE_FLAG_FILE" && print_success "✅ Removed restore flag"
}

# Function for cleanup on script exit
cleanup() {
    remove_restore_flag
    print_info "Restore script exiting with code: $?"
}

# Set trap to call cleanup on exit
trap cleanup EXIT INT TERM

# =============================================================================
# RESTORE FUNCTIONS
# =============================================================================

# Check if server is running
check_server_status() {
    print_info "Checking server status..."
    local ark_server_pid=$(get_ark_server_pid)

    # Check if server is running
    if [ "$ark_server_pid" != "0" ]; then
        print_error "❌ ARK server is currently running"
        print_warning "⚠️ Please stop the server first with 'ark stop' command"
        return 1
    fi

    print_success "✅ Server is not running, can proceed with restore"
    return 0
}

# List and select backup to restore
select_backup() {
    print_script_header "📋 Available backups:"
    echo ""

    # Check if backup directory exists
    if [ ! -d "$BACKUP_PATH" ]; then
        print_error "❌ Backup directory does not exist: $BACKUP_PATH"
        return 1
    fi

    # List all backup files
    local backup_files=($(find "$BACKUP_PATH" -name "${BACKUP_NAME_PREFIX}-*.tar.gz" -type f -printf "%T@ %p\n" | sort -rn | cut -d' ' -f2))
    local backup_count=${#backup_files[@]}

    # Check if any backups exist
    if [ "$backup_count" -eq 0 ]; then
        print_error "❌ No backup archives found"
        return 1
    fi

    # Display backups with numbers
    for ((i = 0; i < backup_count; i++)); do
        local file="${backup_files[$i]}"
        local filename=$(basename "$file")
        local filesize=$(du -h "$file" | cut -f1)
        local file_date=$(date -r "$file" "+%Y-%m-%d %H:%M:%S")

        echo -e "  ${BOLD}${MAGENTA}$(($i + 1)))${NC} ${CYAN}$filename${NC} ${GREEN}($filesize)${NC} ${YELLOW}- $file_date${NC}"
    done

    echo ""
    print_info "Enter the number of the backup to restore (1-$backup_count):"
    echo -e -n "${CYAN}> ${NC}"
    read -r selection

    # Validate input
    if ! [[ "$selection" =~ ^[0-9]+$ ]]; then
        print_error "❌ Invalid selection. Please enter a number."
        return 1
    fi

    if [ "$selection" -lt 1 ] || [ "$selection" -gt "$backup_count" ]; then
        print_error "❌ Invalid selection. Please enter a number between 1 and $backup_count."
        return 1
    fi

    # Get selected backup path
    local selected_index=$((selection - 1))
    SELECTED_BACKUP="${backup_files[$selected_index]}"
    SELECTED_BACKUP_NAME=$(basename "$SELECTED_BACKUP")

    print_success "✅ Selected backup: ${CYAN}$SELECTED_BACKUP_NAME${NC}"
    return 0
}

# Confirm before restoring
confirm_restore() {
    print_warning "⚠️ WARNING: This will overwrite ALL current game data!"
    echo ""
    print_info "Are you sure you want to restore this backup? (y/N): "
    read -r confirm

    if [[ "${confirm,,}" != "y" ]]; then
        print_warning "⚠️ Restore cancelled by user"
        return 1
    fi

    return 0
}

# Restore the selected backup
restore_backup() {
    print_script_header "🔄 Restoring backup: $SELECTED_BACKUP_NAME"
    echo ""

    # Create flag file to indicate restore is in progress
    create_restore_flag

    # Create saved directory if it doesn't exist
    local saved_dir="$ARK_DIR/ShooterGame/Saved"
    if [ ! -d "$saved_dir" ]; then
        print_info "Creating Saved directory..."
        mkdir -p "$saved_dir"
    fi

    # Backup the current saved directory for safety
    if [ -d "$saved_dir" ] && [ "$(ls -A "$saved_dir" 2>/dev/null)" ]; then
        print_info "Creating safety backup of current data..."
        local timestamp=$(date +"%Y-%m-%d_%H-%M-%S")
        local safety_backup="$BACKUP_PATH/pre-restore-$timestamp.tar.gz"

        tar -czf "$safety_backup" -C "$ARK_DIR/ShooterGame" Saved &>/dev/null
        print_success "✅ Safety backup created: $(basename "$safety_backup")"
    fi

    # Prepare for restore - clear existing saved directory
    print_info "Preparing to restore backup..."
    rm -rf "$saved_dir"/* 2>/dev/null

    # Extract the backup
    print_info "Extracting backup (this may take a while)..."

    # Start extraction and show progress
    (tar -xzf "$SELECTED_BACKUP" -C "$ARK_DIR/ShooterGame" 2>/dev/null) &
    local tar_pid=$!

    # Show spinner while extracting
    local elapsed=0
    while kill -0 $tar_pid 2>/dev/null; do
        loading "Restoring backup... (${elapsed}s elapsed)"
        sleep 1
        elapsed=$((elapsed + 1))
    done
    echo "" # Add newline after spinner

    # Check if extraction was successful
    wait $tar_pid
    local tar_status=$?

    if [ $tar_status -ne 0 ]; then
        print_error "❌ Failed to extract backup"
        return 1
    fi

    # Set proper permissions
    print_info "Setting proper permissions..."
    chmod -R u+rwX "$saved_dir" 2>/dev/null

    print_success "✅ Backup restored successfully!"
    print_info "You can now start the server with 'ark start'"
    return 0
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

# Main restore process
main() {
    print_script_header "🚀 ARK Server Restore Utility"
    echo ""

    # Check required environment variables
    check_required_env REQUIRED_VARS || exit 1

    # Check optional environment variables
    check_optional_env OPTIONAL_VARS

    # Set default values
    set_default_values

    # Check if server is stopped
    check_server_status || exit 1

    # Select backup to restore
    select_backup || exit 1

    # Confirm before proceeding
    confirm_restore || exit 1

    # Restore the selected backup
    restore_backup || {
        print_error "❌ Restore failed"
        exit 1
    }

    print_success "✅ Restore process completed successfully"
    return 0
}

# Execute the restore
main "$@" || {
    print_error "❌ Restore failed: $?"
    exit 1
}
