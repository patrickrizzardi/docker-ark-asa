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
    mv "$src" "$dest" 2>/dev/null && return 0

    # Check if it's a cross-device issue
    [[ $? -eq 1 ]] && {
        print_info "Cross-device move detected, copying instead: $src -> $dest"
        # Fall back to copy + delete if across filesystems
        cp "$src" "$dest" && rm "$src" || {
            print_error "Failed to copy and delete $src"
            return 1
        }
        return 0
    }

    print_error "Failed to move $src to $dest"
    return 1
}

# Function to ensure a directory exists
# Creates directory if it doesn't exist
ensure_dir() {
    local dir="$1"
    local perm="${2:-755}"

    if dir_exists "$dir"; then
        return 0
    fi

    mkdir -p "$dir" || {
        print_error "Failed to create directory: $dir"
        return 1
    }

    chmod "$perm" "$dir" || {
        print_warning "Failed to set permissions $perm on $dir"
    }

    print_info "Created directory: $dir"
    return 0
}

# Function to check if a file exists and is readable
# Params:
#   $1 - File path to check
# Returns:
#   0 if file exists and is readable, 1 otherwise
check_file() {
    local file="$1"

    if file_does_not_exist "$file"; then
        print_error "File does not exist: $file"
        return 1
    fi

    if is_not_readable "$file"; then
        print_error "File is not readable: $file"
        return 1
    fi

    return 0
}

# Function to safely copy a file
# Creates destination directory if it doesn't exist
safe_copy() {
    local src="$1"
    local dest="$2"

    check_file "$src" || return 1

    # Create destination directory if it doesn't exist
    mkdir -p "$(dirname "$dest")" || {
        print_error "Failed to create destination directory for: $dest"
        return 1
    }

    cp "$src" "$dest" || {
        print_error "Failed to copy $src to $dest"
        return 1
    }

    print_info "Copied $src to $dest"
    return 0
}

# Function to create a backup of a file with timestamp
# Params:
#   $1 - Original file path
#   $2 - (Optional) Backup directory, defaults to same directory as file
backup_file() {
    local file="$1"
    local backup_dir="${2:-$(dirname "$file")}"
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    local filename=$(basename "$file")
    local backup_file="${backup_dir}/${filename}.${timestamp}.bak"

    check_file "$file" || return 1

    ensure_dir "$backup_dir" || return 1

    cp "$file" "$backup_file" || {
        print_error "Failed to create backup of $file"
        return 1
    }

    print_info "Created backup: $backup_file"
    return 0
}

# Function to remove old backups keeping only N most recent
# Params:
#   $1 - Original file path pattern (used to match backups)
#   $2 - Number of backups to keep
#   $3 - (Optional) Backup directory, defaults to same directory as file
cleanup_backups() {
    local file_pattern="$1"
    local keep_count="$2"
    local backup_dir="${3:-$(dirname "$file_pattern")}"
    local filename=$(basename "$file_pattern")

    if dir_does_not_exist "$backup_dir"; then
        print_warning "Backup directory does not exist: $backup_dir"
        return 0
    fi

    # Find all backup files sorted by modification time (oldest first)
    local old_backups=$(find "$backup_dir" -name "${filename}*.bak" -type f | sort -t. -k2)
    local total_backups=$(echo "$old_backups" | wc -l)

    [[ $total_backups -le $keep_count ]] && return 0

    local delete_count=$((total_backups - keep_count))

    [[ $delete_count -le 0 ]] && return 0

    echo "$old_backups" | head -n $delete_count | while read backup; do
        rm "$backup" || print_warning "Failed to remove old backup: $backup"
    done

    print_info "Cleaned up $delete_count old backups, keeping $keep_count most recent"
    return 0
}

# Function to append text to a file, creating it if it doesn't exist
append_to_file() {
    local file="$1"
    local text="$2"

    # Create directory if it doesn't exist
    ensure_dir "$(dirname "$file")" || return 1

    echo "$text" >>"$file" || {
        print_error "Failed to append to file: $file"
        return 1
    }

    return 0
}

# Function to find and replace text in a file
# Params:
#   $1 - File path
#   $2 - Search pattern (sed format)
#   $3 - Replacement text
#   $4 - (Optional) Backup file if true
find_replace() {
    local file="$1"
    local search="$2"
    local replace="$3"
    local do_backup="${4:-false}"

    check_file "$file" || return 1

    [[ "$do_backup" == "true" ]] && backup_file "$file"

    sed -i "s|$search|$replace|g" "$file" || {
        print_error "Failed to replace text in file: $file"
        return 1
    }

    print_info "Replaced '$search' with '$replace' in $file"
    return 0
}
