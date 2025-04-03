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
UTILS_PATH="$MANAGER_DIR/utils"
source "${UTILS_PATH}/common.sh"

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
    [[ -z "$ip" ]] && {
        echo "0.0.0.0"
        return 0
    }
    echo "$ip"
}

# Function to display server status box
print_status_box() {
    local status="$1"
    local color="$2"

    [[ "$USE_COLOR" != "yes" ]] && {
        echo "[ $status ]"
        return 0
    }

    case "$color" in
    "green") echo -e "\033[1;32m[ $status ]\033[0m" ;;
    "red") echo -e "\033[1;31m[ $status ]\033[0m" ;;
    "yellow") echo -e "\033[1;33m[ $status ]\033[0m" ;;
    *) echo -e "[ $status ]" ;;
    esac
}

# Function to format label and value
format_label_value() {
    local label="$1"
    local value="$2"
    local pad_length=20

    # Calculate padding
    local padding=""
    for ((i = 0; i < $(($pad_length - ${#label})); i++)); do
        padding+=" "
    done

    [[ "$USE_COLOR" == "yes" ]] && {
        echo -e "\033[1;36m${label}${padding}\033[0m ${value}"
        return 0
    }

    echo -e "${label}${padding} ${value}"
}

# Function to get the server's listening port
get_listening_port() {
    # Get ARK server PID using the utility function
    local ark_pid=$(get_ark_server_pid)

    [[ "$ark_pid" == "0" ]] && return 1

    # Look for connections on SERVER_PORT or any port if SERVER_PORT is not specified
    [[ -n "$SERVER_PORT" ]] && {
        # Look specifically for the configured server port
        local port_info=$(ss -tupln | grep -E "$ark_pid.*:$SERVER_PORT" | head -1)
        [[ -n "$port_info" ]] && {
            echo "$SERVER_PORT"
            return 0
        }
    }

    # No specific server port configured or not found, get the first port this process listens on
    local listening_ports=$(ss -tupln | grep -E "$ark_pid" | grep -oP '(?<=:)\d+' | head -1)
    [[ -n "$listening_ports" ]] && {
        echo "$listening_ports"
        return 0
    }

    # Try to find the port by looking at UDP connections, as ARK server uses UDP
    local udp_port=$(ss -uplna | grep -E "$ark_pid" | grep -oP '(?<=:)\d+' | head -1)
    [[ -n "$udp_port" ]] && {
        echo "$udp_port"
        return 0
    }

    # As a last resort, check for any port close to the configured SERVER_PORT
    [[ -n "$SERVER_PORT" ]] && {
        # Check if any process is listening on the expected port
        local any_process_port=$(ss -tupln | grep ":$SERVER_PORT" | grep -oP '(?<=:)\d+')
        [[ -n "$any_process_port" ]] && {
            echo "$any_process_port"
            return 0
        }
    }

    # No port found
    return 1
}

# =============================================================================
# BASIC STATUS FUNCTIONS
# =============================================================================

# Get basic server status information
get_basic_status() {
    print_script_header "ARK Server Status"

    # Get the server PID
    local ark_pid=$(get_ark_server_pid)
    [[ "$ark_pid" == "0" ]] && {
        format_label_value "Server Status:" "$(print_status_box "OFFLINE" "red")"
        echo ""
        format_label_value "Process:" "Not running"
        return 1
    }

    # Server is running, show process info
    format_label_value "Process ID:" "$ark_pid"

    # Show server type (API or regular)
    local server_type="Game Server"
    ps -p "$ark_pid" -o cmd= | grep -q "AsaApiLoader" && server_type="API Server"
    format_label_value "Server Type:" "$server_type"

    # Check if server is listening on the port
    local listening_port=$(get_listening_port)
    [[ -z "$listening_port" ]] && {
        format_label_value "Network Status:" "$(print_status_box "NOT LISTENING" "yellow")"
        format_label_value "Expected Port:" "$SERVER_PORT"
        format_label_value "Server Status:" "$(print_status_box "STARTING" "yellow")"
        echo ""
        format_label_value "Note:" "Server is running but not yet listening on network port"
        return 2
    }

    format_label_value "Listening Port:" "$listening_port"

    # Check if RCON is available
    [[ -z "$RCON_PORT" || -z "$ARK_ADMIN_PASSWORD" ]] && {
        format_label_value "RCON Status:" "$(print_status_box "NOT CONFIGURED" "yellow")"
        format_label_value "Server Status:" "$(print_status_box "UNKNOWN" "yellow")"
        format_label_value "Note:" "RCON not configured, cannot verify server responsiveness"
        return 0
    }

    # Set up rcon command
    local container_ip=$(get_container_ip)
    local rcon_path="/home/arkuser/.local/bin/rcon"
    local rcon_cmd=("${rcon_path}" -a "${container_ip}:${RCON_PORT}" -p "${ARK_ADMIN_PASSWORD}" -t 5)

    # Try to execute a listplayers command
    local players_output=$("${rcon_cmd[@]}" ListPlayers 2>/dev/null)
    local rcon_result=$?

    [[ $rcon_result -ne 0 ]] && {
        format_label_value "RCON Status:" "$(print_status_box "NOT RESPONDING" "yellow")"
        format_label_value "Server Status:" "$(print_status_box "STARTING" "yellow")"
        return 0
    }

    format_label_value "RCON Status:" "$(print_status_box "RESPONDING" "green")"

    # Parse player count
    local player_count=0
    [[ "$players_output" != "No Players"* ]] && {
        player_count=$(echo "$players_output" | grep -v "^$" | wc -l)
        format_label_value "Online Players:" "$player_count"
        [[ $player_count -gt 0 ]] && {
            echo ""
            echo "Player List:"
            echo "------------"
            echo "$players_output" | grep -v "^$"
        }
    } || {
        format_label_value "Online Players:" "0"
    }

    format_label_value "Server Status:" "$(print_status_box "ONLINE" "green")"
    return 0
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
        local download_cmd="wget -q https://github.com/azixus/pdb-sym2addr-rs/releases/latest/download/pdb-sym2addr-x86_64-unknown-linux-musl.tar.gz -O ${MANAGER_DIR}/pdb-sym2addr-x86_64-unknown-linux-musl.tar.gz"

        run_with_spinner "$download_cmd" "Downloading PDB tool..."

        [[ $? -ne 0 ]] && {
            print_error "❌ Failed to download pdb-sym2addr-rs tool"
            return 1
        }

        tar -xzf ${MANAGER_DIR}/pdb-sym2addr-x86_64-unknown-linux-musl.tar.gz -C ${MANAGER_DIR}
        rm ${MANAGER_DIR}/pdb-sym2addr-x86_64-unknown-linux-musl.tar.gz

        [[ ! -f "$PDB_TOOL" ]] && {
            print_error "❌ Failed to extract pdb-sym2addr tool"
            return 1
        }

        chmod +x "$PDB_TOOL"
    }

    # Extract symbols
    print_info "Extracting EOS credentials from PDB file..."
    local extract_cmd="$PDB_TOOL ${ARK_DIR}/ShooterGame/Binaries/Win64/ArkAscendedServer.exe ${ARK_DIR}/ShooterGame/Binaries/Win64/ArkAscendedServer.pdb DedicatedServerClientSecret DedicatedServerClientId DeploymentId"

    local symbols=$(run_with_spinner "$extract_cmd" "Extracting credentials...")

    [[ $? -ne 0 ]] && {
        print_error "❌ Failed to extract symbols from PDB file"
        return 1
    }

    # Parse symbols
    local client_id=$(echo "$symbols" | grep -o 'DedicatedServerClientId.*' | cut -d, -f2)
    local client_secret=$(echo "$symbols" | grep -o 'DedicatedServerClientSecret.*' | cut -d, -f2)
    local deployment_id=$(echo "$symbols" | grep -o 'DeploymentId.*' | cut -d, -f2)

    [[ -z "$client_id" || -z "$client_secret" || -z "$deployment_id" ]] && {
        print_error "❌ Failed to parse extracted symbols"
        return 1
    }

    # Save base64 login and deployment id to file
    local creds=$(echo -n "$client_id:$client_secret" | base64 -w0)
    echo "${creds},${deployment_id}" >"$EOS_FILE"

    [[ ! -f "$EOS_FILE" ]] && {
        print_error "❌ Failed to save credentials to file"
        return 1
    }

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

# Function to display detailed status using EOS API
get_detailed_status() {
    # First check if we have basic server connectivity
    get_basic_status
    local basic_status=$?

    [[ $basic_status -eq 1 ]] && {
        # Server is offline, no need to continue
        print_warning "⚠️ Server is offline, cannot retrieve detailed status"
        return 1
    }

    echo ""
    print_script_header "Detailed Server Information"

    # Check if EOS credentials exist
    [[ ! -f "$EOS_FILE" ]] && {
        print_warning "⚠️ EOS credentials not found"
        full_status_first_run
        [[ $? -ne 0 ]] && return 1
    }

    # Read EOS credentials
    local creds=$(cat "$EOS_FILE" | cut -d, -f1)
    local id=$(cat "$EOS_FILE" | cut -d, -f2)

    [[ -z "$creds" || -z "$id" ]] && {
        print_error "❌ Invalid EOS credentials format"
        # Try to regenerate
        setup_eos_credentials
        [[ $? -ne 0 ]] && return 1
        creds=$(cat "$EOS_FILE" | cut -d, -f1)
        id=$(cat "$EOS_FILE" | cut -d, -f2)
    }

    # Get public IP
    local ip_cmd="curl -s -m 5 https://ifconfig.me/ip || curl -s -m 5 https://api.ipify.org || curl -s -m 5 https://icanhazip.com"
    local ip=$(run_with_spinner "$ip_cmd" "Determining public IP...")

    [[ -z "$ip" ]] && {
        print_error "❌ Failed to determine public IP address"
        return 1
    }

    print_info "Connecting to Epic Online Services API..."

    # Get OAuth token
    local oauth_cmd="curl -s -m 10 -H 'Content-Type: application/x-www-form-urlencoded' -H 'Accept: application/json' -H \"Authorization: Basic ${creds}\" -X POST https://api.epicgames.dev/auth/v1/oauth/token -d \"grant_type=client_credentials&deployment_id=${id}\""
    local oauth=$(run_with_spinner "$oauth_cmd" "Authenticating with EOS API...")

    [[ -z "$oauth" || "$oauth" == *"error"* ]] && {
        print_error "❌ Failed to authenticate with EOS API"
        print_info "API response: $oauth"
        print_warning "⚠️ Credentials may be outdated. Attempting to regenerate..."
        setup_eos_credentials
        [[ $? -ne 0 ]] && return 1
        # Retry with new credentials
        creds=$(cat "$EOS_FILE" | cut -d, -f1)
        id=$(cat "$EOS_FILE" | cut -d, -f2)
        oauth=$(run_with_spinner "$oauth_cmd" "Retrying authentication with new credentials...")
    }

    local token=$(echo "$oauth" | grep -o '"access_token":"[^"]*"' | sed 's/"access_token":"//;s/"//')

    [[ -z "$token" ]] && {
        print_error "❌ Failed to extract access token from OAuth response"
        return 1
    }

    # Query EOS for server information
    local query_cmd="curl -s -m 10 -X \"POST\" \"https://api.epicgames.dev/matchmaking/v1/${id}/filter\" \
        -H \"Content-Type:application/json\" \
        -H \"Accept:application/json\" \
        -H \"Authorization: Bearer $token\" \
        -d \"{\\\"criteria\\\": [{\\\"key\\\": \\\"attributes.ADDRESS_s\\\", \\\"op\\\": \\\"EQUAL\\\", \\\"value\\\": \\\"${ip}\\\"}]}\""

    local res=$(run_with_spinner "$query_cmd" "Querying EOS API for server information...")

    # Check for errors
    [[ "$res" == *"errorCode"* ]] && {
        print_error "❌ Failed to query EOS API"
        print_info "API error: $res"
        print_warning "⚠️ Retrying once with regenerated credentials..."
        setup_eos_credentials
        [[ $? -ne 0 ]] && return 1
        # Retry the entire process with new credentials
        get_detailed_status
        return $?
    }

    # Extract server based on port
    local serv=$(echo "$res" | jq -r ".sessions[] | select( .attributes.ADDRESSBOUND_s | contains(\":${SERVER_PORT}\"))")

    [[ -z "$serv" ]] && {
        print_warning "⚠️ Server not found in EOS listings"
        print_info "The server may be starting up or not yet registered with EOS"
        return 1
    }

    # Extract server information
    local curr_players=$(echo "$serv" | jq -r '.totalPlayers')
    local max_players=$(echo "$serv" | jq -r '.settings.maxPublicPlayers')
    local serv_name=$(echo "$serv" | jq -r '.attributes.CUSTOMSERVERNAME_s')
    local day=$(echo "$serv" | jq -r '.attributes.DAYTIME_s')
    local battleye=$(echo "$serv" | jq -r '.attributes.SERVERUSESBATTLEYE_b')
    local server_ip=$(echo "$serv" | jq -r '.attributes.ADDRESS_s')
    local bind=$(echo "$serv" | jq -r '.attributes.ADDRESSBOUND_s')
    local map=$(echo "$serv" | jq -r '.attributes.MAPNAME_s')
    local major=$(echo "$serv" | jq -r '.attributes.BUILDID_s')
    local minor=$(echo "$serv" | jq -r '.attributes.MINORBUILDID_s')
    local pve=$(echo "$serv" | jq -r '.attributes.SESSIONISPVE_l')
    local mods=$(echo "$serv" | jq -r '.attributes.ENABLEDMODS_s')
    local bind_ip=${bind%:*}
    local bind_port=${bind#*:}

    # Format PvE/PvP
    local game_mode="PvP"
    [[ "$pve" == "1" ]] && game_mode="PvE"

    # Format BattlEye
    local battleye_status="Disabled"
    [[ "$battleye" == "true" ]] && battleye_status="Enabled"

    # Format mods
    [[ "$mods" == "null" || -z "$mods" ]] && mods="None"

    # Display detailed status
    format_label_value "Server Name:" "$serv_name"
    format_label_value "Game Mode:" "$game_mode"
    format_label_value "Map:" "$map"
    format_label_value "Time of Day:" "$day"
    format_label_value "Players:" "$curr_players / $max_players"
    format_label_value "BattlEye:" "$battleye_status"
    format_label_value "Server Version:" "${major}.${minor}"
    format_label_value "Public Address:" "${server_ip}:${bind_port}"
    format_label_value "Bind Address:" "${bind}"
    format_label_value "Active Mods:" "$mods"

    echo ""
    format_label_value "Server Status:" "$(print_status_box "ONLINE" "green")"

    return 0
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

# Parse command line arguments
parse_arguments() {
    SHOW_FULL_STATUS="no"
    USE_COLOR="yes"

    while [[ $# -gt 0 ]]; do
        case "$1" in
        --full | -f)
            SHOW_FULL_STATUS="yes"
            shift
            ;;
        --no-color | -n)
            USE_COLOR="no"
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
    # Create PID file for this script
    create_pid_file

    # Parse command line arguments
    parse_arguments "$@"

    # Check required environment variables
    check_required_env REQUIRED_VARS || exit 1

    # Display status based on mode
    [[ "$SHOW_FULL_STATUS" == "yes" ]] && {
        get_detailed_status
    } || {
        get_basic_status
    }

    exit $?
}

# Execute the main function with all arguments
main "$@"
