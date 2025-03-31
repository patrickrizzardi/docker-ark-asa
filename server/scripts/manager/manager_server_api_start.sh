#!/bin/bash
# This file is called by manager.sh to start a new instance of ASA

# Server main options
cmd="${SERVER_MAP}?listen?SessionName=\"${SESSION_NAME}\"?Port=${SERVER_PORT}"
if [ -n "${MAX_PLAYERS}" ]; then
    cmd="${cmd}?MaxPlayers=${MAX_PLAYERS}"
fi

if [ -n "${SERVER_PASSWORD}" ]; then
    cmd="${cmd}?ServerPassword=${SERVER_PASSWORD}"
fi

if [ -n "${ARK_ADMIN_PASSWORD}" ]; then
    cmd="${cmd}?ServerAdminPassword=\"${ARK_ADMIN_PASSWORD}\""
fi

if [ -n "${RCON_PORT}" ]; then
    cmd="${cmd}?RCONEnabled=True?RCONPort=${RCON_PORT}"
fi

if [ -n ${QUERY_PORT} ]; then
    cmd="${cmd}?QueryPort=${QUERY_PORT}"
fi

cmd="${cmd}${ARK_EXTRA_OPTS}"

# Server dash options
# Install mods
if [ -n "$MODS" ]; then
    ark_flags="${ark_flags} -mods=${MODS}"
fi

ark_flags="${ark_flags} -log -ServerRCONOutputTribeLogs -gameplaylogging -servergamelog -servergamelogincludetribelogs"

# If BATTLEYE is set to True, 1 or true start server with -UseBattlEye
if [ "${BATTLEYE}" = "True" ] || [ "${BATTLEYE}" = "1" ] || [ "${BATTLEYE}" = "true" ]; then
    ark_flags="${ark_flags} -UseBattlEye"
else
    ark_flags="${ark_flags} -NoBattlEye"
fi

if [ -n "${MAX_PLAYERS}" ]; then
    ark_flags="${ark_flags} -WinLiveMaxPlayers=${MAX_PLAYERS}"
fi

if [ -n "${CLUSTER}" ]; then
    ark_flags="${ark_flags} -clusterid=${CLUSTER}"
fi

if [ -n ${EVENT} ]; then
    ark_flags="${ark_flags} -ActiveEvent=${EVENT}"
else
    ark_flags="${ark_flags} -ActiveEvent=None"
fi

ark_flags="${ark_flags} ${ARK_EXTRA_DASH_OPTS}"

#fix for docker compose exec / docker exec parsing inconsistencies
STEAM_COMPAT_DATA_PATH=$(eval echo "$STEAM_COMPAT_DATA_PATH")

#starting server
wine "${ARK_DIR}/ShooterGame/Binaries/Win64/AsaApiLoader.exe" ${cmd} ${ark_flags} >${WINE_LOG_FILE} 2>&1
