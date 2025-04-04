#!/bin/bash
#
# ARK Server Status Script
# Displays server status information in basic or detailed mode
#
# Usage: ./status.sh [options]
# Options:
#   --full, -f       Show detailed status (including EOS API info)
#   --no-color, -n   Disable colored output
#   --help, -h       Display this help message
#
# =============================================================================

# Load environment variables and utilities
source "${MANAGER_DIR}/utils/common.sh"

# =============================================================================
# CONFIGURATION
# =============================================================================

# Required environment variables
declare -a REQUIRED_VARS=(
    "ARK_DIR"               # ARK installation directory
    "NETWORK_SERVER_PORT"   # Server port
    "NETWORK_RCON_PORT"     # RCON port
    "SERVER_ADMIN_PASSWORD" # Admin password for RCON commands
)

# Configuration files
EOS_FILE="${ARK_DIR}/eos_credentials.txt"
PDB_TOOL="${MANAGER_DIR}/pdb-sym2addr"

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Function to display usage information
show_usage() {
    echo "Usage: ./status.sh [options]"
    echo "Options:"
    echo "  --full, -f       Show detailed status (including EOS API info)"
    echo "  --no-color, -n   Disable colored output"
    echo "  --help, -h       Display this help message"
    exit 0
}

# Get the container's IP address
get_container_ip() {
    local ip=$(hostname -I | awk '{print $1}')
    if is_empty "$ip"; then
        echo "0.0.0.0"
        return 0
    fi
    echo "$ip"
}

# Function to display server status box
print_status_box() {
    local status="$1"
    local color="$2"

    case "$color" in
    "green") echo -e "${GREEN}${BOLD}[ $status ]${NC}" ;;
    "red") echo -e "${RED}${BOLD}[ $status ]${NC}" ;;
    "yellow") echo -e "${YELLOW}${BOLD}[ $status ]${NC}" ;;
    *) echo -e "[ $status ]" ;;
    esac
}

# Function to format label and value
format_label_value() {
    local key="$1"
    local value="$2"
    local pad_length=20

    # Calculate padding
    local padding=""
    for ((i = 0; i < $(($pad_length - ${#key})); i++)); do
        padding+=" "
    done

    echo -e "${CYAN}${BOLD}${key}${padding}${NC} ${value}"
    return 0
}

# Function to get the server's listening port
get_listening_port() {
    # Get ARK server PID using the utility function
    local ark_pid=$(get_ark_server_pid)

    if equals "$ark_pid" "0"; then
        return 1
    fi

    # Look for connections on SERVER_PORT or any port if SERVER_PORT is not specified
    if ! is_empty "$SERVER_PORT"; then
        # Look specifically for the configured server port
        local port_info=$(ss -tupln | grep -E "$ark_pid.*:$SERVER_PORT" | head -1)
        if ! is_empty "$port_info"; then
            echo "$SERVER_PORT"
            return 0
        fi
    fi

    # No specific server port configured or not found, get the first port this process listens on
    local listening_ports=$(ss -tupln | grep -E "$ark_pid" | grep -oP '(?<=:)\d+' | head -1)
    if ! is_empty "$listening_ports"; then
        echo "$listening_ports"
        return 0
    fi

    # Try to find the port by looking at UDP connections, as ARK server uses UDP
    local udp_port=$(ss -uplna | grep -E "$ark_pid" | grep -oP '(?<=:)\d+' | head -1)
    if ! is_empty "$udp_port"; then
        echo "$udp_port"
        return 0
    fi

    # As a last resort, check for any port close to the configured SERVER_PORT
    if ! is_empty "$SERVER_PORT"; then
        # Check if any process is listening on the expected port
        local any_process_port=$(ss -tupln | grep ":$SERVER_PORT" | grep -oP '(?<=:)\d+')
        if ! is_empty "$any_process_port"; then
            echo "$any_process_port"
            return 0
        fi
    fi

    # No port found
    return 1
}

# =============================================================================
# BASIC STATUS FUNCTIONS
# =============================================================================

set_basic_status_variables() {
    # Initialize all variables
    PROCESS_ID=""
    SERVER_TYPE=""
    LISTENING_PORT=""
    RCON_STATUS=""
    SERVER_STATUS=""
    PLAYER_COUNT="0"
    SERVER_STATUS_COLOR="red"
    RCON_STATUS_COLOR="red"
    STATUS_NOTE=""

    # Get the server PID
    local ark_pid=$(get_ark_server_pid)
    PROCESS_ID="$ark_pid"

    # Check if server is running
    if equals "$ark_pid" "0" || is_empty "$ark_pid"; then
        SERVER_STATUS="OFFLINE"
        SERVER_STATUS_COLOR="red"
        STATUS_NOTE="Not running"
        return 1
    fi

    # Show server type (API or regular)
    local server_type="Game Server"
    ps -p "$ark_pid" -o cmd= | grep -q "AsaApiLoader" && server_type="API Server"
    SERVER_TYPE="$server_type"

    # Check if server is listening on the port
    local listening_port=$(get_listening_port)
    if is_empty "$listening_port"; then
        LISTENING_PORT=""
        SERVER_STATUS="STARTING"
        SERVER_STATUS_COLOR="yellow"
        STATUS_NOTE="Server is running but not yet listening on network port"
        return 2
    fi

    LISTENING_PORT="$listening_port"
    SERVER_STATUS="ONLINE"
    SERVER_STATUS_COLOR="green"

    # Check if RCON is available
    if is_empty "$NETWORK_RCON_PORT" || is_empty "$SERVER_ADMIN_PASSWORD"; then
        RCON_STATUS="NOT CONFIGURED"
        RCON_STATUS_COLOR="yellow"
        STATUS_NOTE="RCON not configured, cannot verify server responsiveness"
        return 0
    fi

    # Run RCON command with silent mode enabled
    local players_output=$(capture_all_output ark rcon "ListPlayers" --silent)
    echo "Players output: $players_output"

    # Check for error indicators in the output text
    if contains "$players_output" "with exit code: 1" || contains "$players_output" "failed" || contains "$players_output" "error"; then
        RCON_STATUS="ERROR"
        RCON_STATUS_COLOR="red"
        PLAYER_COUNT="0"
        return 0
    fi

    # Check for "not responding" in output
    if contains "$players_output" "not responding" || contains "$players_output" "RCON timeout"; then
        RCON_STATUS="NOT RESPONDING"
        RCON_STATUS_COLOR="yellow"
        PLAYER_COUNT="0"
        return 0
    fi

    # Server is fully online and responding
    RCON_STATUS="RESPONDING"
    RCON_STATUS_COLOR="green"

    # Parse player count based on output
    local player_count=0

    # Handle "No Players Connected" case explicitly
    if contains "$players_output" "No Players Connected"; then
        player_count=0
    elif ! is_empty "$players_output"; then
        # Count lines that match player entries (looking for lines with numbers followed by period)
        player_count=$(echo "$players_output" | grep -c "^[0-9]\+\.")
    fi

    PLAYER_COUNT="$player_count"

    return 0
}

# Get basic server status information
get_basic_status() {
    print_script_header "ARK Server Status"

    # Get status data through the variables
    set_basic_status_variables
    local status_result=$?

    # Show server status based on variables
    format_label_value "Server Status:" "$(print_status_box "$SERVER_STATUS" "$SERVER_STATUS_COLOR")"

    # If server is offline, just show minimal info
    if equals "$SERVER_STATUS" "OFFLINE"; then
        echo ""
        format_label_value "Process:" "$STATUS_NOTE"
        return $status_result
    fi

    # Server is running, show process info
    format_label_value "Process ID:" "$PROCESS_ID"
    format_label_value "Server Type:" "$SERVER_TYPE"

    # Show port info if available
    if ! is_empty "$LISTENING_PORT"; then
        format_label_value "Listening Port:" "$LISTENING_PORT"
    else
        format_label_value "Expected Port:" "$SERVER_PORT"
    fi

    # Show RCON status
    format_label_value "RCON Status:" "$(print_status_box "$RCON_STATUS" "$RCON_STATUS_COLOR")"

    # Show player count
    format_label_value "Online Players:" "$PLAYER_COUNT"

    # Show note if any
    if ! is_empty "$STATUS_NOTE"; then
        echo ""
        format_label_value "Note:" "$STATUS_NOTE"
    fi

    return $status_result
}

# =============================================================================
# DETAILED STATUS FUNCTIONS
# =============================================================================

# Function to set up EOS API credentials
setup_eos_credentials() {
    print_info "Setting up EOS API credentials..."

    # Check PDB is still available
    [[ ! -f "${ARK_DIR}/ShooterGame/Binaries/Win64/ArkAscendedServer.pdb" ]] && {
        print_error "❌ Missing PDB file: ${ARK_DIR}/ShooterGame/Binaries/Win64/ArkAscendedServer.pdb"
        print_info "This file is needed to extract server credentials."
        return 1
    }

    # Check if PDB tool exists, if not download it
    [[ ! -f "$PDB_TOOL" ]] && {
        print_info "Downloading pdb-sym2addr-rs tool..."

        local download_file="${MANAGER_DIR}/pdb-sym2addr-x86_64-unknown-linux-musl.tar.gz"
        local download_cmd="wget -q https://github.com/azixus/pdb-sym2addr-rs/releases/latest/download/pdb-sym2addr-x86_64-unknown-linux-musl.tar.gz -O ${download_file}"

        loading "$download_cmd" "Downloading PDB tool..."
        local download_status=$?

        # Check download status
        [[ $download_status -ne 0 ]] && {
            print_error "❌ Failed to download pdb-sym2addr-rs tool"
            return 1
        }

        # Extract the tool
        tar -xzf ${download_file} -C ${MANAGER_DIR}
        local extract_status=$?

        # Cleanup the tarball regardless of success
        rm -f ${download_file}

        # Check extract status
        [[ $extract_status -ne 0 ]] && {
            print_error "❌ Failed to extract pdb-sym2addr tool"
            return 1
        }

        # Check if the tool exists after extraction
        [[ ! -f "$PDB_TOOL" ]] && {
            print_error "❌ Tool file not found after extraction"
            return 1
        }

        chmod +x "$PDB_TOOL"

        # Verify it's executable
        [[ ! -x "$PDB_TOOL" ]] && {
            print_error "❌ Failed to make pdb-sym2addr tool executable"
            return 1
        }

        print_success "✅ PDB tool downloaded and set up successfully"
    }

    # Extract symbols
    print_info "Extracting EOS credentials from PDB file..."

    local extract_cmd="$PDB_TOOL ${ARK_DIR}/ShooterGame/Binaries/Win64/ArkAscendedServer.exe ${ARK_DIR}/ShooterGame/Binaries/Win64/ArkAscendedServer.pdb DedicatedServerClientSecret DedicatedServerClientId DeploymentId"
    local symbols=$(loading "$extract_cmd" "Extracting credentials")
    local extract_status=$?

    [[ $extract_status -ne 0 ]] && {
        print_error "❌ Failed to extract symbols from PDB file"
        return 1
    }

    # Parse values using the correct CSV column format
    local client_id=$(echo "$symbols" | grep "DedicatedServerClientId" | cut -d, -f3)
    local client_secret=$(echo "$symbols" | grep "DedicatedServerClientSecret" | cut -d, -f3)
    local deployment_id=$(echo "$symbols" | grep "DeploymentId" | cut -d, -f3)

    [[ -z "$client_id" || -z "$client_secret" || -z "$deployment_id" ]] && {
        print_error "❌ Failed to parse extracted symbols"
        print_info "Please check the PDB file and ensure it contains the required credentials."
        return 1
    }

    # Save base64 login and deployment id to file
    local creds=$(echo -n "$client_id:$client_secret" | base64 -w0)
    echo "${creds},${deployment_id}" >"$EOS_FILE"

    [[ ! -f "$EOS_FILE" ]] && {
        print_error "❌ Failed to save credentials to file"
        return 1
    }

    # Clean up - remove PDB tool to avoid bloat
    if [[ -f "$PDB_TOOL" ]]; then
        rm -f "$PDB_TOOL"

        [[ -f "$PDB_TOOL" ]] && {
            print_warning "⚠️ Failed to remove PDB tool, but credentials were saved successfully"
        }
    fi

    print_success "✅ EOS credentials extracted and saved successfully"
    return 0
}

# Function to prompt for first-time EOS setup
full_status_first_run() {
    print_script_header "First-time EOS API Setup"
    print_info "To display detailed server status, the Epic Online Services (EOS) API"
    print_info "credentials need to be extracted from the server binary files."
    print_info "The pdb-sym2addr-rs tool from GitHub (azixus/pdb-sym2addr-rs) will be downloaded."
    echo ""
    read -p "Do you want to proceed with this setup? [y/n]: " -n 1 -r
    echo ""

    [[ ! $REPLY =~ ^[Yy]$ ]] && {
        print_warning "⚠️ Detailed status setup cancelled"
        return 1
    }

    setup_eos_credentials
    return $?
}

# Function to handle detailed status logic and set variables
set_detailed_status_variables() {
    # Initialize detailed status variables
    DETAILED_EOS_STATUS="NOT CONFIGURED"
    DETAILED_EOS_COLOR="yellow"
    DETAILED_NOTE=""
    DETAILED_SERVER_NAME=""
    DETAILED_GAME_MODE=""
    DETAILED_MAP=""
    DETAILED_TIME_OF_DAY=""
    DETAILED_MAX_PLAYERS=""
    DETAILED_CURRENT_PLAYERS=""
    DETAILED_PLAYERS_RATIO=""
    DETAILED_BATTLEYE=""
    DETAILED_SERVER_VERSION=""
    DETAILED_PUBLIC_ADDRESS=""
    DETAILED_BIND_ADDRESS=""
    DETAILED_ACTIVE_MODS=""

    # First get basic status
    set_basic_status_variables
    local basic_status=$?

    # Bail out if server is not running or not listening
    if equals "$SERVER_STATUS" "OFFLINE" || is_empty "$LISTENING_PORT"; then
        return $basic_status
    fi

    # Check if EOS credentials exist
    if [ ! -f "$EOS_FILE" ]; then
        DETAILED_EOS_STATUS="NOT CONFIGURED"
        DETAILED_EOS_COLOR="yellow"
        DETAILED_NOTE="Epic Online Services credentials not found. Run with --full to set up."
        return 0
    fi

    # Read credentials from file
    local creds=$(cat "$EOS_FILE" | cut -d, -f1)
    local id=$(cat "$EOS_FILE" | cut -d, -f2)

    if is_empty "$creds" || is_empty "$id"; then
        DETAILED_EOS_STATUS="INVALID CREDENTIALS"
        DETAILED_EOS_COLOR="yellow"
        DETAILED_NOTE="Epic Online Services credentials format is invalid. Run with --full to regenerate."
        return 0
    fi

    # Get public IP
    local ip=""

    # Try multiple IP detection services
    for ip_service in "https://ifconfig.me/ip" "https://api.ipify.org" "https://icanhazip.com"; do
        ip=$(curl -s --max-time 5 "$ip_service" | tr -d '[:space:]')
        if ! is_empty "$ip" && [[ "$ip" =~ ^[0-9.]+$ ]]; then
            break
        fi
    done

    # Verify we have a valid IP
    if is_empty "$ip" || ! [[ "$ip" =~ ^[0-9.]+$ ]]; then
        DETAILED_EOS_STATUS="IP DETECTION FAILED"
        DETAILED_EOS_COLOR="yellow"
        DETAILED_NOTE="Failed to determine public IP address - cannot query EOS API"
        return 0
    fi

    # Get OAuth token
    local oauth_cmd="curl -s -m 10 -H 'Content-Type: application/x-www-form-urlencoded' -H 'Accept: application/json' -H \"Authorization: Basic ${creds}\" -X POST https://api.epicgames.dev/auth/v1/oauth/token -d \"grant_type=client_credentials&deployment_id=${id}\""
    local oauth=$(eval "$oauth_cmd")

    if is_empty "$oauth" || contains "$oauth" "error"; then
        DETAILED_EOS_STATUS="AUTH FAILED"
        DETAILED_EOS_COLOR="yellow"
        DETAILED_NOTE="Failed to authenticate with Epic Online Services API"
        return 0
    fi

    local token=$(echo "$oauth" | grep -o '"access_token":"[^"]*"' | sed 's/"access_token":"//;s/"//')

    if is_empty "$token"; then
        DETAILED_EOS_STATUS="TOKEN FAILED"
        DETAILED_EOS_COLOR="yellow"
        DETAILED_NOTE="Failed to extract access token from OAuth response"
        return 0
    fi

    # Query EOS for server information
    local json_data=$(
        cat <<EOF
{
  "criteria": [
    {
      "key": "attributes.ADDRESS_s",
      "op": "EQUAL",
      "value": "$ip"
    }
  ]
}
EOF
    )

    # Save to temporary file
    local temp_json=$(mktemp)
    echo "$json_data" >"$temp_json"

    # Use the file in the curl request
    local query_cmd="curl -s -m 10 -X POST \"https://api.epicgames.dev/matchmaking/v1/${id}/filter\" \
        -H \"Content-Type:application/json\" \
        -H \"Accept:application/json\" \
        -H \"Authorization: Bearer $token\" \
        -d @$temp_json"

    local res=$(eval "$query_cmd")

    # Clean up temporary file
    rm -f "$temp_json"

    # Check for errors
    if contains "$res" "errorCode"; then
        DETAILED_EOS_STATUS="API ERROR"
        DETAILED_EOS_COLOR="yellow"
        DETAILED_NOTE="EOS API returned an error"
        return 0
    fi

    # Extract server based on port
    local serv=$(echo "$res" | jq -r ".sessions[] | select(.attributes.ADDRESSBOUND_s | contains(\":${SERVER_PORT}\"))")

    if is_empty "$serv"; then
        DETAILED_EOS_STATUS="SERVER NOT FOUND"
        DETAILED_EOS_COLOR="yellow"
        DETAILED_NOTE="Server not found in EOS listings (may be starting up or not registered)"
        return 0
    fi

    # Set successful status
    DETAILED_EOS_STATUS="CONNECTED"
    DETAILED_EOS_COLOR="green"

    # Extract server information
    DETAILED_CURRENT_PLAYERS=$(echo "$serv" | jq -r '.totalPlayers')
    DETAILED_MAX_PLAYERS=$(echo "$serv" | jq -r '.settings.maxPublicPlayers')
    DETAILED_PLAYERS_RATIO="${DETAILED_CURRENT_PLAYERS} / ${DETAILED_MAX_PLAYERS}"
    DETAILED_SERVER_NAME=$(echo "$serv" | jq -r '.attributes.CUSTOMSERVERNAME_s')
    DETAILED_TIME_OF_DAY=$(echo "$serv" | jq -r '.attributes.DAYTIME_s')

    local battleye=$(echo "$serv" | jq -r '.attributes.SERVERUSESBATTLEYE_b')
    DETAILED_BATTLEYE="Disabled"
    if equals "$battleye" "true"; then
        DETAILED_BATTLEYE="Enabled"
    fi

    local server_ip=$(echo "$serv" | jq -r '.attributes.ADDRESS_s')
    local bind=$(echo "$serv" | jq -r '.attributes.ADDRESSBOUND_s')
    local bind_ip=${bind%:*}
    local bind_port=${bind#*:}
    DETAILED_PUBLIC_ADDRESS="${server_ip}:${bind_port}"
    DETAILED_BIND_ADDRESS="${bind}"

    DETAILED_MAP=$(echo "$serv" | jq -r '.attributes.MAPNAME_s')

    local major=$(echo "$serv" | jq -r '.attributes.BUILDID_s')
    local minor=$(echo "$serv" | jq -r '.attributes.MINORBUILDID_s')
    DETAILED_SERVER_VERSION="${major}.${minor}"

    local pve=$(echo "$serv" | jq -r '.attributes.SESSIONISPVE_l')
    DETAILED_GAME_MODE="PvP"
    if equals "$pve" "1"; then
        DETAILED_GAME_MODE="PvE"
    fi

    local mods=$(echo "$serv" | jq -r '.attributes.ENABLEDMODS_s')
    DETAILED_ACTIVE_MODS="None"
    if ! equals "$mods" "null" && ! is_empty "$mods"; then
        DETAILED_ACTIVE_MODS="$mods"
    fi

    return 0
}

# Function to display detailed status using EOS API
get_detailed_status() {
    # Get detailed status information
    set_detailed_status_variables
    local status_result=$?

    # Print the header
    print_script_header "ARK Server Status (Detailed)"

    # Process is not running
    if equals "$SERVER_STATUS" "OFFLINE"; then
        format_label_value "Server Status:" "$(print_status_box "$SERVER_STATUS" "$SERVER_STATUS_COLOR")"
        echo ""
        format_label_value "Process:" "$STATUS_NOTE"
        return 1
    fi

    # Server is running, show process info
    format_label_value "Process ID:" "$PROCESS_ID"
    format_label_value "Server Type:" "$SERVER_TYPE"

    # Show port info if available
    if ! is_empty "$LISTENING_PORT"; then
        format_label_value "Listening Port:" "$LISTENING_PORT"
    else
        format_label_value "Network Status:" "$(print_status_box "NOT LISTENING" "yellow")"
        format_label_value "Expected Port:" "$SERVER_PORT"
        format_label_value "Server Status:" "$(print_status_box "$SERVER_STATUS" "$SERVER_STATUS_COLOR")"
        echo ""
        format_label_value "Note:" "$STATUS_NOTE"
        return 2
    fi

    # Show RCON status
    format_label_value "RCON Status:" "$(print_status_box "$RCON_STATUS" "$RCON_STATUS_COLOR")"

    # If we're still here, show online status and players count
    format_label_value "Server Status:" "$(print_status_box "$SERVER_STATUS" "$SERVER_STATUS_COLOR")"
    format_label_value "EOS Status:" "$(print_status_box "$DETAILED_EOS_STATUS" "$DETAILED_EOS_COLOR")"

    # Check if this is a first-run situation for EOS setup
    if equals "$DETAILED_EOS_STATUS" "NOT CONFIGURED"; then
        format_label_value "Online Players:" "$PLAYER_COUNT"
        echo ""
        format_label_value "Note:" "$DETAILED_NOTE"

        # Prompt for first-time setup
        echo ""
        full_status_first_run
        if [ $? -eq 0 ]; then
            # If setup succeeded, retry with new credentials
            set_detailed_status_variables

            # Only show detailed info if we connected successfully
            if equals "$DETAILED_EOS_STATUS" "CONNECTED"; then
                # Clear screen and redisplay
                clear
                get_detailed_status
                return $?
            fi
        fi

        return 0
    elif contains "$DETAILED_EOS_STATUS" "INVALID CREDENTIALS" || equals "$DETAILED_EOS_STATUS" "AUTH FAILED" || equals "$DETAILED_EOS_STATUS" "API ERROR"; then
        # For credential issues, try regenerating silently
        format_label_value "Online Players:" "$PLAYER_COUNT"
        echo ""
        format_label_value "Note:" "$DETAILED_NOTE"

        # Try regenerating credentials
        echo ""
        print_warning "⚠️ Attempting to regenerate EOS credentials..."
        setup_eos_credentials

        if [ $? -eq 0 ]; then
            # If regeneration succeeded, retry with new credentials
            set_detailed_status_variables

            # Only show detailed info if we connected successfully
            if equals "$DETAILED_EOS_STATUS" "CONNECTED"; then
                # Clear screen and redisplay
                clear
                get_detailed_status
                return $?
            fi
        fi

        return 0
    fi

    # Show player count (from detailed if available, otherwise from basic)
    if equals "$DETAILED_EOS_STATUS" "CONNECTED"; then
        format_label_value "Online Players:" "$DETAILED_PLAYERS_RATIO"

        # Show detailed server information
        echo ""
        format_label_value "Server Name:" "$DETAILED_SERVER_NAME"
        format_label_value "Game Mode:" "$DETAILED_GAME_MODE"
        format_label_value "Map:" "$DETAILED_MAP"
        format_label_value "Day:" "$DETAILED_TIME_OF_DAY"
        format_label_value "BattlEye:" "$DETAILED_BATTLEYE"
        format_label_value "Server Version:" "$DETAILED_SERVER_VERSION"
        format_label_value "Public Address:" "$DETAILED_PUBLIC_ADDRESS"
        format_label_value "Bind Address:" "$DETAILED_BIND_ADDRESS"
        format_label_value "Active Mods:" "$DETAILED_ACTIVE_MODS"
    else
        format_label_value "Online Players:" "$PLAYER_COUNT"

        # Show note if we couldn't get detailed info
        if ! is_empty "$DETAILED_NOTE"; then
            echo ""
            format_label_value "Note:" "$DETAILED_NOTE"
        fi
    fi

    return $status_result
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

# Parse command line arguments
parse_arguments() {
    SHOW_FULL_STATUS="no"

    while [[ $# -gt 0 ]]; do
        case "$1" in
        --full | -f)
            SHOW_FULL_STATUS="yes"
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

    # Check required environment variables
    check_required_env REQUIRED_VARS || exit 1

    # Display status based on mode
    if equals "$SHOW_FULL_STATUS" "yes"; then
        get_detailed_status
    else
        get_basic_status
    fi

    exit $?
}

# Execute the main function with all arguments
main "$@"
