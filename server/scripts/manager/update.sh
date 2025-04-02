#!/bin/bash
#
# ARK Server Update Script
# Updates the ARK server and optionally restarts it
#
# Usage: ./update.sh [options]
# Options:
#   --force            Skip player checks and force server shutdown
#   --no-restart       Don't restart the server after update
#   --restart-as-api   Restart as API server after update
#   --help             Display this help message
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

# Required environment variables for updating
declare -a UPDATE_REQUIRED_VARS=(
    "ARK_DIR"   # ARK installation directory
    "STEAM_DIR" # SteamCMD directory
    "ASA_APPID" # ARK: Survival Ascended App ID
)

# Optional environment variables
declare -a UPDATE_OPTIONAL_VARS=(
    "RESTART_NOTICE_MINUTES" # Minutes to notify players before restart
    "CLEANUP_AFTER_UPDATE"   # Whether to clean up unnecessary files
    "SERVER_MAP"             # Map to run
    "SESSION_NAME"           # Server session name
    "SERVER_PORT"            # Server port
    "MAX_PLAYERS"            # Maximum number of players
    "SERVER_PASSWORD"        # Server password
    "ARK_ADMIN_PASSWORD"     # Admin password
    "RCON_PORT"              # RCON port
    "QUERY_PORT"             # Query port
    "MODS"                   # Mods to load
    "ARK_EXTRA_OPTS"         # Extra server options
)

# Optional variables with defaults
RESTART_NOTICE_MINUTES=${RESTART_NOTICE_MINUTES:-5}
CLEANUP_AFTER_UPDATE=${CLEANUP_AFTER_UPDATE:-"TRUE"}

# Creating an update lock file to prevent multiple updates
UPDATE_LOCK_FILE="${ARK_DIR}/updating.flag"
# Store the current build ID for validation
CURRENT_BUILD_ID_FILE="${ARK_DIR}/current_build_id.txt"

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Function to get the current build ID from SteamCMD
get_current_build_id() {
    print_info "Checking for current build ID from SteamCMD..."

    # Cache the current build ID to prevent repeatedly calling SteamCMD
    if [[ -f "$CURRENT_BUILD_ID_FILE" ]]; then
        local cached_id=$(cat "$CURRENT_BUILD_ID_FILE")

        # Check if the cached content is actually an error message
        if [[ "$cached_id" == *"⚠️"* || "$cached_id" == *"error"* || "$cached_id" == *"Error"* || "$cached_id" == *"not found"* || "$cached_id" == "unknown" ]]; then
            print_warning "⚠️ Cached build ID contains an error message, will query SteamCMD directly"
            # Remove the invalid cache file
            rm -f "$CURRENT_BUILD_ID_FILE"
        else
            # Validate that the cached ID is numeric
            if [[ "$cached_id" =~ ^[0-9]+$ ]]; then
                print_info "Using cached build ID: $cached_id"
                echo "$cached_id"
                return 0
            else
                print_warning "⚠️ Cached build ID is not in expected format: $cached_id"
                # Remove the invalid cache file
                rm -f "$CURRENT_BUILD_ID_FILE"
            fi
        fi
    fi

    # Run SteamCMD to get the current build ID with improved extraction
    print_info "Querying SteamCMD for current build ID..."
    local steamcmd_output=$(${STEAM_DIR}/steamcmd.sh +login anonymous +app_info_print ${ASA_APPID} +quit 2>/dev/null)

    # More precise extraction to avoid multiple matches
    # 1. Find the "branches" section
    # 2. Extract only the "public" branch section
    # 3. Look for buildid within that specific section
    # 4. Take only the first match and trim whitespace
    local build_id=$(echo "$steamcmd_output" |
        grep -A 150 "\"branches\"" |
        grep -A 50 "\"public\"" |
        grep -m 1 -oP "\"buildid\"\s*\"*\K[0-9]+" |
        head -n 1 |
        tr -d '[:space:]')

    if [[ -z "$build_id" ]]; then
        print_error "❌ Could not retrieve build ID from SteamCMD. Please check SteamCMD connection."
        echo "unknown"
        return 1
    fi

    # Final sanity check - ensure it only contains digits
    if ! [[ "$build_id" =~ ^[0-9]+$ ]]; then
        print_error "❌ Invalid build ID format: '$build_id'"
        echo "invalid"
        return 1
    fi

    # Cache the build ID - only if it's valid
    echo "$build_id" >"$CURRENT_BUILD_ID_FILE"
    # Verify the file was written correctly
    if [[ -f "$CURRENT_BUILD_ID_FILE" ]]; then
        local written_id=$(cat "$CURRENT_BUILD_ID_FILE")
        if [[ "$written_id" != "$build_id" ]]; then
            print_warning "⚠️ Failed to write build ID correctly to cache file"
            # If the write failed, remove the potentially corrupted file
            rm -f "$CURRENT_BUILD_ID_FILE"
        else
            print_success "✅ Current build ID cached: $build_id"
        fi
    else
        print_warning "⚠️ Failed to create build ID cache file"
    fi

    print_success "✅ Current build ID: $build_id"
    echo "$build_id"
    return 0
}

# Function to get the installed build ID from the app manifest
get_installed_build_id() {
    local acf_file="${STEAM_DIR}/steamapps/appmanifest_${ASA_APPID}.acf"

    if [[ ! -f "$acf_file" ]]; then
        print_warning "⚠️ App manifest not found: $acf_file"
        # Check if the server is actually installed despite missing manifest
        if [[ -d "${ARK_DIR}/ShooterGame" ]]; then
            print_info "Server appears to be installed despite missing manifest"

            # Create a flag file to indicate we need to force validation on next update
            touch "${ARK_DIR}/force_validate.flag"

            # Since we can't determine the build ID, we'll return unknown
            echo "unknown"
            return 1
        fi
        echo "missing"
        return 1
    fi

    # Extract the build ID from the app manifest
    local build_id=$(grep -oP '"buildid"\s*"\K[^"]+' "$acf_file")

    if [[ -z "$build_id" ]]; then
        print_warning "⚠️ Build ID not found in app manifest"
        echo "unknown"
        return 1
    fi

    # Validate the build ID (should be numeric)
    if ! [[ "$build_id" =~ ^[0-9]+$ ]]; then
        print_warning "⚠️ Invalid build ID format in manifest: $build_id"
        echo "invalid"
        return 1
    fi

    print_info "Installed build ID: $build_id"
    echo "$build_id"
    return 0
}

# Function to check if an update is needed
server_needs_update() {
    print_header "🔍 Checking if server update is needed"

    # Get current build ID from SteamCMD
    local current_build=$(get_current_build_id)

    # Get installed build ID from app manifest
    local installed_build=$(get_installed_build_id)

    # If either build ID is unknown, assume update is needed
    if [[ "$current_build" == "unknown" || "$installed_build" == "unknown" ]]; then
        print_warning "⚠️ Could not determine build IDs, assuming update is needed"
        return 0
    fi

    # If either build ID is invalid, assume update is needed
    if [[ "$current_build" == "invalid" || ! "$installed_build" =~ ^[0-9]+$ ]]; then
        print_warning "⚠️ Invalid build ID format, assuming update is needed"
        return 0
    fi

    # Pretty printing build IDs
    echo "========================================================"
    print_info "🔵 SteamCMD Current Build ID: $current_build"
    print_info "🟢 Server Installed Build ID: $installed_build"
    echo "========================================================"

    # Compare build IDs
    if [[ "$current_build" != "$installed_build" ]]; then
        print_success "✅ UPDATE AVAILABLE - Current: $current_build, Installed: $installed_build"
        return 0
    else
        print_success "✅ Server is up to date with build ID: $current_build"
        return 1
    fi
}

# Function to acquire update lock
acquire_update_lock() {
    if [[ -f "$UPDATE_LOCK_FILE" ]]; then
        # Check if the lock file is stale (more than 30 minutes old)
        if [[ $(find "$UPDATE_LOCK_FILE" -mmin +30 -print) ]]; then
            print_warning "⚠️ Found stale update lock, removing it"
            rm -f "$UPDATE_LOCK_FILE"
        else
            print_warning "⚠️ Another update process is running"
            return 1
        fi
    fi

    # Create the lock file
    echo "$(date) - Update started by PID $$" >"$UPDATE_LOCK_FILE"
    print_success "✅ Acquired update lock"
    return 0
}

# Function to release update lock
release_update_lock() {
    if [[ -f "$UPDATE_LOCK_FILE" ]]; then
        rm -f "$UPDATE_LOCK_FILE"
        print_success "✅ Released update lock"
    fi
}

# Function to notify players about the upcoming update
notify_players_of_update() {
    local minutes=$1

    print_info "Notifying players about update in $minutes minutes..."

    # Send initial notice
    ./rcon.sh "ServerChat Server update detected! Server will restart in $minutes minutes for the update." --silent

    # If minutes is greater than 5, send additional notices at intervals
    if [ $minutes -gt 5 ]; then
        # Send notice at half-way point
        local halfway_minutes=$((minutes / 2))
        sleep $((halfway_minutes * 60))
        ./rcon.sh "ServerChat Server update reminder: Restart in $halfway_minutes minutes." --silent

        # Additional reminders at 5, 2, and 1 minute marks
        if [ $halfway_minutes -gt 5 ]; then
            sleep $(((halfway_minutes - 5) * 60))
            ./rcon.sh "ServerChat Server update imminent: Restart in 5 minutes." --silent
            sleep 180 # 3 minutes
            ./rcon.sh "ServerChat Server update imminent: Restart in 2 minutes." --silent
            sleep 60 # 1 minute
            ./rcon.sh "ServerChat FINAL WARNING: Server restart in 1 minute for update!" --silent
        else
            local remaining_minutes=$((halfway_minutes))
            sleep $(((remaining_minutes - 1) * 60))
            ./rcon.sh "ServerChat FINAL WARNING: Server restart in 1 minute for update!" --silent
        fi
    else
        # For short countdowns, just wait until the last minute
        if [ $minutes -gt 1 ]; then
            sleep $(((minutes - 1) * 60))
            ./rcon.sh "ServerChat FINAL WARNING: Server restart in 1 minute for update!" --silent
        fi
    fi

    # Final countdown in seconds
    sleep 30
    ./rcon.sh "ServerChat Server restarting in 30 seconds for update..." --silent
    sleep 20
    ./rcon.sh "ServerChat Server restarting in 10 seconds for update..." --silent
    sleep 5
    ./rcon.sh "ServerChat 5..." --silent
    sleep 1
    ./rcon.sh "ServerChat 4..." --silent
    sleep 1
    ./rcon.sh "ServerChat 3..." --silent
    sleep 1
    ./rcon.sh "ServerChat 2..." --silent
    sleep 1
    ./rcon.sh "ServerChat 1..." --silent
    sleep 1
    ./rcon.sh "ServerChat Server restarting NOW!" --silent
}

# Update the ARK server via SteamCMD
update_server() {
    print_header "🔄 Updating ARK Server"
    echo ""

    print_info "Running SteamCMD to update ARK server..."

    # Check if we need to force validation (missing or corrupt install)
    local validation_flag=""
    if [[ -f "${ARK_DIR}/force_validate.flag" ]]; then
        print_warning "⚠️ Force validation flag detected - will perform full validation"
        validation_flag="validate"
        # Remove the flag file after detection
        rm -f "${ARK_DIR}/force_validate.flag"
    fi

    if ! ${STEAM_DIR}/steamcmd.sh +force_install_dir ${ARK_DIR} +login anonymous +app_update ${ASA_APPID} $validation_flag +quit; then
        print_error "❌ Update failed"
        return 1
    fi

    print_success "✅ Update completed successfully"

    # Cleanup unnecessary files to reduce image size if enabled
    if [[ "$CLEANUP_AFTER_UPDATE" == "TRUE" ]]; then
        print_info "Cleaning up unnecessary files to reduce image size..."

        # Cleanup debug symbols (PDB files) - these are huge and not needed for runtime
        # ! For now im not removing them as they are needed for the status command
        # if [[ -f "${ARK_DIR}/ShooterGame/Binaries/Win64/ArkAscendedServer.pdb" ]]; then
        #     rm -rf ${ARK_DIR}/ShooterGame/Binaries/Win64/ArkAscendedServer.pdb
        #     print_info "Removed PDB file (debug symbols)"
        # fi

        # Remove intro movies - not needed for server
        if [[ -d "${ARK_DIR}/ShooterGame/Content/Movies/" ]]; then
            rm -rf ${ARK_DIR}/ShooterGame/Content/Movies/
            print_info "Removed movies directory"
        fi

        # Remove any other unnecessary files to reduce size
        # List of directories/files that are safe to remove for a server
        unnecessary_dirs=(
            "${ARK_DIR}/ShooterGame/Content/Localization"       # Localization files not needed for server
            "${ARK_DIR}/Engine/Documentation"                   # Documentation
            "${ARK_DIR}/ShooterGame/Content/Maps/*/MapTextures" # Map textures (not needed by server)
        )

        for dir in "${unnecessary_dirs[@]}"; do
            if [[ -d "$dir" ]]; then
                rm -rf "$dir"
                print_info "Removed unnecessary directory: $dir"
            fi
        done

        # Clean up SteamCMD temporary files
        print_info "Cleaning up SteamCMD temporary files..."
        rm -rf ${STEAM_DIR}/Steam/logs/* 2>/dev/null || true
        rm -rf ${STEAM_DIR}/Steam/appcache/httpcache/* 2>/dev/null || true
        rm -rf /tmp/SteamCMD_* 2>/dev/null || true

        print_success "✅ Cleanup completed - server image size reduced"
    fi

    # Update the current build ID file after successful update
    local new_build_id=$(get_installed_build_id)

    # Only update the cache if we got a valid build ID
    if [[ "$new_build_id" != "unknown" && "$new_build_id" != "missing" && "$new_build_id" != "invalid" ]]; then
        # Ensure we're writing a valid build ID to the cache
        if [[ "$new_build_id" =~ ^[0-9]+$ ]]; then
            echo "$new_build_id" >"$CURRENT_BUILD_ID_FILE"
            print_success "✅ Updated current build ID file to: $new_build_id"
        else
            print_warning "⚠️ Not caching invalid build ID: $new_build_id"
            # Remove any existing cache to force fresh check next time
            rm -f "$CURRENT_BUILD_ID_FILE"
        fi
    else
        print_warning "⚠️ Could not determine build ID after update"
        # Remove any existing cache to force fresh check next time
        rm -f "$CURRENT_BUILD_ID_FILE"
    fi

    return 0
}

# Function to cleanup on script exit
cleanup() {
    local exit_code=$?

    # Release update lock
    release_update_lock

    print_info "Update script exiting with code: $exit_code"
    exit $exit_code
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

# Set up trap to call cleanup on exit
trap cleanup EXIT INT TERM

# Parse command line arguments
parse_arguments() {
    FORCE_FLAG=""
    RESTART_SERVER="no"
    SERVER_TYPE="server"

    for arg in "$@"; do
        case "$arg" in
        --force)
            FORCE_FLAG="--force"
            ;;
        --no-restart)
            RESTART_SERVER="no"
            ;;
        --restart-as-api)
            SERVER_TYPE="api"
            ;;
        --help)
            echo "Usage: ./update.sh [options]"
            echo "Options:"
            echo "  --force            Skip player checks and force server shutdown"
            echo "  --no-restart       Don't restart the server after update"
            echo "  --restart-as-api   Restart as API server after update"
            echo "  --help             Display this help message"
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
    clear # Start with a clean screen
    print_header "🚀 ARK Server Update"
    echo ""

    # Check required environment variables
    if ! check_env_variables UPDATE_REQUIRED_VARS 0; then
        print_error "❌ Missing required environment variables"
        exit 1
    fi

    # Check optional environment variables
    check_env_variables UPDATE_OPTIONAL_VARS 1

    # Parse command line arguments
    parse_arguments "$@"

    # Check if an update is needed
    if ! server_needs_update; then
        print_success "✅ Server is already up to date, no update needed"
        exit 0
    fi

    # Try to acquire the update lock
    if ! acquire_update_lock; then
        print_error "❌ Another update is in progress, exiting"
        exit 1
    fi

    # Step 1: Check if server is running
    print_info "Checking server status..."
    local ark_server_pid=$(get_ark_server_pid)

    if [[ "$ark_server_pid" != "0" ]]; then
        print_info "Server is running (PID: $ark_server_pid)"

        # Notify players if server is running and we'll be restarting
        if [[ "$RESTART_SERVER" == "yes" ]]; then
            print_info "Notifying players about upcoming restart in $RESTART_NOTICE_MINUTES minutes"
            notify_players_of_update $RESTART_NOTICE_MINUTES
        fi

        print_info "Saving world and stopping server..."

        # Use force flag if provided
        if [[ -n "$FORCE_FLAG" ]]; then
            print_warning "Force flag detected - will stop server regardless of players"
        fi

        # Stop the server
        if ! "${MANAGER_DIR}/stop.sh" $FORCE_FLAG; then
            print_error "❌ Failed to stop the server - update aborted"
            exit 1
        fi

        print_success "✅ Server successfully stopped"
    else
        print_info "No server is currently running"
    fi

    # Step 2: Update the server
    if ! update_server; then
        print_error "❌ Update failed - server may be in an inconsistent state"
        exit 1
    fi

    # Step 3: Restart the server if requested
    if [[ "$RESTART_SERVER" == "yes" ]]; then
        print_info "Restarting server as ${SERVER_TYPE}..."

        if ! "${MANAGER_DIR}/start.sh" $SERVER_TYPE; then
            print_error "❌ Failed to start the server"
            exit 1
        fi

        print_success "✅ Server successfully restarted"
    else
        print_info "Server will not be restarted (--no-restart option used)"
    fi

    print_success "🎮 ARK server update completed"
    exit 0
}

# Execute the main function with all arguments
main "$@"
