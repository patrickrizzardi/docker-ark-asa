#!/bin/bash

#exit on error
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Plugin definitions
declare -A ark_shop=(
    ["latest_release"]="1.06"
    ["url"]="https://cdn.redact.digital/ark/ArkShop"
    ["additional_files"]="config.json Commented.json"
)

declare -A turret_manager=(
    ["latest_release"]="1.08"
    ["url"]="http://cdn.redact.digital/ark/TurretManagerFREE"
    ["additional_files"]="config.json"
)

declare -A advanced_messages=(
    ["latest_release"]="1.2"
    ["url"]="http://cdn.redact.digital/ark/AdvancedMessagesAscended"
    ["additional_files"]="config.json config_help.json"
)

# Store all plugins in an array
declare -A plugins=(server_api ark_shop turret_manager advanced_messages)

# Function to download and install plugins
install_plugin() {
    local name="$1"
    local latest_release="$2"
    local url="$3"
    local destination="$4"
    local additional_files=("${!5}") # Use an array for additional files

    echo -e "Installing latest ${name} ${GREEN}${latest_release}${NC}"
    wget "${url}/${name}_${latest_release}.zip" -O "/tmp/${name}.zip"
    unzip "/tmp/${name}.zip" -d "/tmp/${name}"

    mkdir -p "${destination}"

    # Move default files
    mv -f "/tmp/${name}/${name}.dll" "${destination}/${name}.dll"
    mv -f "/tmp/${name}/${name}.pdb" "${destination}/${name}.pdb"
    mv -f "/tmp/${name}/PluginInfo.json" "${destination}/PluginInfo.json"

    # Move additional files if specified
    for file in "${additional_files[@]}"; do
        mv -f "/tmp/${name}/${file}" "${destination}/${file}"
    done

    # Clean up
    rm -rf "/tmp/${name}.zip" "/tmp/${name}"

    # Update version record
    echo "${latest_release}" >"${destination}/last_${name}_release.txt"
}

function installServerAPI {
    # https://gameservershub.com/forums/resources/ark-survival-ascended-serverapi-crossplay-supported.683/
    LATEST_RELEASE=$1

    echo -e "Installing latest API ${GREEN}${LATEST_RELEASE}${NC}"
    wget https://cdn.redact.digital/ark/AsaApi_${LATEST_RELEASE}.zip -O /tmp/AsaApi.zip

    mkdir -p /tmp/AsaApi
    unzip /tmp/AsaApi.zip -d /tmp/AsaApi

    mkdir -p "${ARK_DIR}/ShooterGame/Binaries/Win64/ArkApi/Plugins/Permissions"

    mv -f /tmp/AsaApi/AsaApiLoader.exe "${ARK_DIR}/ShooterGame/Binaries/Win64/AsaApiLoader.exe"
    mv -f /tmp/AsaApi/AsaApiLoader.pdb "${ARK_DIR}/ShooterGame/Binaries/Win64/AsaApiLoader.pdb"
    mv -f /tmp/AsaApi/msdia140.dll "${ARK_DIR}/ShooterGame/Binaries/Win64/msdia140.dll"
    mv -f /tmp/AsaApi/ArkApi/pdbignores.txt "${ARK_DIR}/ShooterGame/Binaries/Win64/ArkApi/pdbignores.txt"
    mv -f /tmp/AsaApi/ArkApi/Plugins/Permissions/Permissions.dll "${ARK_DIR}/ShooterGame/Binaries/Win64/ArkApi/Plugins/Permissions/Permissions.dll"
    mv -f /tmp/AsaApi/ArkApi/Plugins/Permissions/Permissions.pdb "${ARK_DIR}/ShooterGame/Binaries/Win64/ArkApi/Plugins/Permissions/Permissions.pdb"

    mv -f /tmp/AsaApi/ArkApi/AsaApi.dll "${ARK_DIR}/ShooterGame/Binaries/Win64/ArkApi/AsaApi.dll"
    mv -f /tmp/AsaApi/ArkApi/AsaApi.pdb "${ARK_DIR}/ShooterGame/Binaries/Win64/ArkApi/AsaApi.pdb"
    mv -f /tmp/AsaApi/ArkApi/Plugins/Permissions/PluginInfo.json "${ARK_DIR}/ShooterGame/Binaries/Win64/ArkApi/Plugins/Permissions/PluginInfo.json"
    # TODO - Add some checks to see if the api already has config files in it or not. If it doesn't then we need to copy them over from the zip file

    rm -rf /tmp/AsaApiLoader.zip
    rm -rf /tmp/AsaApi

    if [[ ! -f "${ARK_DIR}/ShooterGame/Binaries/last_server_api_release.txt" ]]; then
        rm -rf "${ARK_DIR}/ShooterGame/Binaries/last_server_api_release.txt"
        echo "${LATEST_RELEASE}" >"${ARK_DIR}/ShooterGame/Binaries/last_server_api_release.txt"
    else
        echo "${LATEST_RELEASE}" >"${ARK_DIR}/ShooterGame/Binaries/last_server_api_release.txt"
    fi
}

# function installArkShopPlugin {
#     # https://gameservershub.com/forums/resources/ark-survival-ascended-arkshop-crossplay-supported.714/
#     LATEST_RELEASE=$1

#     echo -e "Installing latest ArkShop ${GREEN}${LATEST_RELEASE}${NC}"
#     # Login game server hub atm requires a subscription to download the plugin,
#     # so for the time being I'm going to download it manually and copy it to an s3 bucket
#     wget "https://cdn.redact.digital/ark/ArkShop_${LATEST_RELEASE}.zip" -O /tmp/ArkShop.zip
#     unzip /tmp/ArkShop.zip -d /tmp/ArkShop

#     mkdir -p "${ARK_DIR}/ShooterGame/Binaries/Win64/ArkApi/Plugins/ArkShop"

#     mv -f /tmp/ArkShop/ArkShop/ArkShop.dll "${ARK_DIR}/ShooterGame/Binaries/Win64/ArkApi/Plugins/ArkShop/ArkShop.dll"
#     mv -f /tmp/ArkShop/ArkShop/ArkShop.pdb "${ARK_DIR}/ShooterGame/Binaries/Win64/ArkApi/Plugins/ArkShop/ArkShop.pdb"
#     mv -f /tmp/ArkShop/ArkShop/PluginInfo.json "${ARK_DIR}/ShooterGame/Binaries/Win64/ArkApi/Plugins/ArkShop/PluginInfo.json"
#     mv -f /tmp/ArkShop/ArkShop/Commented.json "${ARK_DIR}/ShooterGame/Binaries/Win64/ArkApi/Plugins/ArkShop/Commented.json"

#     if [[ ! -f "${ARK_DIR}/ShooterGame/Binaries/Win64/ArkApi/Plugins/ArkShop/config.json" ]]; then
#         mv -f /tmp/ArkShop/ArkShop/config.json "${ARK_DIR}/ShooterGame/Binaries/Win64/ArkApi/Plugins/ArkShop/config.json"
#     fi

#     rm -rf /tmp/ArkShop.zip
#     rm -rf /tmp/ArkShop

#     if [[ ! -f "${ARK_DIR}/ShooterGame/Binaries/last_arkshop_release.txt" ]]; then
#         rm -rf "${ARK_DIR}/ShooterGame/Binaries/last_arkshop_release.txt"
#         echo "${LATEST_RELEASE}" >"${ARK_DIR}/ShooterGame/Binaries/last_arkshop_release.txt"
#     else
#         echo "${LATEST_RELEASE}" >"${ARK_DIR}/ShooterGame/Binaries/last_arkshop_release.txt"
#     fi
# }

# function installTurretManagerPlugin {
#     # https://gameservershub.com/forums/resources/turret-manager-free.749/
#     LATEST_RELEASE=$1

#     echo -e "Installing latest TurretManager ${GREEN}${LATEST_RELEASE}${NC}"
#     # Login game server hub atm requires a subscription to download the plugin,
#     # so for the time being I'm going to download it manually and copy it to an s3 bucket
#     wget "http://cdn.redact.digital/ark/TurretManagerFREE${LATEST_RELEASE}.zip" -O /tmp/TurretManager.zip
#     unzip /tmp/TurretManager.zip -d /tmp/TurretManager

#     mkdir -p "${ARK_DIR}/ShooterGame/Binaries/Win64/ArkApi/Plugins/TurretManagerFree"

#     mv -f /tmp/TurretManager/TurretManagerFree/TurretManagerFree.dll "${ARK_DIR}/ShooterGame/Binaries/Win64/ArkApi/Plugins/TurretManagerFree/TurretManagerFree.dll"
#     mv -f /tmp/TurretManager/TurretManagerFree/TurretManagerFree.pdb "${ARK_DIR}/ShooterGame/Binaries/Win64/ArkApi/Plugins/TurretManagerFree/TurretManagerFree.pdb"
#     mv -f /tmp/TurretManager/TurretManagerFree/PluginInfo.json "${ARK_DIR}/ShooterGame/Binaries/Win64/ArkApi/Plugins/TurretManagerFree/PluginInfo.json"

#     if [[ ! -f "${ARK_DIR}/ShooterGame/Binaries/Win64/ArkApi/Plugins/TurretManagerFree/config.json" ]]; then
#         mv -f /tmp/TurretManager/TurretManagerFree/config.json "${ARK_DIR}/ShooterGame/Binaries/Win64/ArkApi/Plugins/TurretManagerFree/config.json"
#     fi

#     rm -rf /tmp/TurretManager.zip
#     rm -rf /tmp/TurretManager

#     if [[ ! -f "${ARK_DIR}/ShooterGame/Binaries/last_turret_manager_release.txt" ]]; then
#         rm -rf "${ARK_DIR}/ShooterGame/Binaries/last_turret_manager_release.txt"
#         echo "${LATEST_RELEASE}" >"${ARK_DIR}/ShooterGame/Binaries/last_turret_manager_release.txt"
#     else
#         echo "${LATEST_RELEASE}" >"${ARK_DIR}/ShooterGame/Binaries/last_turret_manager_release.txt"
#     fi
# }

# function installAdvancedMessagesPlugin {
#     # https://gameservershub.com/forums/resources/advanced-messages-ascended.739/
#     LATEST_RELEASE=$1

#     echo -e "Installing latest AdvancedMessages ${GREEN}${LATEST_RELEASE}${NC}"
#     # Login game server hub atm requires a subscription to download the plugin,
#     # so for the time being I'm going to download it manually and copy it to an s3 bucket
#     wget "http://cdn.redact.digital/ark/AdvancedMessagesAscended_${LATEST_RELEASE}.zip" -O "/tmp/AdvancedMessagesAscended.zip"

#     # Turn off error checking for this command becaues it keeps giving the "appears to use backslashes as path separators" error
#     # which doesn't seem to be affecting the actual unzipping of the file
#     set +e
#     unzip "/tmp/AdvancedMessagesAscended.zip" -d "/tmp/AdvancedMessagesAscended"
#     set -e

#     mkdir -p "${ARK_DIR}/ShooterGame/Binaries/Win64/ArkApi/Plugins/AdvancedMessagesAscended"

#     mv -f "/tmp/AdvancedMessagesAscended/AdvancedMessagesAscended/AdvancedMessagesAscended.dll" "${ARK_DIR}/ShooterGame/Binaries/Win64/ArkApi/Plugins/AdvancedMessagesAscended/AdvancedMessagesAscended.dll"
#     mv -f "/tmp/AdvancedMessagesAscended/AdvancedMessagesAscended/AdvancedMessagesAscended.pdb" "${ARK_DIR}/ShooterGame/Binaries/Win64/ArkApi/Plugins/AdvancedMessagesAscended/AdvancedMessagesAscended.pdb"
#     mv -f "/tmp/AdvancedMessagesAscended/AdvancedMessagesAscended/PluginInfo.json" "${ARK_DIR}/ShooterGame/Binaries/Win64/ArkApi/Plugins/AdvancedMessagesAscended/PluginInfo.json"

#     mv -f "/tmp/AdvancedMessagesAscended/AdvancedMessagesAscended/config_help.json" "${ARK_DIR}/ShooterGame/Binaries/Win64/ArkApi/Plugins/AdvancedMessagesAscended/config_help.json"

#     if [[ ! -f "${ARK_DIR}/ShooterGame/Binaries/Win64/ArkApi/Plugins/AdvancedMessagesAscended/config.json" ]]; then
#         mv -f "/tmp/AdvancedMessagesAscended/AdvancedMessagesAscended/config.json" "${ARK_DIR}/ShooterGame/Binaries/Win64/ArkApi/Plugins/AdvancedMessagesAscended/config.json"
#     fi

#     rm -rf "/tmp/AdvancedMessagesAscended.zip"
#     rm -rf "/tmp/AdvancedMessagesAscended"

#     if [[ ! -f "${ARK_DIR}/ShooterGame/Binaries/last_advanced_messages_release.txt" ]]; then
#         rm -rf "${ARK_DIR}/ShooterGame/Binaries/last_advanced_messages_release.txt"
#         echo "${LATEST_RELEASE}" >"${ARK_DIR}/ShooterGame/Binaries/last_advanced_messages_release.txt"
#     else
#         echo "${LATEST_RELEASE}" >"${ARK_DIR}/ShooterGame/Binaries/last_advanced_messages_release.txt"
#     fi
# }

# If command is provided, run it
# The reason this is here is because comonly the next step fails, so I would like to be
# able to run commands and such to troubleshoot before this command happens IE docker run -it bash
# if [ $# -gt 0 ]; then
#     exec "$@"
# fi

# Install or update ASA server + verify installation
# ${STEAM_DIR}/steamcmd.sh +force_install_dir ${ARK_DIR} +login anonymous +app_update ${ASA_APPID} +quit

# # Find latest release of Server API
# ARK_SERVER_API_LATEST_RELEASE=1.17

# # Server API
# if [[ -f "${ARK_DIR}/ShooterGame/Binaries/Win64/AsaApiLoader.exe" ]]; then
#     LAST_RELEASE=""
#     if [[ -f "${ARK_DIR}/ShooterGame/Binaries/last_server_api_release.txt" ]]; then
#         LAST_RELEASE=$(cat "${ARK_DIR}/ShooterGame/Binaries/last_server_api_release.txt")
#     fi

#     if [[ "${LAST_RELEASE}" == "${ARK_SERVER_API_LATEST_RELEASE}" ]]; then
#         echo -e "Server API is up to date: ${GREEN}${ARK_SERVER_API_LATEST_RELEASE}${NC}"
#     else
#         installServerAPI "${ARK_SERVER_API_LATEST_RELEASE}"
#     fi
# else
#     installServerAPI "${ARK_SERVER_API_LATEST_RELEASE}"
# fi

# Install plugins
# for plugin in "${plugins[@]}"; do
#     latest_release="${!plugin[latest_release]}"
#     url="${!plugin[url]}"

#     # Convert space-separated string into an array
#     IFS=' ' read -r -a additional_files <<<"${!plugin[additional_files]}"

#     destination="${ARK_DIR}/ShooterGame/Binaries/Win64/ArkApi/Plugins/${plugin}"

#     # Check for last installed version
#     last_release_file="${destination}/last_${plugin}_release.txt"
#     LAST_RELEASE=""
#     if [[ -f "${last_release_file}" ]]; then
#         LAST_RELEASE=$(cat "${last_release_file}")
#     fi

#     # Compare last installed version with latest release version
#     if [[ "${LAST_RELEASE}" == "${latest_release}" ]]; then
#         echo -e "${plugin} is up to date: ${GREEN}${latest_release}${NC}"
#     else
#         install_plugin "${plugin}" "${latest_release}" "${url}" "${destination}" additional_files[@]
#     fi
# done

# Start server through manager
# manager startApi &

# Register SIGTERM handler to stop server gracefully
# trap "manager stop --saveworld" SIGTERM
# echo -e "${GREEN}------------------------ Server is ready${NC}. Use 'manager' command to manage the server. ${GREEN}------------------------${NC}"

if [ $# -gt 0 ]; then
    exec "$@"
fi

# Function to tail multiple log files
# tail_logs() {
#     while true; do # Start an infinite loop to continuously monitor the log files
#         # Check if the main ShooterGame.log file exists
#         if [[ -f "${LOG_FILE}" ]]; then
#             # Tail the ShooterGame.log file and run it in the background
#             tail -F "${LOG_FILE}" &
#         fi

#         for log_pattern in "${GAME_LOG_FILE}" "${API_LOG_FILE}" "${WINE_LOG_FILE}"; do
#             # Use ls -t to sort files by modification time and head -n 1 to get the most recent one
#             latest_log=$(ls -t "${log_pattern}" 2>/dev/null | head -n 1)
#             # Check if a latest_log was found
#             if [[ -n "${latest_log}" ]]; then
#                 # Tail the latest log file and run it in the background
#                 tail -F "${latest_log}" &
#             fi
#         done

#         # Wait for all background tail processes to finish
#         wait

#         # Sleep for a short period (5 seconds) before checking for log files again
#         # This reduces CPU usage and avoids constant checking
#         sleep 5
#     done
# }

# # Start the log tailing in the background
# tail_logs

# run index.ts
export PATH="/home/${USER}/.bun/bin:$PATH"
bun run /opt/manager/index.ts

# The script will never reach this point, as the while loop above will run indefinitely.
# However, the exit command is included for completeness and to indicate that the script has finished executing.
exit 0
