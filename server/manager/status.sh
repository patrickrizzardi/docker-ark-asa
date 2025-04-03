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
source "${UTILS_PATH}/colorPrinter.sh"
source "${UTILS_PATH}/processManager.sh"
source "${UTILS_PATH}/envManager.sh"

# =============================================================================
# CONFIGURATION
# =============================================================================

# Required environment variables
declare -a STATUS_REQUIRED_VARS=(
    "ARK_DIR"     # ARK installation directory
    "SERVER_PORT" # Server port
)

# Optional environment variables
declare -a STATUS_OPTIONAL_VARS=(
    "RCON_PORT"          # RCON port
    "ARK_ADMIN_PASSWORD" # Admin password for RCON commands
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
    if [[ -z "$ip" ]]; then
        echo "0.0.0.0" # Fallback to all interfaces
    else
        echo "$ip"
    fi
}

# Function to display server status box
print_status_box() {
    local status="$1"
    local color="$2"

    if [[ "$USE_COLOR" == "yes" ]]; then
        case "$color" in
        "green") echo -e "\033[1;32m[ $status ]\033[0m" ;;
        "red") echo -e "\033[1;31m[ $status ]\033[0m" ;;
        "yellow") echo -e "\033[1;33m[ $status ]\033[0m" ;;
        *) echo -e "[ $status ]" ;;
        esac
    else
        echo "[ $status ]"
    fi
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

    if [[ "$USE_COLOR" == "yes" ]]; then
        echo -e "\033[1;36m${label}${padding}\033[0m ${value}"
    else
        echo -e "${label}${padding} ${value}"
    fi
}

# Function to get the server's listening port
get_listening_port() {
    # Get ARK server PID using the utility function
    local ark_pid=$(get_ark_server_pid)

    if [[ "$ark_pid" == "0" ]]; then
        # No ARK process found
        return 1
    fi

    # Look for connections on SERVER_PORT or any port if SERVER_PORT is not specified
    if [[ -n "$SERVER_PORT" ]]; then
        # Look specifically for the configured server port
        local port_info=$(ss -tupln | grep -E "$ark_pid.*:$SERVER_PORT" | head -1)
        if [[ -n "$port_info" ]]; then
            echo "$SERVER_PORT"
            return 0
        fi
    else
        # No specific server port configured, get the first port this process listens on
        local listening_ports=$(ss -tupln | grep -E "$ark_pid" | grep -oP '(?<=:)\d+' | head -1)
        if [[ -n "$listening_ports" ]]; then
            echo "$listening_ports"
            return 0
        fi
    fi

    # Try to find the port by looking at UDP connections, as ARK server uses UDP
    local udp_port=$(ss -uplna | grep -E "$ark_pid" | grep -oP '(?<=:)\d+' | head -1)
    if [[ -n "$udp_port" ]]; then
        echo "$udp_port"
        return 0
    fi

    # As a last resort, check for any port close to the configured SERVER_PORT
    if [[ -n "$SERVER_PORT" ]]; then
        # Check if any process is listening on the expected port
        local any_process_port=$(ss -tupln | grep ":$SERVER_PORT" | grep -oP '(?<=:)\d+')
        if [[ -n "$any_process_port" ]]; then
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

# Get basic server status information
get_basic_status() {
    print_header "🎮 ARK Server Status"
    echo ""

    # Get the server PID
    local ark_pid=$(get_ark_server_pid)
    if [[ "$ark_pid" == "0" ]]; then
        format_label_value "Server Status:" "$(print_status_box "OFFLINE" "red")"
        echo ""
        format_label_value "Process:" "Not running"
        return 1
    fi

    # Server is running, show process info
    format_label_value "Process ID:" "$ark_pid"

    # Show server type (API or regular)
    local server_type="Game Server"
    if ps -p "$ark_pid" -o cmd= | grep -q "AsaApiLoader"; then
        server_type="API Server"
    fi
    format_label_value "Server Type:" "$server_type"

    # Check if server is listening on the port
    local listening_port=$(get_listening_port)
    if [[ -z "$listening_port" ]]; then
        format_label_value "Network Status:" "$(print_status_box "NOT LISTENING" "yellow")"
        format_label_value "Expected Port:" "$SERVER_PORT"
        format_label_value "Server Status:" "$(print_status_box "STARTING" "yellow")"
        echo ""
        format_label_value "Note:" "Server is running but not yet listening on network port"
        return 2
    fi

    format_label_value "Listening Port:" "$listening_port"

    # Check if RCON is available
    if [[ -n "$RCON_PORT" && -n "$ARK_ADMIN_PASSWORD" ]]; then
        # Set up rcon command
        local container_ip=$(get_container_ip)
        local rcon_path="/home/arkuser/.local/bin/rcon"
        local rcon_cmd=("${rcon_path}" -a "${container_ip}:${RCON_PORT}" -p "${ARK_ADMIN_PASSWORD}" -t 5)

        # Try to execute a listplayers command
        local players_output=$("${rcon_cmd[@]}" ListPlayers 2>/dev/null)
        local rcon_result=$?

        if [[ $rcon_result -eq 0 ]]; then
            format_label_value "RCON Status:" "$(print_status_box "RESPONDING" "green")"

            # Parse player count
            local player_count=0
            if [[ "$players_output" != "No Players"* ]]; then
                player_count=$(echo "$players_output" | grep -v "^$" | wc -l)
                format_label_value "Online Players:" "$player_count"
                if [[ $player_count -gt 0 ]]; then
                    echo ""
                    echo "Player List:"
                    echo "------------"
                    echo "$players_output" | grep -v "^$"
                fi
            else
                format_label_value "Online Players:" "0"
            fi

            format_label_value "Server Status:" "$(print_status_box "ONLINE" "green")"
        else
            format_label_value "RCON Status:" "$(print_status_box "NOT RESPONDING" "yellow")"
            format_label_value "Server Status:" "$(print_status_box "STARTING" "yellow")"
        fi
    else
        format_label_value "RCON Status:" "$(print_status_box "NOT CONFIGURED" "yellow")"
        format_label_value "Server Status:" "$(print_status_box "UNKNOWN" "yellow")"
        format_label_value "Note:" "RCON not configured, cannot verify server responsiveness"
    fi

    return 0
}

# =============================================================================
# DETAILED STATUS FUNCTIONS
# =============================================================================

# Function to set up EOS API credentials
setup_eos_credentials() {
    print_info "Setting up EOS API credentials..."

    # Check PDB is still available
    if [[ ! -f "${ARK_DIR}/ShooterGame/Binaries/Win64/ArkAscendedServer.pdb" ]]; then
        print_error "❌ Missing PDB file: ${ARK_DIR}/ShooterGame/Binaries/Win64/ArkAscendedServer.pdb"
        print_info "This file is needed to extract server credentials."
        return 1
    fi

    # Check if PDB tool exists, if not download it
    if [[ ! -f "$PDB_TOOL" ]]; then
        print_info "Downloading pdb-sym2addr-rs tool..."
        wget -q https://github.com/azixus/pdb-sym2addr-rs/releases/latest/download/pdb-sym2addr-x86_64-unknown-linux-musl.tar.gz -O ${MANAGER_DIR}/pdb-sym2addr-x86_64-unknown-linux-musl.tar.gz

        if [[ $? -ne 0 ]]; then
            print_error "❌ Failed to download pdb-sym2addr-rs tool"
            return 1
        fi

        tar -xzf ${MANAGER_DIR}/pdb-sym2addr-x86_64-unknown-linux-musl.tar.gz -C ${MANAGER_DIR}
        rm ${MANAGER_DIR}/pdb-sym2addr-x86_64-unknown-linux-musl.tar.gz

        if [[ ! -f "$PDB_TOOL" ]]; then
            print_error "❌ Failed to extract pdb-sym2addr tool"
            return 1
        fi

        chmod +x "$PDB_TOOL"
    fi

    # Extract symbols
    print_info "Extracting EOS credentials from PDB file..."
    local symbols=$("$PDB_TOOL" ${ARK_DIR}/ShooterGame/Binaries/Win64/ArkAscendedServer.exe ${ARK_DIR}/ShooterGame/Binaries/Win64/ArkAscendedServer.pdb DedicatedServerClientSecret DedicatedServerClientId DeploymentId)

    if [[ $? -ne 0 ]]; then
        print_error "❌ Failed to extract symbols from PDB file"
        return 1
    fi

    # Parse symbols
    local client_id=$(echo "$symbols" | grep -o 'DedicatedServerClientId.*' | cut -d, -f2)
    local client_secret=$(echo "$symbols" | grep -o 'DedicatedServerClientSecret.*' | cut -d, -f2)
    local deployment_id=$(echo "$symbols" | grep -o 'DeploymentId.*' | cut -d, -f2)

    if [[ -z "$client_id" || -z "$client_secret" || -z "$deployment_id" ]]; then
        print_error "❌ Failed to parse extracted symbols"
        return 1
    fi

    # Save base64 login and deployment id to file
    local creds=$(echo -n "$client_id:$client_secret" | base64 -w0)
    echo "${creds},${deployment_id}" >"$EOS_FILE"

    if [[ ! -f "$EOS_FILE" ]]; then
        print_error "❌ Failed to save credentials to file"
        return 1
    fi

    print_success "✅ EOS credentials extracted and saved successfully"
    return 0
}

# Function to prompt for first-time EOS setup
full_status_first_run() {
    print_header "⚙️ First-time EOS API Setup"
    echo ""
    print_info "To display detailed server status, the Epic Online Services (EOS) API"
    print_info "credentials need to be extracted from the server binary files."
    print_info "The pdb-sym2addr-rs tool from GitHub (azixus/pdb-sym2addr-rs) will be downloaded."
    echo ""
    read -p "Do you want to proceed with this setup? [y/n]: " -n 1 -r
    echo ""

    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_warning "⚠️ Detailed status setup cancelled"
        return 1
    fi

    setup_eos_credentials
    return $?
}

# Function to display detailed status using EOS API
get_detailed_status() {
    # First check if we have basic server connectivity
    get_basic_status
    local basic_status=$?

    if [[ $basic_status -eq 1 ]]; then
        # Server is offline, no need to continue
        print_warning "⚠️ Server is offline, cannot retrieve detailed status"
        return 1
    fi

    echo ""
    print_header "🔍 Detailed Server Information"
    echo ""

    # Check if EOS credentials exist
    if [[ ! -f "$EOS_FILE" ]]; then
        print_warning "⚠️ EOS credentials not found"
        full_status_first_run
        if [[ $? -ne 0 ]]; then
            return 1
        fi
    fi

    # Read EOS credentials
    local creds=$(cat "$EOS_FILE" | cut -d, -f1)
    local id=$(cat "$EOS_FILE" | cut -d, -f2)

    if [[ -z "$creds" || -z "$id" ]]; then
        print_error "❌ Invalid EOS credentials format"
        # Try to regenerate
        setup_eos_credentials
        if [[ $? -ne 0 ]]; then
            return 1
        fi
        creds=$(cat "$EOS_FILE" | cut -d, -f1)
        id=$(cat "$EOS_FILE" | cut -d, -f2)
    fi

    # Get public IP
    local ip=$(curl -s -m 5 https://ifconfig.me/ip || curl -s -m 5 https://api.ipify.org || curl -s -m 5 https://icanhazip.com)

    if [[ -z "$ip" ]]; then
        print_error "❌ Failed to determine public IP address"
        return 1
    fi

    print_info "Connecting to Epic Online Services API..."

    # Get OAuth token
    local oauth=$(curl -s -m 10 -H 'Content-Type: application/x-www-form-urlencoded' -H 'Accept: application/json' -H "Authorization: Basic ${creds}" -X POST https://api.epicgames.dev/auth/v1/oauth/token -d "grant_type=client_credentials&deployment_id=${id}")

    if [[ -z "$oauth" || "$oauth" == *"error"* ]]; then
        print_error "❌ Failed to authenticate with EOS API"
        print_info "API response: $oauth"
        print_warning "⚠️ Credentials may be outdated. Attempting to regenerate..."
        setup_eos_credentials
        if [[ $? -ne 0 ]]; then
            return 1
        fi
        # Retry with new credentials
        creds=$(cat "$EOS_FILE" | cut -d, -f1)
        id=$(cat "$EOS_FILE" | cut -d, -f2)
        oauth=$(curl -s -m 10 -H 'Content-Type: application/x-www-form-urlencoded' -H 'Accept: application/json' -H "Authorization: Basic ${creds}" -X POST https://api.epicgames.dev/auth/v1/oauth/token -d "grant_type=client_credentials&deployment_id=${id}")
    fi

    local token=$(echo "$oauth" | grep -o '"access_token":"[^"]*"' | sed 's/"access_token":"//;s/"//')

    if [[ -z "$token" ]]; then
        print_error "❌ Failed to extract access token from OAuth response"
        return 1
    fi

    # Query EOS for server information
    local res=$(curl -s -m 10 -X "POST" "https://api.epicgames.dev/matchmaking/v1/${id}/filter" \
        -H "Content-Type:application/json" \
        -H "Accept:application/json" \
        -H "Authorization: Bearer $token" \
        -d "{\"criteria\": [{\"key\": \"attributes.ADDRESS_s\", \"op\": \"EQUAL\", \"value\": \"${ip}\"}]}")

    # Check for errors
    if [[ "$res" == *"errorCode"* ]]; then
        print_error "❌ Failed to query EOS API"
        print_info "API error: $res"
        print_warning "⚠️ Retrying once with regenerated credentials..."
        setup_eos_credentials
        if [[ $? -ne 0 ]]; then
            return 1
        fi
        # Retry the entire process with new credentials
        get_detailed_status
        return $?
    fi

    # Extract server based on port
    local serv=$(echo "$res" | jq -r ".sessions[] | select( .attributes.ADDRESSBOUND_s | contains(\":${SERVER_PORT}\"))")

    if [[ -z "$serv" ]]; then
        print_warning "⚠️ Server not found in EOS listings"
        print_info "The server may be starting up or not yet registered with EOS"
        return 1
    fi

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
    if [[ "$pve" == "1" ]]; then
        game_mode="PvE"
    fi

    # Format BattlEye
    local battleye_status="Disabled"
    if [[ "$battleye" == "true" ]]; then
        battleye_status="Enabled"
    fi

    # Format mods
    if [[ "$mods" == "null" || -z "$mods" ]]; then
        mods="None"
    fi

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
    # Parse command line arguments
    parse_arguments "$@"

    # Check required environment variables
    if ! check_env_variables STATUS_REQUIRED_VARS 0; then
        print_error "❌ Missing required environment variables"
        exit 1
    fi

    # Check optional environment variables
    check_env_variables STATUS_OPTIONAL_VARS 1

    # Display status based on mode
    if [[ "$SHOW_FULL_STATUS" == "yes" ]]; then
        get_detailed_status
    else
        get_basic_status
    fi

    exit $?
}

# Execute the main function with all arguments
main "$@"
