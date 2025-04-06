#!/bin/bash
#
# ARK Server Update Script
# Updates the ARK server and optionally restarts it
#
# Usage: ./update.sh [options]
# Options:
#   --force       Force stop the server before update
#   --check-only  Only check if an update is available without applying it
#   --help        Display this help message
#
# =============================================================================

# Load utilities
source "$MANAGER_DIR/utils/common.sh"

# =============================================================================
# CONFIGURATION
# =============================================================================

# Required environment variables for updating
declare -a REQUIRED_VARS=(
    "ARK_SAVE_DIR" # ARK installation directory
    "STEAM_DIR"    # SteamCMD directory
    "ASA_APPID"    # ARK: Survival Ascended App ID
)

# Optional environment variables
declare -a OPTIONAL_VARS=(
    "CLEANUP_AFTER_UPDATE" # Whether to clean up unnecessary files
)

# Default values
set_default_values() {
    CLEANUP_AFTER_UPDATE=${CLEANUP_AFTER_UPDATE:-"true"}

    # Files and paths
    CURRENT_BUILD_ID_FILE="${ARK_SAVE_DIR}/current_build_id.txt"
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Function to get the current build ID from SteamCMD
get_current_build_id() {
    print_info "Checking for current build ID from SteamCMD..."

    # Cache the current build ID to prevent repeatedly calling SteamCMD
    if file_exists "$CURRENT_BUILD_ID_FILE"; then
        local cached_id=$(cat "$CURRENT_BUILD_ID_FILE")
        # Validate the cached ID is numeric
        if [[ "$cached_id" =~ ^[0-9]+$ ]]; then
            print_info "Using cached build ID: $cached_id"
            echo "$cached_id"
            return 0
        fi
        # Remove invalid cache file
        rm -f "$CURRENT_BUILD_ID_FILE"
    fi

    # Run SteamCMD to get the current build ID
    local steamcmd_output=$(${STEAM_DIR}/steamcmd.sh +login anonymous +app_info_print ${ASA_APPID} +quit 2>/dev/null)

    # Extract buildid from output
    local build_id=$(echo "$steamcmd_output" |
        grep -A 150 "\"branches\"" |
        grep -A 50 "\"public\"" |
        grep -m 1 -oP "\"buildid\"\s*\"*\K[0-9]+" |
        head -n 1 |
        tr -d '[:space:]')

    # Validate build ID
    if is_empty "$build_id" || ! [[ "$build_id" =~ ^[0-9]+$ ]]; then
        print_error "❌ Could not retrieve valid build ID from SteamCMD"
        echo "unknown"
        return 1
    fi

    # Cache the valid build ID
    echo "$build_id" >"$CURRENT_BUILD_ID_FILE"
    print_success "✅ Current build ID: $build_id"
    echo "$build_id"
    return 0
}

# Function to get the installed build ID from the app manifest
get_installed_build_id() {
    local acf_file="${ARK_SAVE_DIR}/steamapps/appmanifest_${ASA_APPID}.acf"

    if ! file_exists "$acf_file"; then
        print_warning "⚠️ App manifest not found: $acf_file"
        echo "missing"
        return 1
    fi

    # Extract the build ID
    local build_id=$(grep -oP '"buildid"\s*"\K[^"]+' "$acf_file")

    # Validate build ID
    if is_empty "$build_id" || ! [[ "$build_id" =~ ^[0-9]+$ ]]; then
        print_warning "⚠️ Invalid build ID in manifest"
        echo "unknown"
        return 1
    fi

    print_info "Installed build ID: $build_id"
    echo "$build_id"
    return 0
}

# Function to check if an update is needed
server_needs_update() {
    print_info "Checking if server update is needed..."

    # Get current and installed build IDs
    local current_build=$(get_current_build_id)
    local installed_build=$(get_installed_build_id)

    # Handle unknown or invalid build IDs
    if [[ "$current_build" == "unknown" || "$installed_build" == "unknown" ||
        "$current_build" == "missing" || "$installed_build" == "missing" ]]; then
        print_warning "⚠️ Could not determine build IDs, assuming update is needed"
        return 0
    fi

    # Pretty print build IDs
    print_info "🔵 SteamCMD Current Build ID: $current_build"
    print_info "🟢 Server Installed Build ID: $installed_build"

    # Compare build IDs
    if does_not_equal "$current_build" "$installed_build"; then
        print_success "✅ UPDATE AVAILABLE - Current: $current_build, Installed: $installed_build"
        return 0
    else
        print_success "✅ Server is up to date with build ID: $current_build"
        return 1
    fi
}

# Function for update lock management
acquire_update_lock() {
    if flag_exists "update"; then
        # Check if the lock file is stale
        if [[ $(get_flag_age "update") -gt 30 ]]; then
            print_warning "⚠️ Found stale update lock, removing it"
            remove_flag "update"
        else
            print_warning "⚠️ Another update process is running"
            return 1
        fi
    fi

    # Create the lock file
    create_flag "update"
    print_success "✅ Acquired update lock"
    return 0
}

# Function to release update lock
release_update_lock() {
    remove_flag "update"
    print_success "✅ Released update lock"
}

# Update the ARK server via SteamCMD
update_server() {
    print_script_header "🔄 Updating ARK Server"

    # Check if we need to force validation
    local validation_flag=""
    if file_exists "${ARK_SAVE_DIR}/force_validate.flag"; then
        print_warning "⚠️ Force validation flag detected"
        validation_flag="validate"
        rm -f "${ARK_SAVE_DIR}/force_validate.flag"
    fi

    # Create a temporary file for capturing SteamCMD output
    local steam_output_file=$(mktemp)

    # Run SteamCMD update command with loading animation
    print_info "Starting ARK server update..."
    local update_cmd="${STEAM_DIR}/steamcmd.sh +force_install_dir ${ARK_SAVE_DIR} +login anonymous +app_update ${ASA_APPID} ${validation_flag} +quit"

    # Run the command with loading animation
    eval "$update_cmd" >"$steam_output_file" 2>&1 &
    local cmd_pid=$!

    # Display loading animation
    local elapsed=0
    while kill -0 $cmd_pid 2>/dev/null; do
        loading "Updating ARK server (${elapsed}s)"
        sleep 1
        elapsed=$((elapsed + 1))
    done

    # Get command exit status
    wait $cmd_pid
    local update_status=$?

    # Read the output file
    local update_output=$(cat "$steam_output_file")

    # Check for specific error conditions in the output
    if echo "$update_output" | grep -q "state is 0x6 after update job"; then
        print_warning "⚠️ Steam reports state 0x6 - this usually means the server is already up to date"

        # Log the specific error line
        local error_line=$(echo "$update_output" | grep "state is 0x6" | head -1)
        print_info "SteamCMD message: $error_line"

        # Consider this a success as it means server is up to date
        update_status=0

        # Run a validate if not already done to ensure file integrity
        if is_empty "$validation_flag"; then
            print_info "Running file validation to ensure server integrity..."

            # Run validation command
            local validate_cmd="${STEAM_DIR}/steamcmd.sh +force_install_dir ${ARK_SAVE_DIR} +login anonymous +app_update ${ASA_APPID} validate +quit"

            # Run the command with loading animation
            eval "$validate_cmd" >"$steam_output_file" 2>&1 &
            local validate_pid=$!

            # Display loading animation
            local v_elapsed=0
            while kill -0 $validate_pid 2>/dev/null; do
                loading "Validating ARK server files (${v_elapsed}s)"
                sleep 1
                v_elapsed=$((v_elapsed + 1))
            done

            # Get validation exit status
            wait $validate_pid
            local validate_status=$?

            if equals "$validate_status" "0"; then
                print_success "✅ Validation completed successfully"
            else
                print_warning "⚠️ Validation completed with status: $validate_status"
            fi
        fi
    fi

    # Clean up temporary file
    rm -f "$steam_output_file"

    # Check final update status
    if does_not_equal "$update_status" "0"; then
        print_error "❌ Update failed with exit code: $update_status"
        return 1
    fi

    print_success "✅ Update completed successfully"

    # Cleanup unnecessary files if enabled
    if equals "$CLEANUP_AFTER_UPDATE" "true"; then
        print_info "Cleaning up unnecessary files..."

        # Remove large files not needed for server
        rm -rf ${ARK_SAVE_DIR}/ShooterGame/Content/Movies/ 2>/dev/null || true

        # Clean up SteamCMD temporary files
        rm -rf ${STEAM_DIR}/Steam/logs/* 2>/dev/null || true
        rm -rf ${STEAM_DIR}/Steam/appcache/httpcache/* 2>/dev/null || true
        rm -rf /tmp/SteamCMD_* 2>/dev/null || true

        print_success "✅ Cleanup completed"
    fi

    # Update the current build ID file
    local new_build_id=$(get_installed_build_id)
    if [[ "$new_build_id" =~ ^[0-9]+$ ]]; then
        echo "$new_build_id" >"$CURRENT_BUILD_ID_FILE"
    fi

    return 0
}

# Function for cleanup on script exit
cleanup() {
    release_update_lock
    print_info "Update script exiting with code: $?"
}

# Function to get monitor process ID if running
get_monitor_pid() {
    local MONITOR_PID_FILE="${ARK_SAVE_DIR}/monitor.pid"

    if file_exists "$MONITOR_PID_FILE"; then
        local pid=$(cat "$MONITOR_PID_FILE")
        # Check if process exists
        if ps -p "$pid" >/dev/null 2>&1; then
            if [[ $(ps -p "$pid" -o comm= | grep -c "monitor.sh") -gt 0 ]]; then
                echo "$pid"
                return 0
            fi
        fi
        # PID file exists but process doesn't - clean up stale file
        rm -f "$MONITOR_PID_FILE"
    fi

    # Look for the monitor process
    local pids=$(pgrep -f "bash.*monitor.sh" 2>/dev/null || true)
    if is_not_empty "$pids"; then
        # Return the first matching PID
        echo "$pids" | head -n 1
        return 0
    fi

    echo "0"
    return 1
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

# Parse command line arguments
parse_arguments() {
    FORCE_FLAG=""
    CHECK_ONLY="no"

    for arg in "$@"; do
        case "$arg" in
        --force)
            FORCE_FLAG="--force"
            ;;
        --check-only)
            CHECK_ONLY="yes"
            ;;
        --help)
            echo "Usage: ./update.sh [options]"
            echo "Options:"
            echo "  --force       Force stop the server before update"
            echo "  --check-only  Only check if an update is available without applying it"
            echo "  --help        Display this help message"
            exit 0
            ;;
        *)
            print_warning "⚠️ Unknown option: $arg"
            ;;
        esac
    done
}

# Main function
main() {
    # Set up trap to call cleanup on exit
    trap cleanup EXIT INT TERM

    print_script_header "🚀 ARK Server Update"

    # Check required environment variables
    check_required_env REQUIRED_VARS || exit 1
    check_optional_env OPTIONAL_VARS
    set_default_values

    # Parse command line arguments
    parse_arguments "$@"

    # Check if an update is needed
    if ! server_needs_update; then
        print_success "✅ Server is already up to date"
        # If in check-only mode, exit with non-zero code to indicate no update needed
        [[ "$CHECK_ONLY" == "yes" ]] && return 1
        return 0
    fi

    # If check-only mode, exit after checking for updates
    if [[ "$CHECK_ONLY" == "yes" ]]; then
        print_success "✅ UPDATE AVAILABLE! (--check-only mode, not applying update)"
        # Exit with success code to indicate update is available
        return 0
    fi

    # Try to acquire the update lock
    if ! acquire_update_lock; then
        print_error "❌ Another update is in progress, exiting"
        return 1
    fi

    # Check if server is running and stop it if needed
    print_info "Checking server status..."
    local server_was_running=false
    local ark_server_pid=$(get_ark_server_pid)

    # Check if monitor is running and remember its status
    local monitor_was_running=false
    local monitor_pid=$(get_monitor_pid)
    if does_not_equal "$monitor_pid" "0"; then
        print_info "Monitor is running, will preserve its state"
        monitor_was_running=true

        # Create an update flag to tell the monitor not to exit but wait
        print_info "Creating update in progress flag for monitor..."
        create_flag "update"
    fi

    if does_not_equal "$ark_server_pid" "0"; then
        print_info "Server is running, stopping it before update"
        server_was_running=true

        # Use ark stop command with force flag if provided
        if ! ark stop $FORCE_FLAG; then
            print_error "❌ Failed to stop the server - update aborted"
            remove_flag "update"
            return 1
        fi

        print_success "✅ Server successfully stopped"
    else
        print_info "No server is currently running"
    fi

    # Update the server
    if ! update_server; then
        print_error "❌ Update failed"
        remove_flag "update"
        return 1
    fi

    # Remove the updating flag
    remove_flag "update"

    # Restart the server if it was running before
    if [[ "$server_was_running" == "true" ]]; then
        print_info "Restarting server..."

        if ! ark start; then
            print_error "❌ Failed to restart the server"
            return 1
        fi

        print_success "✅ Server successfully restarted"
    fi

    # If monitor was running but got stopped, restart it
    if [[ "$monitor_was_running" == "true" ]]; then
        # Check if monitor is still running
        monitor_pid=$(get_monitor_pid)
        if [[ "$monitor_pid" == "0" ]]; then
            print_info "Restarting monitor..."
            ark monitor start
            print_success "✅ Monitor restarted"
        else
            print_info "Monitor is still running, no need to restart"
        fi
    fi

    print_success "🎮 ARK server update completed"
    return 0
}

# Execute the main function
main "$@"
