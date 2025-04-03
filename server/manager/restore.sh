#!/bin/bash
#
# ARK Server Restore Backup Utility
# Restores a selected backup archive to the ARK saved game data
#
# Usage: ./restoreBackup.sh [options]
# Options:
#   --file <path>       Specify backup file to restore
#   --force             Skip confirmation prompts
#   --no-server-check   Skip checking if server is running
#   --keep-temp         Keep temporary files after restore
#   --help              Display this help message
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

SAVED_DIR="$ARK_DIR/ShooterGame/Saved"
TEMP_EXTRACT_PATH="$BACKUP_PATH/temp-extract"
RESTORE_FLAG_FILE="${ARK_DIR}/restore_in_progress.flag" # Flag file to indicate restore is in progress

# Define required and optional environment variables for backup
declare -a BACKUP_REQUIRED_VARS=(
    "ARK_DIR"     # ARK installation directory
    "BACKUP_PATH" # Path to store backups
    "MANAGER_DIR" # Manager scripts directory
)

# Define optional environment variables
declare -a BACKUP_OPTIONAL_VARS=(
    "BACKUP_NAME_PREFIX" # Prefix for backup filenames
    "RESTORE_TIMEOUT"    # Timeout for restore operations
)

# Default values
BACKUP_NAME_PREFIX=${BACKUP_NAME_PREFIX:-"ark-backup"}
RESTORE_TIMEOUT=${RESTORE_TIMEOUT:-300} # 5 minutes timeout for restore operations

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Function to display a spinner with a message
declare -a SPINNER=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
SPINNER_IDX=0

show_spinner() {
    local message="$1"
    local current_spinner=${SPINNER[$SPINNER_IDX]}
    SPINNER_IDX=$(((SPINNER_IDX + 1) % ${#SPINNER[@]}))

    printf "\r${current_spinner} ${message}"
}

# Function to create restore flag file
create_restore_flag() {
    echo "$(date) - Restore started by PID $$" >"$RESTORE_FLAG_FILE"
    print_success "✅ Created restore flag: $RESTORE_FLAG_FILE"
}

# Function to remove restore flag file
remove_restore_flag() {
    if [[ -f "$RESTORE_FLAG_FILE" ]]; then
        rm -f "$RESTORE_FLAG_FILE"
        print_success "✅ Removed restore flag"
    fi
}

# Function for cleanup on script exit
cleanup() {
    local exit_code=$?

    # Remove restore flag
    remove_restore_flag

    # Cleanup temp files if KEEP_TEMP is not set
    if [[ "$KEEP_TEMP" != "yes" && -d "$TEMP_EXTRACT_PATH" ]]; then
        print_info "Cleaning up temporary files..."
        rm -rf "$TEMP_EXTRACT_PATH"
    fi

    print_info "Restore script exiting with code: $exit_code"
    exit $exit_code
}

# =============================================================================
# RESTORE FUNCTIONS
# =============================================================================

# Lists available backup files with numbers
list_backup_files() {
    print_header "Available backup archives:"

    # Check if backup directory exists
    if [ ! -d "$BACKUP_PATH" ]; then
        print_error "❌ Backup directory $BACKUP_PATH does not exist."
        return 1
    fi

    # Get all backup files ending with .tar.gz
    local backup_files=($(find "$BACKUP_PATH" -name "*.tar.gz" -type f | sort -r))

    if [ "${#backup_files[@]}" -eq 0 ]; then
        print_warning "⚠️ No backup archives found."
        return 1
    fi

    # Display backups with numbers
    local index=1
    for file in "${backup_files[@]}"; do
        filename=$(basename "$file")
        # Extract date and time from filename for better display
        if [[ $filename =~ ([0-9]{4}-[0-9]{2}-[0-9]{2})_([0-9]{2}-[0-9]{2}-[0-9]{2}) ]]; then
            date_part="${BASH_REMATCH[1]}"
            time_part="${BASH_REMATCH[2]}"
            size=$(du -h "$file" | cut -f1)
            echo -e "${BOLD}\033[0;35m$index)${NC} ${CYAN}$filename${NC} ${YELLOW}[$date_part at ${time_part//-/:}]${NC} ${GREEN}$size${NC}"
        else
            size=$(du -h "$file" | cut -f1)
            echo -e "${BOLD}\033[0;35m$index)${NC} ${CYAN}$filename${NC} ${GREEN}$size${NC}"
        fi
        index=$((index + 1))
    done

    echo ""
    return 0
}

# Check if server is running and prompt to stop if needed
ensure_server_stopped() {
    if [[ "$NO_SERVER_CHECK" == "yes" ]]; then
        print_info "Skipping server status check (--no-server-check option)"
        return 0
    fi

    print_info "Checking server status..."
    local ark_server_pid=$(get_ark_server_pid)

    # Check if server is running
    if [[ "$ark_server_pid" != "0" ]]; then
        print_warning "⚠️ ARK server is currently running (PID: $ark_server_pid)"

        if [[ "$FORCE" == "yes" ]]; then
            print_warning "Force option enabled - stopping server automatically"

            if ! "${MANAGER_DIR}/stop.sh" --force; then
                print_error "❌ Failed to stop server"
                return 1
            fi

            print_success "✅ Server stopped successfully"
            return 0
        fi

        echo -e "${BOLD}${YELLOW}Server needs to be stopped before restoring a backup.${NC}"
        echo -e "${BOLD}Do you want to stop the server now? (y/N):${NC} \c"
        read -r answer

        if [[ "${answer,,}" == "y" ]]; then
            print_info "Stopping server..."

            if ! "${MANAGER_DIR}/stop.sh"; then
                print_error "❌ Failed to stop server"
                return 1
            fi

            print_success "✅ Server stopped successfully"
            return 0
        else
            print_warning "⚠️ Cannot proceed with backup restoration while the server is running"
            return 1
        fi
    fi

    print_success "✅ Server is not running, can proceed with restore"
    return 0
}

# Global variable to store selected backup
SELECTED_BACKUP_PATH=""
SELECTED_BACKUP_FILENAME=""

# Prompts the user to select a backup file and sets the global variable
select_backup() {
    # If backup is already specified via command line, use that
    if [[ -n "$SPECIFY_FILE" ]]; then
        if [[ -f "$SPECIFY_FILE" ]]; then
            SELECTED_BACKUP_PATH="$SPECIFY_FILE"
            SELECTED_BACKUP_FILENAME=$(basename "$SPECIFY_FILE")
            print_success "✅ Using specified backup file: $SELECTED_BACKUP_FILENAME"
            return 0
        else
            print_error "❌ Specified backup file does not exist: $SPECIFY_FILE"
            return 1
        fi
    fi

    # Get all backup files
    local backup_files=($(find "$BACKUP_PATH" -name "*.tar.gz" -type f | sort -r))
    local backup_count=${#backup_files[@]}

    # Check if any backups exist
    if [ "$backup_count" -eq 0 ]; then
        print_warning "⚠️ No backup archives found."
        return 1
    fi

    # Display prompt for selection
    print_info "Enter the number of the backup you want to restore (1-$backup_count):"
    echo -e "${CYAN}> ${NC}\c"

    # Get user input
    read -r selection
    echo "" # Add a newline after input

    # Validate input
    if ! [[ "$selection" =~ ^[0-9]+$ ]]; then
        print_error "❌ Invalid selection. Please enter a valid number."
        return 1
    fi

    local selected_index=$((selection - 1))

    if [ "$selected_index" -lt 0 ] || [ "$selected_index" -ge "$backup_count" ]; then
        print_error "❌ Invalid selection. Please enter a number between 1 and $backup_count."
        return 1
    fi

    # Set the global variable instead of returning a value
    SELECTED_BACKUP_PATH="${backup_files[$selected_index]}"
    SELECTED_BACKUP_FILENAME=$(basename "$SELECTED_BACKUP_PATH")
    print_success "✅ You selected: ${CYAN}$SELECTED_BACKUP_FILENAME${NC}"
    return 0
}

# Confirms with the user before restoring
confirm_restore() {
    # If force option is enabled, skip confirmation
    if [[ "$FORCE" == "yes" ]]; then
        print_info "Force option enabled - skipping confirmation prompt"
        return 0
    fi

    print_warning "⚠️ Warning: Restoring backup ${CYAN}$SELECTED_BACKUP_FILENAME${NC}${YELLOW} will overwrite current saved data!${NC}"
    echo -e "${BOLD}${YELLOW}Are you sure you want to proceed? (y/N):${NC} \c"

    read -r answer

    if [[ "${answer,,}" == "y" ]]; then
        return 0
    else
        print_warning "⚠️ Restoration cancelled by user"
        return 1
    fi
}

# Backup the current data before restoring
backup_current_data() {
    # If force option is enabled or current data doesn't exist, skip backup
    if [[ "$FORCE" == "yes" || ! -d "$SAVED_DIR" ]]; then
        return 0
    fi

    print_info "Would you like to backup the current data before restoring? (y/N): \c"
    read -r answer

    if [[ "${answer,,}" == "y" ]]; then
        print_info "Creating backup of current data before restore..."

        # Create a temporary backup of current data
        local timestamp=$(date +"%Y-%m-%d_%H-%M-%S")
        local backup_name="pre-restore-${timestamp}.tar.gz"
        local backup_path="$BACKUP_PATH/$backup_name"

        print_info "Backing up current data to $backup_path..."

        # Create tar archive of current data
        if tar -czf "$backup_path" -C "$ARK_DIR/ShooterGame" Saved 2>/dev/null; then
            print_success "✅ Current data backed up successfully"
            return 0
        else
            print_error "❌ Failed to backup current data"

            print_info "Would you like to continue without backing up? (y/N): \c"
            read -r continue_answer

            if [[ "${continue_answer,,}" == "y" ]]; then
                return 0
            else
                print_warning "⚠️ Restoration cancelled - could not backup current data"
                return 1
            fi
        fi
    fi

    return 0
}

# Ensures parent directory structure exists
ensure_parent_directory_exists() {
    local target_dir="$1"

    print_info "Creating parent directory structure if needed..."
    local parent_dir=$(dirname "$target_dir")

    if [ ! -d "$parent_dir" ]; then
        print_warning "⚠️ Parent directory $parent_dir doesn't exist, creating..."
        mkdir -p "$parent_dir"

        if [ ! -d "$parent_dir" ]; then
            print_error "❌ Failed to create parent directory"
            return 1
        fi
    fi

    return 0
}

# Extracts archive directly to target location
extract_directly_to_target() {
    local archive_path="$1"
    local target_dir="$2"

    print_info "Extracting directly to final location..."

    # Create a temporary error log file
    local error_log="/tmp/tar_error.$(date +%s).log"

    # Start tar extraction in background to show progress
    (tar -xzf "$archive_path" -C "$(dirname "$target_dir")" 2>"$error_log") &
    local tar_pid=$!

    # Monitor the extraction process
    local elapsed=0
    while kill -0 $tar_pid 2>/dev/null; do
        show_spinner "Extracting backup... (${elapsed}s elapsed)"
        sleep 1
        elapsed=$((elapsed + 1))

        # Check if we've hit the timeout
        if [[ $elapsed -gt $RESTORE_TIMEOUT ]]; then
            print_error "❌ Extraction timed out after ${RESTORE_TIMEOUT}s"
            kill -9 $tar_pid 2>/dev/null
            wait $tar_pid 2>/dev/null
            return 1
        fi
    done

    # Wait for tar to finish and get exit status
    wait $tar_pid
    local tar_status=$?
    echo "" # Add newline after spinner

    if [[ $tar_status -eq 0 ]]; then
        print_success "✅ Archive extracted successfully to final location"
        rm -f "$error_log" 2>/dev/null
        return 0
    else
        local error_msg=$(cat "$error_log" 2>/dev/null)
        print_error "❌ Direct extraction failed: $error_msg"
        rm -f "$error_log" 2>/dev/null
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

    # Create a temporary error log file
    local error_log="/tmp/tar_error.$(date +%s).log"

    # Start tar extraction in background to show progress
    (tar -xzf "$archive_path" -C "$extract_path" 2>"$error_log") &
    local tar_pid=$!

    # Monitor the extraction process
    local elapsed=0
    while kill -0 $tar_pid 2>/dev/null; do
        show_spinner "Extracting to temporary location... (${elapsed}s elapsed)"
        sleep 1
        elapsed=$((elapsed + 1))

        # Check if we've hit the timeout
        if [[ $elapsed -gt $RESTORE_TIMEOUT ]]; then
            print_error "❌ Extraction timed out after ${RESTORE_TIMEOUT}s"
            kill -9 $tar_pid 2>/dev/null
            wait $tar_pid 2>/dev/null
            return 1
        fi
    done

    # Wait for tar to finish and get exit status
    wait $tar_pid
    local tar_status=$?
    echo "" # Add newline after spinner

    if [[ $tar_status -eq 0 ]]; then
        print_success "✅ Archive extracted successfully to temporary location"
        rm -f "$error_log" 2>/dev/null
        return 0
    else
        local error_msg=$(cat "$error_log" 2>/dev/null)
        print_error "❌ Extraction failed: $error_msg"
        rm -f "$error_log" 2>/dev/null
        return 1
    fi
}

# Cleans up temporary extraction directory
cleanup_temp_directory() {
    if [[ "$KEEP_TEMP" == "yes" ]]; then
        print_info "Keeping temporary files (--keep-temp option)"
        return 0
    fi

    print_info "Cleaning up temporary files..."
    if [ -d "$TEMP_EXTRACT_PATH" ]; then
        rm -rf "$TEMP_EXTRACT_PATH"
        print_success "✅ Temporary files cleaned up"
    fi
}

# Verifies the restored files and permissions
verify_restore() {
    print_info "Verifying restored files..."

    # Check if key directories exist after restore
    local required_dirs=("SavedArks" "Config")
    local missing_dirs=()

    for dir in "${required_dirs[@]}"; do
        if [[ ! -d "$SAVED_DIR/$dir" ]]; then
            missing_dirs+=("$dir")
        fi
    done

    if [[ ${#missing_dirs[@]} -gt 0 ]]; then
        print_warning "⚠️ Some important directories are missing after restore: ${missing_dirs[*]}"
        print_warning "⚠️ The backup may not have been complete"
    else
        print_success "✅ All required directories are present"
    fi

    # Fix permissions if needed
    print_info "Setting appropriate permissions on restored files..."
    chmod -R u+rwX "$SAVED_DIR" 2>/dev/null

    return 0
}

# Restores a backup archive to the saved directory
restore_backup() {
    local archive_path="$SELECTED_BACKUP_PATH"

    # Create restore flag to indicate restore is in progress
    create_restore_flag

    echo "" # Add a newline for visual separation
    print_header "📦 Restoring Backup: ${CYAN}$(basename "$archive_path")${NC}"

    # Extract archive to temp folder
    print_info "📤 Step 1/4: Extracting backup to temporary location..."
    if ! extract_archive "$archive_path" "$TEMP_EXTRACT_PATH"; then
        print_error "❌ Failed to extract backup to temporary location."
        cleanup_temp_directory
        return 1
    fi

    # Ensure parent directories exist
    print_info "📥 Step 2/4: Preparing target directory structure..."
    if ! ensure_parent_directory_exists "$SAVED_DIR"; then
        print_error "❌ Failed to create directory structure."
        cleanup_temp_directory
        return 1
    fi

    # Remove existing saved directory if it exists
    if [[ -d "$SAVED_DIR" ]]; then
        print_warning "⚠️ Preparing to restore existing saved directory..."

        # First try to preserve the logs directory if it exists and might be in use
        local logs_dir="$SAVED_DIR/Logs"
        local logs_backup_dir="${TEMP_EXTRACT_PATH}/logs_backup"

        if [[ -d "$logs_dir" ]]; then
            print_info "Logs directory exists, attempting to preserve it..."
            mkdir -p "$logs_backup_dir"

            # Try to move log files without removing directory
            find "$logs_dir" -type f -name "*.log" -print0 | xargs -0 -I{} cp -f {} "$logs_backup_dir/" 2>/dev/null || true
            print_info "Log files preserved if possible"
        fi

        # Remove all directories except Logs
        print_info "Removing saved game directories (except Logs if busy)..."
        for dir in "$SAVED_DIR"/*; do
            if [[ -d "$dir" && "$(basename "$dir")" != "Logs" ]]; then
                rm -rf "$dir"
                if [[ $? -ne 0 ]]; then
                    print_error "❌ Failed to remove directory: $dir"
                    cleanup_temp_directory
                    return 1
                fi
            fi
        done

        # Handle SavedArks directory specifically since it's the most important
        rm -rf "$SAVED_DIR/SavedArks" 2>/dev/null
        if [[ -d "$SAVED_DIR/SavedArks" ]]; then
            print_error "❌ Failed to remove SavedArks directory, cannot proceed with restore"
            cleanup_temp_directory
            return 1
        fi

        print_success "✅ Existing directories cleaned up"
    fi

    print_info "📁 Step 3/4: Restoring to game directory..."
    if ! extract_directly_to_target "$archive_path" "$SAVED_DIR"; then
        print_error "❌ Failed to restore backup to final location."
        cleanup_temp_directory
        return 1
    fi

    # Restore log files if they were preserved
    local logs_backup_dir="${TEMP_EXTRACT_PATH}/logs_backup"
    if [[ -d "$logs_backup_dir" && -d "$SAVED_DIR/Logs" ]]; then
        print_info "Restoring preserved log files..."
        find "$logs_backup_dir" -type f -name "*.log" -print0 | xargs -0 -I{} cp -f {} "$SAVED_DIR/Logs/" 2>/dev/null || true
    fi

    # Verify the restored files
    print_info "🔍 Step 4/4: Verifying restored files..."
    verify_restore

    # Clean up and report success
    cleanup_temp_directory

    # Remove restore flag
    remove_restore_flag

    echo "" # Add a newline for visual separation
    print_success "✅ Backup restored successfully!"

    return 0
}

# =============================================================================
# COMMAND LINE PARSING
# =============================================================================

# Parse command line arguments
parse_arguments() {
    FORCE="no"
    NO_SERVER_CHECK="no"
    KEEP_TEMP="no"
    SPECIFY_FILE=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
        --file)
            if [[ -n "$2" && ! "$2" =~ ^-- ]]; then
                SPECIFY_FILE="$2"
                shift 2
            else
                print_error "❌ --file requires a file path argument"
                exit 1
            fi
            ;;
        --force)
            FORCE="yes"
            shift
            ;;
        --no-server-check)
            NO_SERVER_CHECK="yes"
            shift
            ;;
        --keep-temp)
            KEEP_TEMP="yes"
            shift
            ;;
        --help)
            echo "Usage: ./restoreBackup.sh [options]"
            echo "Options:"
            echo "  --file <path>       Specify backup file to restore"
            echo "  --force             Skip confirmation prompts"
            echo "  --no-server-check   Skip checking if server is running"
            echo "  --keep-temp         Keep temporary files after restore"
            echo "  --help              Display this help message"
            exit 0
            ;;
        *)
            print_warning "⚠️ Unknown option: $1"
            shift
            ;;
        esac
    done
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

# Set up trap to call cleanup on exit
trap cleanup EXIT INT TERM

# Main function to run the restore process
main() {
    clear # Start with a clean screen
    print_header "🔄 ARK Server Backup Restoration Tool"
    echo ""

    # Parse command line arguments
    parse_arguments "$@"

    # Check required environment variables
    if ! check_env_variables BACKUP_REQUIRED_VARS 0; then
        print_error "❌ Missing required environment variables"
        exit 1
    fi

    # Check optional environment variables
    check_env_variables BACKUP_OPTIONAL_VARS 1

    # Check if server is running
    if ! ensure_server_stopped; then
        exit 1
    fi

    echo "" # Add a newline for visual separation

    # List available backups if we're not using a specified file
    if [[ -z "$SPECIFY_FILE" ]]; then
        if ! list_backup_files; then
            print_error "❌ No backups available to restore"
            exit 1
        fi
    fi

    # Select the backup to restore
    if ! select_backup; then
        print_error "❌ Failed to select a backup"
        exit 1
    fi

    # Confirm restoration
    if ! confirm_restore; then
        exit 0
    fi

    # Backup current data if requested
    if ! backup_current_data; then
        exit 1
    fi

    # Restore the selected backup
    if ! restore_backup; then
        print_error "❌ Restore failed"
        exit 1
    fi

    # Provide instructions for starting the server
    echo ""
    print_info "📝 Next Steps:"
    print_info "1. Your server data has been restored successfully"
    print_info "2. To start the server, run: ${MANAGER_DIR}/start.sh"
    print_info "3. Check logs after starting to ensure everything is working correctly"

    exit 0
}

# Execute the restore process
main "$@"
