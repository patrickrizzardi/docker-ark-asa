#!/bin/bash
# Temporary simplified processManager.sh to fix segmentation fault

# Directly source color definitions
source "$MANAGER_DIR/utils/colorPrinter.sh"

# Get the PID of a running server process
# Params:
#   $1 - process name to check (e.g. "ArkAscendedServer.exe")
# Returns:
#   PID if found, 0 if not found
get_server_pid() {
    local process_name="$1"
    local pid=$(ps aux | grep -v grep | grep -i "${process_name}" | awk '{print $2}' | head -1)
    echo "${pid:-0}"
}

# Check if a specific server process is running
# Params:
#   $1 - process name to check (e.g. "ArkAscendedServer.exe")
# Returns:
#   0 if process is running, 1 if not
is_process_running() {
    local process_name="$1"
    local pid=$(get_server_pid "$process_name")
    [[ "$pid" != "0" ]]
}

# Get the PID of the running ARK server (either API or game server)
# Returns:
#   PID if found, 0 if not found
get_ark_server_pid() {
    # Try ArkAscendedServer.exe first
    local pid=$(get_server_pid "ArkAscendedServer.exe")
    if [[ "$pid" != "0" ]]; then
        echo "$pid"
        return 0
    fi

    # Try AsaApiLoader.exe as fallback
    pid=$(get_server_pid "AsaApiLoader.exe")
    if [[ "$pid" != "0" ]]; then
        echo "$pid"
        return 0
    fi

    echo "0"
    return 1
}
