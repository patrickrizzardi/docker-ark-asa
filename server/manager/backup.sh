#!/bin/bash

# ARK Server Backup Utility
# Creates compressed backups of the ARK saved game data
#
# Usage: ./backup.sh [options]
# Options:
#   --save-and-backup  Saves the world and creates backup without stopping server
#   --force-stop       Stops the server for backup and then restarts it
#   --skip-prune       Skips pruning old backups
#   --quick            Creates a quick backup with less compression
#   --help             Display this help message
#
# =============================================================================

# Ensure the script exits on any error
set -e

# Load utilities
UTILS_PATH="$MANAGER_DIR/utils"
source "${UTILS_PATH}/colorPrinter.sh"
source "${UTILS_PATH}/envManager.sh"
source "${UTILS_PATH}/processManager.sh"

# =============================================================================
# CONFIGURATION
# =============================================================================

# Define required and optional environment variables for backup
declare -a BACKUP_REQUIRED_VARS=(
    "ARK_DIR"     # ARK installation directory
    "BACKUP_PATH" # Path to store backups
    "MAX_BACKUPS" # Maximum number of backups to keep
    "MANAGER_DIR" # Manager scripts directory
)

# Define optional variables with defaults
declare -a BACKUP_OPTIONAL_VARS=(
    "BACKUP_COMPRESSION_LEVEL" # Compression level (1-9)
    "BACKUP_INCLUDE_LOGS"      # Whether to include logs in backup
    "BACKUP_NAME_PREFIX"       # Prefix for backup filenames
)

# Set default values
BACKUP_COMPRESSION_LEVEL=${BACKUP_COMPRESSION_LEVEL:-5}
BACKUP_INCLUDE_LOGS=${BACKUP_INCLUDE_LOGS:-"false"}
BACKUP_NAME_PREFIX=${BACKUP_NAME_PREFIX:-"ark-backup"}
BACKUP_FLAG_FILE="${ARK_DIR}/backup_in_progress.flag" # Flag file to indicate backup is in progress

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

# Creates a formatted timestamp for the backup filename
get_timestamp() {
    date +"%Y-%m-%d_%H-%M-%S"
}

# Function to create backup flag file
create_backup_flag() {
    echo "$(date) - Backup started by PID $$" >"$BACKUP_FLAG_FILE"
    print_success "✅ Created backup flag: $BACKUP_FLAG_FILE"
}

# Function to remove backup flag file
remove_backup_flag() {
    if [[ -f "$BACKUP_FLAG_FILE" ]]; then
        rm -f "$BACKUP_FLAG_FILE"
        print_success "✅ Removed backup flag"
    fi
}

# Function for cleanup on script exit
cleanup() {
    local exit_code=$?

    # Remove backup flag
    remove_backup_flag

    print_info "Backup script exiting with code: $exit_code"
    exit $exit_code
}

# =============================================================================
# BACKUP FUNCTIONS
# =============================================================================

# Creates a backup path if it doesn't exist
create_backup_path_if_not_exists() {
    if [ ! -d "$BACKUP_PATH" ]; then
        print_info "Creating backup directory: $BACKUP_PATH"
        mkdir -p "$BACKUP_PATH"

        if [ ! -d "$BACKUP_PATH" ]; then
            print_error "❌ Failed to create backup directory"
            return 1
        fi

        print_success "✅ Created backup directory: $BACKUP_PATH"
    fi
    return 0
}

# Save world data before backup if server is running
save_world_before_backup() {
    print_info "Checking server status..."
    local ark_server_pid=$(get_ark_server_pid)

    if [[ "$ark_server_pid" != "0" ]]; then
        print_info "Server is running (PID: $ark_server_pid), saving world before backup..."

        # Attempt to save the world using RCON
        if [[ -n "$RCON_PORT" && -n "$ARK_ADMIN_PASSWORD" ]]; then
            print_info "Sending SaveWorld command via RCON..."

            local save_result=$(./rcon.sh "SaveWorld" --silent 2>&1)

            if [[ "$save_result" == *"World Saved"* ]]; then
                print_success "✅ World saved successfully"

                # Wait a moment for save to complete
                print_info "Waiting 5 seconds for save to complete..."
                sleep 5
                return 0
            else
                print_warning "⚠️ SaveWorld command may have failed: $save_result"
            fi
        else
            print_warning "⚠️ RCON not configured, cannot save world before backup"
        fi

        print_warning "⚠️ Using server stop script to save world data"

        # Use the stop script with --save-only option as fallback
        if "${MANAGER_DIR}/stop.sh" --save-only; then
            print_success "✅ World saved successfully using stop script"
            return 0
        else
            print_error "❌ Failed to save world before backup"
            return 1
        fi
    else
        print_info "Server is not running, no need to save world"
        return 0
    fi
}

# Creates a backup of the ARK saved data
create_backup() {
    # Get the backup file name
    local timestamp=$(get_timestamp)
    local archive_name="${BACKUP_NAME_PREFIX}-${timestamp}"
    local archive_path="$BACKUP_PATH/${archive_name}.tar.gz"

    # Create backup flag
    create_backup_flag

    print_header "📦 Creating ARK Server Backup"
    echo ""

    # Determine which directories to include
    print_info "Determining backup content..."
    local saved_dir="$ARK_DIR/ShooterGame/Saved"
    local backup_dirs=("SavedArks" "Config" "clusters")

    # Add logs if configured
    if [[ "$BACKUP_INCLUDE_LOGS" == "true" || "$BACKUP_INCLUDE_LOGS" == "1" || "$BACKUP_INCLUDE_LOGS" == "yes" ]]; then
        backup_dirs+=("Logs")
        print_info "Including logs in backup"
    else
        print_info "Excluding logs from backup"
    fi

    # Building args for tar
    local tar_args=(-cz)

    # Use specified compression level - but don't try to pass it directly to tar
    # as some tar versions don't support the compression level syntax
    if [[ "$BACKUP_COMPRESSION_LEVEL" =~ ^[1-9]$ ]]; then
        # Instead, use the GZIP environment variable to control compression level
        export GZIP="-$BACKUP_COMPRESSION_LEVEL"
        print_info "Using compression level $BACKUP_COMPRESSION_LEVEL via GZIP environment variable"
    fi

    # Add output file
    tar_args+=(-f "$archive_path")

    # Change to saved directory and add specific directories
    tar_args+=(-C "$ARK_DIR/ShooterGame")

    print_info "Preparing to create backup archive..."
    print_info "Backup will include: ${backup_dirs[*]}"

    # Create the backup
    print_info "Creating backup archive: $archive_path"
    local dir_args=()

    # Add each directory with safety checks
    for dir in "${backup_dirs[@]}"; do
        if [[ -d "$saved_dir/$dir" ]]; then
            dir_args+=("Saved/$dir")
        fi
    done

    # Actually run the tar command with progress
    print_info "Creating backup archive... (this may take a while)"
    local backup_size_mb=0
    local tar_error_log="/tmp/tar_error.$(date +%s).log"

    # Start tar in background with progress reporting
    (tar "${tar_args[@]}" "${dir_args[@]}" 2>"$tar_error_log") &
    local tar_pid=$!

    # Monitor the backup file size
    local elapsed=0
    while kill -0 $tar_pid 2>/dev/null; do
        if [[ -f "$archive_path" ]]; then
            local size_bytes=$(stat -c%s "$archive_path" 2>/dev/null || echo 0)
            local size_mb=$(echo "scale=2; $size_bytes / 1048576" | bc)
            show_spinner "Creating backup: ${size_mb}MB written (${elapsed}s elapsed)"
        else
            show_spinner "Preparing backup... (${elapsed}s elapsed)"
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done

    # Check if tar completed successfully
    wait $tar_pid
    local tar_status=$?
    echo "" # Add newline after spinner

    if [[ $tar_status -ne 0 ]]; then
        # Display the error if available
        if [[ -f "$tar_error_log" ]]; then
            local error_content=$(cat "$tar_error_log")
            print_error "❌ Tar error output: $error_content"
        fi
        print_error "❌ Backup creation failed with status $tar_status"
        # Clean up partial archive
        if [[ -f "$archive_path" ]]; then
            rm -f "$archive_path"
        fi
        rm -f "$tar_error_log" 2>/dev/null
        return 1
    fi

    # Clean up error log
    rm -f "$tar_error_log" 2>/dev/null

    # Get final backup size
    if [[ -f "$archive_path" ]]; then
        local size_bytes=$(stat -c%s "$archive_path" 2>/dev/null || echo 0)
        local size_mb=$(echo "scale=2; $size_bytes / 1048576" | bc)
        print_success "✅ Backup created successfully: $archive_path (${size_mb}MB)"
    else
        print_error "❌ Backup file not found after creation"
        return 1
    fi

    # Remove backup flag
    remove_backup_flag

    return 0
}

# Prunes old backups to maintain only the specified number
prune_old_backups() {
    # Skip if MAX_BACKUPS is 0 or less
    if [[ "$MAX_BACKUPS" -le 0 ]]; then
        print_info "Backup pruning disabled (MAX_BACKUPS=$MAX_BACKUPS)"
        return 0
    fi

    print_header "♻️ Pruning Old Backups"

    # List all backup files sorted by modification time (newest first)
    print_info "Listing existing backups..."
    local backup_files=($(find "$BACKUP_PATH" -name "${BACKUP_NAME_PREFIX}-*.tar.gz" -type f -printf "%T@ %p\n" | sort -rn | cut -d' ' -f2))
    local backup_count=${#backup_files[@]}

    print_info "Found $backup_count backup files"

    # Delete older backups if exceeding max limit
    if [[ "$backup_count" -gt "$MAX_BACKUPS" ]]; then
        local files_to_remove=$((backup_count - MAX_BACKUPS))
        print_info "Removing $files_to_remove old backups..."

        for ((i = MAX_BACKUPS; i < backup_count; i++)); do
            local file="${backup_files[$i]}"
            local filename=$(basename "$file")
            local filesize=$(du -h "$file" | cut -f1)

            print_warning "Removing old backup: $filename ($filesize)"
            rm -f "$file"

            if [[ $? -ne 0 ]]; then
                print_error "❌ Failed to remove backup: $file"
            fi
        done

        print_success "✅ Removed $files_to_remove old backups"
    else
        print_info "No backups need to be pruned (count: $backup_count, max: $MAX_BACKUPS)"
    fi

    return 0
}

# =============================================================================
# COMMAND LINE PARSING
# =============================================================================

# Parse command line arguments
parse_arguments() {
    SAVE_AND_BACKUP="no"
    FORCE_STOP="no"
    SKIP_PRUNE="no"
    QUICK_BACKUP="no"

    while [[ $# -gt 0 ]]; do
        case "$1" in
        --save-and-backup)
            SAVE_AND_BACKUP="yes"
            shift
            ;;
        --force-stop)
            FORCE_STOP="yes"
            shift
            ;;
        --skip-prune)
            SKIP_PRUNE="yes"
            shift
            ;;
        --quick)
            QUICK_BACKUP="yes"
            BACKUP_COMPRESSION_LEVEL=1
            shift
            ;;
        --help)
            echo "Usage: ./backup.sh [options]"
            echo "Options:"
            echo "  --save-and-backup  Saves the world and creates backup without stopping server"
            echo "  --force-stop       Stops the server for backup (ignoring save and player checks) and then restarts it"
            echo "  --skip-prune       Skips pruning old backups"
            echo "  --quick            Creates a quick backup with less compression"
            echo "  --help             Display this help message"
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

# Main backup process
main() {
    clear # Start with a clean screen
    print_header "🚀 ARK Server Backup Utility"
    echo ""

    # Parse arguments
    parse_arguments "$@"

    # Check required environment variables
    if ! check_env_variables BACKUP_REQUIRED_VARS 0; then
        print_error "❌ Missing required environment variables"
        exit 1
    fi

    # Check optional environment variables (warnings only)
    check_env_variables BACKUP_OPTIONAL_VARS 1

    # Set quick backup if requested
    if [[ "$QUICK_BACKUP" == "yes" ]]; then
        print_info "Quick backup mode enabled - using faster compression"
        BACKUP_COMPRESSION_LEVEL=1
    fi

    # Create backup directory if needed
    if ! create_backup_path_if_not_exists; then
        print_error "❌ Cannot proceed without backup directory"
        exit 1
    fi

    # Handle server based on options
    if [[ "$FORCE_STOP" == "yes" ]]; then
        # Save server state to use for restart
        SERVER_WAS_RUNNING="no"

        print_info "Checking server status..."
        local ark_server_pid=$(get_ark_server_pid)

        if [[ "$ark_server_pid" != "0" ]]; then
            SERVER_WAS_RUNNING="yes"
            print_info "Server is running (PID: $ark_server_pid), stopping for backup..."

            if ! "${MANAGER_DIR}/stop.sh" --force; then
                print_error "❌ Failed to stop server for backup"
                exit 1
            fi

            print_success "✅ Server stopped for backup"
        fi
    elif [[ "$SAVE_AND_BACKUP" == "yes" ]]; then
        # Save the world without stopping
        if ! save_world_before_backup; then
            print_warning "⚠️ Could not save world before backup"
        fi
    fi

    # Create and compress backup
    if ! create_backup; then
        print_error "❌ Backup failed"

        # Restart server if it was stopped
        if [[ "$FORCE_STOP" == "yes" && "$SERVER_WAS_RUNNING" == "yes" ]]; then
            print_info "Attempting to restart server after failed backup..."
            "${MANAGER_DIR}/start.sh"
        fi

        exit 1
    fi

    # Restart server if it was stopped
    if [[ "$FORCE_STOP" == "yes" && "$SERVER_WAS_RUNNING" == "yes" ]]; then
        print_info "Restarting server after backup..."
        if "${MANAGER_DIR}/start.sh"; then
            print_success "✅ Server restarted successfully"
        else
            print_error "❌ Failed to restart server"
        fi
    fi

    # Clean up old backups unless skipped
    if [[ "$SKIP_PRUNE" != "yes" ]]; then
        if ! prune_old_backups; then
            print_warning "⚠️ Backup pruning had some issues"
        fi
    else
        print_info "Skipping backup pruning (--skip-prune option)"
    fi

    # Log success
    print_header "✅ Backup process completed successfully"
    return 0
}

# Execute the backup
main "$@" || {
    print_header "❌ Backup failed: $?"
    exit 1
}
