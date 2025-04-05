#!/bin/bash
# ARK Server Backup Utility
# Creates compressed backups of the ARK saved game data
#
# =============================================================================

# Load utilities
UTILS_PATH="$MANAGER_DIR/utils"
source "${UTILS_PATH}/common.sh"

# =============================================================================
# CONFIGURATION
# =============================================================================

# Required environment variables for backup
declare -a REQUIRED_VARS=(
    "ARK_DIR"     # ARK installation directory
    "BACKUP_PATH" # Path to store backups
    "MANAGER_DIR" # Manager scripts directory
)

# Optional environment variables
declare -a OPTIONAL_VARS=(
    "BACKUP_COMPRESSION_LEVEL" # Compression level (1-9)
    "BACKUP_NAME_PREFIX"       # Prefix for the backup file name
    "BACKUP_MAX_BACKUPS"       # Maximum number of backups to keep
    "NETWORK_RCON_PORT"        # RCON port for remote commands
    "SERVER_ADMIN_PASSWORD"    # Admin password for RCON
)

# Default values for optional variables
set_default_values() {
    BACKUP_COMPRESSION_LEVEL=${BACKUP_COMPRESSION_LEVEL:-5}
    BACKUP_NAME_PREFIX=${BACKUP_NAME_PREFIX:-"ark-backup"}
    BACKUP_MAX_BACKUPS=${BACKUP_MAX_BACKUPS:-10}
    BACKUP_FLAG_FILE="${ARK_DIR}/backup_in_progress.flag"

    # Ensure MAX_BACKUPS is at least 1
    if [ "$BACKUP_MAX_BACKUPS" -lt 1 ]; then
        print_warning "⚠️ BACKUP_MAX_BACKUPS must be at least 1, setting to 1"
        BACKUP_MAX_BACKUPS=1
    fi
}

# Function to create backup flag file
create_backup_flag() {
    echo "$(date) - Backup started by PID $$" >"$BACKUP_FLAG_FILE"
    print_success "✅ Created backup flag: $BACKUP_FLAG_FILE"
}

# Function to remove backup flag file
remove_backup_flag() {
    [ -f "$BACKUP_FLAG_FILE" ] && rm -f "$BACKUP_FLAG_FILE" && print_success "✅ Removed backup flag"
}

# Function for cleanup on script exit
cleanup() {
    remove_backup_flag
    print_info "Backup script exiting with code: $?"
}

# Set trap to call cleanup on exit
trap cleanup EXIT INT TERM

# =============================================================================
# BACKUP FUNCTIONS
# =============================================================================

# Creates a backup path if it doesn't exist
create_backup_path() {
    [ -d "$BACKUP_PATH" ] && return 0

    print_info "Creating backup directory: $BACKUP_PATH"
    mkdir -p "$BACKUP_PATH"

    [ ! -d "$BACKUP_PATH" ] && {
        print_error "❌ Failed to create backup directory"
        return 1
    }

    print_success "✅ Created backup directory: $BACKUP_PATH"
    return 0
}

# Save world data before backup if server is running
save_world() {
    print_info "Checking server status..."
    local ark_server_pid=$(get_ark_server_pid)

    # Early return if server is not running
    [ "$ark_server_pid" = "0" ] && {
        print_info "Server is not running, no need to save world"
        return 0
    }

    print_info "Server is running (PID: $ark_server_pid), saving world before backup..."

    # Attempt to save the world using RCON if configured
    if [ -n "$NETWORK_RCON_PORT" ] && [ -n "$SERVER_ADMIN_PASSWORD" ]; then
        print_info "Sending SaveWorld command via RCON..."
        local save_result=$(capture_all_output ark rcon "SaveWorld" --silent)

        if contains "$save_result" "World Saved"; then
            print_success "✅ World saved successfully"
            sleep 5 # Wait a moment for save to complete
            return 0
        else
            print_warning "⚠️ SaveWorld command may have failed: $save_result"
        fi
    else
        print_warning "⚠️ RCON not configured, using alternative save method"
    fi
}

# Creates a backup of the ARK saved data
create_backup() {
    # Generate filename with timestamp
    local timestamp=$(date +"%Y-%m-%d_%H-%M-%S")
    local archive_name="${BACKUP_NAME_PREFIX}-${timestamp}"
    local archive_path="$BACKUP_PATH/${archive_name}.tar.gz"

    # Create backup flag
    create_backup_flag

    print_script_header "📦 Creating ARK Server Backup"
    echo ""

    # Determine which directories to include
    print_info "Preparing backup content..."
    local saved_dir="$ARK_DIR/ShooterGame/Saved"
    local backup_dirs=("SavedArks" "Config" "clusters")

    # Set compression level via GZIP environment variable
    [[ "$BACKUP_COMPRESSION_LEVEL" =~ ^[1-9]$ ]] && {
        export GZIP="-$BACKUP_COMPRESSION_LEVEL"
        print_info "Using compression level: $BACKUP_COMPRESSION_LEVEL"
    }

    print_info "Creating backup archive: $archive_path"
    local dir_args=()

    # Add directories that exist
    for dir in "${backup_dirs[@]}"; do
        [ -d "$saved_dir/$dir" ] && dir_args+=("Saved/$dir")
    done

    # Create the backup with progress indicator
    print_info "Starting backup creation (this may take a while)..."
    local tar_log="/tmp/tar_backup_$$.log"

    # Start tar in background with progress spinner
    (tar -czf "$archive_path" -C "$ARK_DIR/ShooterGame" "${dir_args[@]}" 2>"$tar_log") &
    local tar_pid=$!

    # Show progress spinner
    local elapsed=0
    while kill -0 $tar_pid 2>/dev/null; do
        if [ -f "$archive_path" ]; then
            local size_bytes=$(stat -c%s "$archive_path" 2>/dev/null || echo 0)
            # Calculate MB using bash arithmetic instead of bc
            local size_mb=$((size_bytes / 1048576))
            loading "Creating backup: ${size_mb}MB written (${elapsed}s elapsed)"
        else
            loading "Preparing backup... (${elapsed}s elapsed)"
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done
    echo "" # Add newline after spinner

    # Check if tar completed successfully
    wait $tar_pid
    local tar_status=$?

    if [ $tar_status -ne 0 ]; then
        [ -f "$tar_log" ] && {
            local error_content=$(cat "$tar_log")
            print_error "❌ Tar error output: $error_content"
        }

        print_error "❌ Backup creation failed with status $tar_status"
        [ -f "$archive_path" ] && rm -f "$archive_path"
        [ -f "$tar_log" ] && rm -f "$tar_log"
        return 1
    fi

    # Clean up and report success
    [ -f "$tar_log" ] && rm -f "$tar_log"

    if [ -f "$archive_path" ]; then
        local size_bytes=$(stat -c%s "$archive_path" 2>/dev/null || echo 0)
        # Calculate MB using bash arithmetic instead of bc
        local size_mb=$((size_bytes / 1048576))
        print_success "✅ Backup created successfully: $archive_path (${size_mb}MB)"
        return 0
    else
        print_error "❌ Backup file not found after creation"
        return 1
    fi
}

# Prunes old backups to maintain only the specified number
prune_old_backups() {
    print_info "Checking for old backups to prune..."

    # List all backup files sorted by modification time (newest first)
    local backup_files=($(find "$BACKUP_PATH" -name "${BACKUP_NAME_PREFIX}-*.tar.gz" -type f -printf "%T@ %p\n" | sort -rn | cut -d' ' -f2))
    local backup_count=${#backup_files[@]}

    # Delete older backups if exceeding max limit
    if [ "$backup_count" -gt "$BACKUP_MAX_BACKUPS" ]; then
        local files_to_remove=$((backup_count - BACKUP_MAX_BACKUPS))
        print_info "Removing $files_to_remove old backups..."

        for ((i = BACKUP_MAX_BACKUPS; i < backup_count; i++)); do
            local file="${backup_files[$i]}"
            [ ! -f "$file" ] && continue

            local filename=$(basename "$file")
            local filesize=$(du -h "$file" | cut -f1)

            print_warning "Removing old backup: $filename ($filesize)"
            rm -f "$file"
            [ $? -ne 0 ] && print_error "❌ Failed to remove backup: $file"
        done

        print_success "✅ Removed $files_to_remove old backups"
    else
        print_info "No backups need to be pruned (count: $backup_count, max: $BACKUP_MAX_BACKUPS)"
    fi

    return 0
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

# Main backup process
main() {
    print_script_header "🚀 ARK Server Backup Utility"

    # Check required environment variables
    check_required_env REQUIRED_VARS || exit 1

    # Check optional environment variables
    check_optional_env OPTIONAL_VARS

    # Set default values for optional variables
    set_default_values

    # Create backup directory if needed
    create_backup_path || {
        print_error "❌ Cannot proceed without backup directory"
        exit 1
    }

    # Save world before backup
    save_world || print_warning "⚠️ Could not save world before backup, continuing anyway"

    # Create backup
    if ! create_backup; then
        print_error "❌ Backup failed"
        exit 1
    fi

    # Prune old backups
    prune_old_backups || print_warning "⚠️ Backup pruning had some issues"

    print_success "✅ Backup process completed successfully"
    return 0
}

# Execute the backup
main "$@" || {
    print_error "❌ Backup failed: $?"
    exit 1
}
