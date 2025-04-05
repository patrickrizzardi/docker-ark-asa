#!/bin/bash

# Utility functions for server monitoring

# Check if the monitor process is active
is_monitor_active() {
    # Check if monitor PID file exists
    if file_exists "${ARK_DIR}/monitor.pid"; then
        local monitor_pid=$(cat "${ARK_DIR}/monitor.pid")

        # Check if the process exists
        if ps -p "$monitor_pid" >/dev/null; then
            # Process exists, check if it's the monitor
            if ps -p "$monitor_pid" -o cmd= | grep -q "monitor.sh"; then
                return 0 # Monitor is active
            fi
        fi

        # PID file exists but process is dead or not monitor, clean up
        rm -f "${ARK_DIR}/monitor.pid" 2>/dev/null || true
    fi

    # Check for any monitor.sh process
    if pgrep -f "monitor.sh" >/dev/null; then
        return 0 # Monitor is active
    fi

    return 1 # No monitor found
}

# Start the monitor if it's not already running
start_monitor() {
    if ! is_monitor_active; then
        if file_exists "${MANAGER_DIR}/monitor.sh"; then
            echo "Starting ARK server monitor..."
            mkdir -p "${SAVED_DIR}/Logs" 2>/dev/null || true
            nohup "${MANAGER_DIR}/monitor.sh" >"${SAVED_DIR}/Logs/monitor.log" 2>&1 &
            echo $! >"${ARK_DIR}/monitor.pid"
            return 0
        else
            echo "Monitor script not found at ${MANAGER_DIR}/monitor.sh"
            return 1
        fi
    else
        echo "Monitor is already running"
        return 0
    fi
}

# Stop the monitor
stop_monitor() {
    if is_monitor_active; then
        if file_exists "${ARK_DIR}/monitor.pid"; then
            local monitor_pid=$(cat "${ARK_DIR}/monitor.pid")
            echo "Stopping monitor (PID: $monitor_pid)..."
            kill "$monitor_pid" 2>/dev/null || true
            rm -f "${ARK_DIR}/monitor.pid" 2>/dev/null || true
        else
            echo "Stopping all monitor processes..."
            pkill -f "monitor.sh" 2>/dev/null || true
        fi
        return 0
    else
        echo "No active monitor found"
        return 1
    fi
}

# Restart the monitor
restart_monitor() {
    stop_monitor
    sleep 2
    start_monitor
    return $?
}

# Check if a restart is in progress
is_restart_in_progress() {
    if file_exists "${ARK_DIR}/restart.flag"; then
        return 0 # Restart in progress
    fi
    return 1 # No restart in progress
}

# Check if the server is updating
is_server_updating() {
    if file_exists "${ARK_DIR}/updating.flag"; then
        return 0 # Update in progress
    fi
    return 1 # No update in progress
}

# Check if a server start is in progress
is_server_starting() {
    if file_exists "${ARK_DIR}/server_starting.flag"; then
        return 0 # Server start in progress
    fi
    return 1 # No server start in progress
}

# Check if the server should not be automatically restarted
is_restart_prevented() {
    if file_exists "${ARK_DIR}/stop.flag"; then
        return 0 # Restart prevented
    fi
    return 1 # Restart allowed
}

# Check if the server is in a stable state (not starting, updating, or restarting)
is_server_stable() {
    if is_server_starting || is_server_updating || is_restart_in_progress; then
        return 1 # Server is not stable
    fi
    return 0 # Server is stable
}

# Create a flag file with timeout
create_timeout_flag() {
    local flag_file="$1"
    local timeout_seconds="${2:-3600}" # Default 1 hour

    # Create the flag file
    touch "$flag_file"

    # Schedule flag file removal after timeout
    (
        sleep "$timeout_seconds"
        rm -f "$flag_file" 2>/dev/null || true
    ) &

    return 0
}

# Remove a flag file if it exists
remove_flag() {
    local flag_file="$1"

    if file_exists "$flag_file"; then
        rm -f "$flag_file" 2>/dev/null || true
        return 0
    fi

    return 1 # Flag file didn't exist
}
