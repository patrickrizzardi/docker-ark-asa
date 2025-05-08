#!/bin/bash

# Utility functions for server monitoring

# Start the monitor if it's not already running
start_monitor() {
    if ! is_monitor_active; then
        if [[ -f "${MANAGER_DIR}/monitor.sh" ]]; then
            echo "Starting ARK server monitor..."
            mkdir -p "${SAVED_DIR}/Logs" 2>/dev/null || true
            nohup "${MANAGER_DIR}/monitor.sh" >"${SAVED_DIR}/Logs/monitor.log" 2>&1 &
            echo $! >"${ARK_SAVE_DIR}/monitor.pid"
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
        if [[ -f "${ARK_SAVE_DIR}/monitor.pid" ]]; then
            local monitor_pid=$(cat "${ARK_SAVE_DIR}/monitor.pid")
            echo "Stopping monitor (PID: $monitor_pid)..."
            kill "$monitor_pid" 2>/dev/null || true
            rm -f "${ARK_SAVE_DIR}/monitor.pid" 2>/dev/null || true
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
