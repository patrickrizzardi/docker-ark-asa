#!/bin/bash
RCON_CMDLINE=(rcon -a 127.0.0.1:${RCON_PORT} -p ${ARK_ADMIN_PASSWORD})
EOS_FILE=${MANAGER_DIR}/.eos.config

# Colors
blue_text='\033[0;36m'
bold_text='\033[1m'
red_text='\033[0;31m'
green_text='\033[0;32m'
color_reset='\033[0m'

get_and_check_pid() {
    # Check if ArkAscendedServer.exe is running, if it is return PID
    ark_pid=$(pgrep -fl "ArkAscendedServer.exe" | grep "GameThread" | cut -d' ' -f1)
    if [[ -n "$ark_pid" ]]; then
        echo $ark_pid
        return
    fi

    # Check if AsaApiLoader.exe is running, if it is return PID
    ark_pid=$(pgrep -fl "AsaApiLoader.exe" | grep "AsaApiLoader" | cut -d' ' -f1)
    if [[ -n "$ark_pid" ]]; then
        echo $ark_pid
        return
    fi

    # If no PID found, return 0
    echo "0"
}

full_status_setup() {
    # Check PDB is still available
    if [[ ! -f "${ARK_DIR}/ShooterGame/Binaries/Win64/ArkAscendedServer.pdb" ]]; then
        echo "${ARK_DIR}/ShooterGame/Binaries/Win64/ArkAscendedServer.pdb is needed to setup full status."
        return 1
    fi

    # Download pdb-sym2addr-rs and extract it to ${MANAGER_DIR}/pdb-sym2addr
    wget -q https://github.com/azixus/pdb-sym2addr-rs/releases/latest/download/pdb-sym2addr-x86_64-unknown-linux-musl.tar.gz -O ${MANAGER_DIR}/pdb-sym2addr-x86_64-unknown-linux-musl.tar.gz
    tar -xzf ${MANAGER_DIR}/pdb-sym2addr-x86_64-unknown-linux-musl.tar.gz -C ${MANAGER_DIR}
    rm ${MANAGER_DIR}/pdb-sym2addr-x86_64-unknown-linux-musl.tar.gz

    # Extract EOS login
    symbols=$(${MANAGER_DIR}/pdb-sym2addr ${ARK_DIR}/ShooterGame/Binaries/Win64/ArkAscendedServer.exe ${ARK_DIR}/ShooterGame/Binaries/Win64/ArkAscendedServer.pdb DedicatedServerClientSecret DedicatedServerClientId DeploymentId)

    client_id=$(echo "$symbols" | grep -o 'DedicatedServerClientId.*' | cut -d, -f2)
    client_secret=$(echo "$symbols" | grep -o 'DedicatedServerClientSecret.*' | cut -d, -f2)
    deployment_id=$(echo "$symbols" | grep -o 'DeploymentId.*' | cut -d, -f2)

    # Save base64 login and deployment id to file
    creds=$(echo -n "$client_id:$client_secret" | base64 -w0)
    echo "${creds},${deployment_id}" >"$EOS_FILE"

    return 0
}

full_status_first_run() {
    read -p "To display the full status, the EOS API credentials will have to be extracted from the server binary files and pdb-sym2addr-rs (azixus/pdb-sym2addr-rs) will be downloaded. Do you want to proceed [y/n]?: " -n 1 -r
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        return 1
    fi

    full_status_setup
    return $?
}

full_status_display() {
    creds=$(cat "$EOS_FILE" | cut -d, -f1)
    id=$(cat "$EOS_FILE" | cut -d, -f2)

    # Recover current ip
    ip=$(curl -s https://ifconfig.me/ip)

    # Recover and extract oauth token
    oauth=$(curl -s -H 'Content-Type: application/x-www-form-urlencoded' -H 'Accept: application/json' -H "Authorization: Basic ${creds}" -X POST https://api.epicgames.dev/auth/v1/oauth/token -d "grant_type=client_credentials&deployment_id=${id}")
    token=$(echo "$oauth" | jq -r '.access_token')

    # Send query to get server(s) registered under public ip
    res=$(curl -s -X "POST" "https://api.epicgames.dev/matchmaking/v1/${id}/filter" \
        -H "Content-Type:application/json" \
        -H "Accept:application/json" \
        -H "Authorization: Bearer $token" \
        -d "{\"criteria\": [{\"key\": \"attributes.ADDRESS_s\", \"op\": \"EQUAL\", \"value\": \"${ip}\"}]}")

    # Check there was no error
    if [[ "$res" == *"errorCode"* ]]; then
        echo "Failed to query EOS... Please run command again."
        full_status_setup
        return
    fi

    # Extract correct server based on server port
    serv=$(echo "$res" | jq -r ".sessions[] | select( .attributes.ADDRESSBOUND_s | contains(\":${SERVER_PORT}\"))")

    if [[ -z "$serv" ]]; then
        echo "Server is down"
        return
    fi

    # Extract variables
    mapfile -t vars < <(echo "$serv" | jq -r '
            .totalPlayers,
            .settings.maxPublicPlayers,
            .attributes.CUSTOMSERVERNAME_s,
            .attributes.DAYTIME_s,
            .attributes.SERVERUSESBATTLEYE_b,
            .attributes.ADDRESS_s,
            .attributes.ADDRESSBOUND_s,
            .attributes.MAPNAME_s,
            .attributes.BUILDID_s,
            .attributes.MINORBUILDID_s,
            .attributes.SESSIONISPVE_l,
            .attributes.ENABLEDMODS_s
        ')

    curr_players=${vars[0]}
    max_players=${vars[1]}
    serv_name=${vars[2]}
    day=${vars[3]}
    battleye=${vars[4]}
    ip=${vars[5]}
    bind=${vars[6]}
    map=${vars[7]}
    major=${vars[8]}
    minor=${vars[9]}
    pve=${vars[10]}
    mods=${vars[11]}
    bind_ip=${bind%:*}
    bind_port=${bind#*:}

    if [[ "${mods}" == "null" ]]; then
        mods="-"
    fi

    echo -e "Server Name:    ${serv_name}"
    echo -e "Map:            ${map}"
    echo -e "Day:            ${day}"
    echo -e "Players:        ${curr_players} / ${max_players}"
    echo -e "Mods:           ${mods}"
    echo -e "Server Version: ${major}.${minor}"
    echo -e "Server Address: ${ip}:${bind_port}"
    echo "Server is up"
}

status() {
    enable_full_status=false
    # Execute initial EOS setup, true if no error
    if [[ "$1" == "--full" ]]; then
        # If EOS file exists, no need to run initial setup
        if [[ -f "$EOS_FILE" ]]; then
            enable_full_status=true
        else
            full_status_first_run
            res=$?
            if [[ $res -eq 0 ]]; then
                enable_full_status=true
            fi
        fi
    fi

    # Get server PID
    ark_pid=$(get_and_check_pid)
    if [[ "$ark_pid" == 0 ]]; then
        echo "Server PID not found (server offline?)"
        return
    fi
    echo -e "Server PID:     ${ark_pid}"

    ark_port=$(ss -tupln | grep "GameThread" | grep -oP '(?<=:)\d+')
    if [[ -z "$ark_port" ]]; then
        echo -e "Server Port:    Not Listening"
        return
    fi

    echo -e "Server Port:    ${ark_port}"

    # Check initial status with rcon command
    out=$(${RCON_CMDLINE[@]} ListPlayers 2>/dev/null)
    res=$?
    if [[ $res == 0 ]]; then
        # Once rcon is up, query EOS if requested
        if [[ "$enable_full_status" == true ]]; then
            full_status_display
        else
            num_players=0
            if [[ "$out" != "No Players"* ]]; then
                num_players=$(echo "$out" | wc -l)
            fi
            echo -e "Players:        ${num_players} / ?"
            echo "Server is up"
        fi
    else
        echo "Server is down"
    fi
}

start() {
    server_command=$1

    # Check server not already running
    ark_pid=$(get_and_check_pid)
    if [[ "$ark_pid" != 0 ]]; then
        echo -e "${red_text}Server is already running${color_reset}"
        return
    fi

    # Promt user to select which server they want to start using the selector script
    # if the server is not provided as an argument
    if [[ -z "$server_command" ]]; then
        options=("none" "start" "startApi")
        instructions="Select which server you want to start:"
        source ${UTILS_DIR}/selector.sh
        Menu "${instructions}" "${options[@]}"
        server_command=${options[$?]}
    fi

    if ls ${ARK_DIR}/ShooterGame/Saved/Logs/Archive/*.log 1>/dev/null 2>&1; then
        echo -e "${blue_text}Archiving old logs${color_reset}"
        mv ${ARK_DIR}/ShooterGame/Saved/Logs/*.log ${ARK_DIR}/ShooterGame/Saved/Logs/Archive/
    fi

    if ls ${ARK_DIR}/ShooterGame/Binaries/Win64/logs/Archive/*.log 1>/dev/null 2>&1; then
        echo -e "${blue_text}Archiving old logs${color_reset}"
        mv ${ARK_DIR}/ShooterGame/Binaries/Win64/logs/*.log ${ARK_DIR}/ShooterGame/Binaries/Win64/logs/Archive/
    fi

    if [[ "$server_command" == "start" ]]; then

        echo -e "${green_text}Starting server on port ${SERVER_PORT}${color_reset}"
        echo "-------- STARTING SERVER --------" >>"$LOG_FILE"

        # Start server in the background + nohup and save PID
        nohup ${MANAGER_DIR}/manager_server_start.sh >/dev/null 2>&1 &
        sleep 3
        echo -e "${green_text}Server should be up in a few minutes${color_reset}"
    fi

    if [[ "$server_command" == "startApi" ]]; then
        echo -e "${green_text}Starting API server on port ${SERVER_PORT}${color_reset}"
        echo "-------- STARTING API SERVER --------" >>"$LOG_FILE"

        nohup ${MANAGER_DIR}/manager_server_api_start.sh >/dev/null 2>&1 &
        sleep 3
        echo -e "${green_text}API server should be up in a few minutes${color_reset}"
    fi

    if [[ "$server_command" == "none" ]]; then
        echo -e "${red_text}No server selected${color_reset}"
    fi
}

stop() {
    # Get server pid
    ark_pid=$(get_and_check_pid)
    if [[ "$ark_pid" == 0 ]]; then
        echo -e "${red_text}Server PID not found (server offline?)${color_reset}"
        return
    fi

    # Check number of players
    out=$(${RCON_CMDLINE[@]} listplayers 2>/dev/null)
    res=$?
    if ([[ $res == 0 ]] && [[ "$out" != "No Players"* ]]); then
        num_players=$(echo "$out" | wc -l)
        if [[ "$num_players" -gt 0 ]]; then
            echo -e "${red_text}Server is still running with $num_players players${color_reset}"
            echo "Please disconnect all players before stopping the server."
            return
        fi
    else
        gracefulStop
    fi

    echo "-------- SERVER STOPPED --------" >>"$LOG_FILE"
}

gracefulStop() {
    ark_pid=$(get_and_check_pid)
    echo -e "${green_text}Server is running, stopping server gracefully...${color_reset}"
    echo "-------- STOPPING SERVER --------" >>"$LOG_FILE"

    saveworld

    out=$(${RCON_CMDLINE[@]} DoExit 2>/dev/null)
    res=$?
    if [[ $res == 0 && "$out" == "Exiting..." ]]; then
        echo -e "${green_text}success!${color_reset}"
        echo -e "${green_text}Waiting ${blue_text}${SERVER_SHUTDOWN_TIMEOUT}s ${green_text}for the server to stop...${color_reset}"
        timeout $SERVER_SHUTDOWN_TIMEOUT tail --pid=$ark_pid -f /dev/null
        res=$?

        # Timeout occurred, force shutdown
        if [[ "$res" == 124 ]]; then
            echo "Server still running after $SERVER_SHUTDOWN_TIMEOUT seconds"
            forceShutdown
        fi
    fi
}

forceShutdown() {
    ark_pid=$(get_and_check_pid)
    echo -e "${red_text}Forcing server to stop...${color_reset}"

    kill $ark_pid
}

restart() {
    # Check if ArkAscendedServer.exe is running, if it is we need to run the start command
    ark_pid=$(pgrep -fl "ArkAscendedServer.exe" | grep "GameThread" | cut -d' ' -f1)
    if [[ -n "$ark_pid" ]]; then
        echo -e "${green_text}Restarting server on port ${SERVER_PORT}${color_reset}"
        stop "$1"
        start "start"
    fi

    # Check if AsaApiLoader.exe is running, if it is we need to run the startApi command
    ark_pid=$(pgrep -fl "AsaApiLoader.exe" | grep "AsaApiLoader" | cut -d' ' -f1)
    if [[ -n "$ark_pid" ]]; then
        echo "Restarting ASA API on port ${SERVER_PORT}"
        stop "$1"
        start "startApi"
    fi

    # If no server is running, we need to start the server we can just run the start command
    start

}

saveworld() {
    # Get server pid
    ark_pid=$(get_and_check_pid)
    if [[ "$ark_pid" == 0 ]]; then
        echo "Server PID not found (server offline?)"
        return
    fi

    echo "Saving world..."
    out=$(${RCON_CMDLINE[@]} SaveWorld 2>/dev/null)
    res=$?
    if [[ $res == 0 && "$out" == "World Saved" ]]; then
        echo "Save Success!"
    else
        echo "Save Failed."
    fi
}

custom_rcon() {
    # Get server pid
    ark_pid=$(get_and_check_pid)
    if [[ "$ark_pid" == 0 ]]; then
        echo "Server PID not found (server offline?)"
        return
    fi

    out=$(${RCON_CMDLINE[@]} "${@}" 2>/dev/null)
    echo "$out"
}

update() {
    echo "Updating ARK Ascended Server"

    # Promt user to select which server they want to start using the selector script
    options=("none" "start" "startApi")
    instructions="Select which server you want to start after the update:"
    source ${UTILS_DIR}/selector.sh
    Menu "${instructions}" "${options[@]}"
    server_command=${options[$?]}

    # Check server not already running
    ark_pid=$(get_and_check_pid)
    if [[ "$ark_pid" != 0 ]]; then
        echo "Server is running, saving world and stopping server"
        stop --saveworld

    fi

    ${STEAM_DIR}/steamcmd.sh +force_install_dir ${ARK_DIR} +login anonymous +app_update ${ASA_APPID} +quit
    # Remove unnecessary files (saves 6.4GB.., that will be re-downloaded next update)
    if [[ -n "${REDUCE_IMAGE_SIZE}" ]]; then
        rm -rf ${ARK_DIR}/ShooterGame/Binaries/Win64/ArkAscendedServer.pdb
        rm -rf ${ARK_DIR}/ShooterGame/Content/Movies/
    fi

    echo "Update completed"

    # Check if server_command is start, then we need to run the start command
    if [[ "$server_command" == "start" ]]; then
        echo "Restarting server on port ${SERVER_PORT}"
        start "start"
    fi

    # Check if server_command is startApi, then we need to run the startApi command
    if [[ "$server_command" == "startApi" ]]; then
        echo "Restarting ASA API on port ${SERVER_PORT}"
        start "startApi"
    fi
}

backup() {
    echo "Creating backup. Backups are saved in your ./ark_backup volume."
    # saving before creating the backup
    saveworld
    # sleep is nessecary because the server seems to write save files after the saveworld function ends and thus tar runs into errors.
    sleep 5
    # Use backup script
    ${MANAGER_DIR}/manager_backup.sh

    res=$?
    if [[ $res == 0 ]]; then
        echo "BACKUP CREATED" >>"$LOG_FILE"
    else
        echo "creating backup failed"
    fi
}

restoreBackup() {
    backup_count=$(ls /var/backups/asa-server/ | wc -l)
    if [[ $backup_count > 0 ]]; then
        echo "Stopping the server."
        stop
        sleep 3
        # restoring the backup
        ${MANAGER_DIR}/manager_restore_backup.sh

        sleep 2
        start
    else
        echo "You haven't created any backups yet."
    fi
}

# Main function
main() {
    action="$1"
    option="$2"

    case "$action" in
    "status")
        status "$option"
        ;;
    "start")
        start
        ;;
    "stop")
        stop "$option"
        ;;
    "restart")
        restart "$option"
        ;;
    "saveworld")
        saveworld
        ;;
    "rcon")
        custom_rcon "${@:2:99}"
        ;;
    "update")
        update
        ;;
    "backup")
        backup
        ;;
    "restore")
        restoreBackup
        ;;
    *)
        echo "Invalid action. Supported actions: status, start, stop, restart, saveworld, rcon, update, backup, restore."
        exit 1
        ;;
    esac
}

# Check if at least one argument is provided
if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <action> [--saveworld]"
    exit 1
fi

main "$@"
