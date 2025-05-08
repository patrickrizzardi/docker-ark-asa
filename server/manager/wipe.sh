#!/bin/bash
#
# ARK Server Wipe Utility
# Wipes ARK saved game data with option to create backup first
#
# Usage: ./wipe.sh [options]
# Options:
#   --force, -f     Skip confirmation prompts
#   --help, -h      Display this help message
#
# =============================================================================

# Load environment variables and utilities
source "${MANAGER_DIR}/utils/common.sh"

# =============================================================================
# CONFIGURATION
# =============================================================================

# Required environment variables
declare -a REQUIRED_VARS=(
    "ARK_SAVE_DIR" # ARK installation directory
)

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Function to display usage information
show_usage() {
    echo "Usage: ./wipe.sh [options]"
    echo "Options:"
    echo "  --force, -f     Skip confirmation prompts"
    echo "  --help, -h      Display this help message"
    exit 0
}

# Function to cleanup resources on script exit
cleanup() {
    local exit_code=$?
    print_info "Wipe script exiting with code: $exit_code"
    exit $exit_code
}

# Set trap to call cleanup on exit
trap cleanup EXIT INT TERM

# =============================================================================
# WIPE FUNCTIONS
# =============================================================================

# Create a backup before wiping if requested
create_backup_before_wipe() {
    print_warning "Recommended: Create a backup before wiping save data"

    # Prompt for backup
    read -p "Create a backup before wiping? (y/n): " -n 1 -r
    echo ""

    if equals "${REPLY}" "y" || equals "${REPLY}" "Y"; then
        print_info "Creating backup before wiping..."

        # Run the backup command
        ark backup

        # Check if backup succeeded
        if does_not_equal "$?" "0"; then
            print_error "❌ Backup failed"

            read -p "Continue with wipe despite backup failure? (y/n): " -n 1 -r
            echo ""

            if does_not_equal "${REPLY}" "y" && does_not_equal "${REPLY}" "Y"; then
                print_info "Wipe cancelled by user"
                exit 0
            fi
        else
            print_success "✅ Backup completed successfully"
        fi
    else
        print_warning "⚠️ Skipping backup as requested"
    fi

    return 0
}

# Confirm wipe with user
confirm_wipe() {
    if equals "$FORCE_MODE" "yes"; then
        return 0
    fi

    print_warning "⚠️ WARNING: This will delete ALL saved game data!"
    print_warning "⚠️ This action CANNOT be undone!"

    echo ""
    read -p "Are you SURE you want to wipe all saves? Type 'WIPE' to confirm: " confirmation
    echo ""

    if does_not_equal "$confirmation" "WIPE"; then
        print_info "Wipe cancelled by user"
        exit 0
    fi

    return 0
}

# Perform the actual wipe of save data
wipe_save_data() {
    print_info "Stopping ARK server if running..."

    # Check if server is running and stop it if needed
    local ark_server_pid=$(get_ark_server_pid)
    if does_not_equal "$ark_server_pid" "0"; then
        print_info "Server is running (PID: $ark_server_pid), stopping..."
        ark stop --force

        # Wait for server to stop
        local timeout=60
        local elapsed=0

        while [ $elapsed -lt $timeout ]; do
            ark_server_pid=$(get_ark_server_pid)
            if equals "$ark_server_pid" "0"; then
                break
            fi

            loading "Waiting for server to stop... ${elapsed}s" "cyan"
            sleep 1
            elapsed=$((elapsed + 1))
        done

        echo ""

        if does_not_equal "$(get_ark_server_pid)" "0"; then
            print_error "❌ Failed to stop server"
            return 1
        fi

        print_success "✅ Server stopped successfully"
    else
        print_info "Server is not running, proceeding with wipe"
    fi

    # Wipe save data
    print_info "Wiping ARK save data..."

    # Define paths to wipe
    local saved_dir="${ARK_SAVE_DIR}/ShooterGame/Saved"
    local save_paths=(
        "${saved_dir}/SavedArks"
        "${saved_dir}/clusters"
        "${saved_dir}/Logs"

    )

    for path in "${save_paths[@]}"; do
        if dir_exists "$path"; then
            print_info "Deleting $path..."

            # Remove save files while preserving directory structure
            find "$path" -type f -not -path "*/\.*" -delete

            if does_not_equal "$?" "0"; then
                print_error "❌ Failed to delete files in $path"
                return 1
            fi
        else
            print_info "Directory $path does not exist, skipping"
        fi
    done

    print_success "✅ Save data wiped successfully"

    return 0
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

# Parse command line arguments
parse_arguments() {
    FORCE_MODE="no"

    while [[ $# -gt 0 ]]; do
        case "$1" in
        --force | -f)
            FORCE_MODE="yes"
            shift
            ;;
        --help | -h)
            show_usage
            ;;
        *)
            print_warning "⚠️ Unknown option: $1"
            shift
            ;;
        esac
    done
}

# Main function
main() {
    # Parse command line arguments
    parse_arguments "$@"

    # Print script header
    print_script_header "🧨 ARK Server Wipe Utility"

    # Check required environment variables
    check_required_env REQUIRED_VARS || exit 1

    # Create backup before wiping if requested
    create_backup_before_wipe

    # Confirm wipe with user
    confirm_wipe

    # Perform the wipe
    if ! wipe_save_data; then
        print_error "❌ Wipe failed"
        exit 1
    fi

    print_success "✅ ARK server save data has been wiped successfully"
    print_info "You can now start the server with a fresh state"

    return 0
}

# Execute the main function with all arguments
main "$@"
