#!/bin/bash
#
# ARK Server Monitor Manager Script
# Checks, starts, stops, and restarts the ARK server monitor process
#
# Usage: ./monitorManager.sh [command]
# Commands:
#   status       - Check if the monitor is running
#   start        - Start the monitor
#   stop         - Stop the monitor
#   restart      - Restart the monitor
#   logs         - Show monitor logs
#   follow       - Follow monitor logs in real-time
#
# =============================================================================

# Load environment variables and utilities
UTILS_PATH="$MANAGER_DIR/utils"
source "${UTILS_PATH}/common.sh"

# =============================================================================
# CONFIGURATION
# =============================================================================

# Required environment variables
declare -a MONITOR_REQUIRED_VARS=(
    "MANAGER_DIR" # Manager scripts directory
    "ARK_DIR"     # ARK installation directory
)

# Default log file location if not specified in environment
DEFAULT_MONITOR_LOG="${ARK_DIR}/logs/server_monitor.log"

# Script paths
MONITOR_SCRIPT="${MANAGER_DIR}/monitor.sh"
MONITOR_PID_FILE="${ARK_DIR}/monitor.pid"

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Get monitor process ID if running
get_monitor_pid() {
    if [[ -f "$MONITOR_PID_FILE" ]]; then
        local pid=$(cat "$MONITOR_PID_FILE")
        # Check if process exists
        if ps -p "$pid" >/dev/null 2>&1; then
            if [[ $(ps -p "$pid" -o comm= | grep -c "monitor.sh") -gt 0 ]]; then
                echo "$pid"
                return 0
            fi
        fi
        # PID file exists but process doesn't - clean up stale file
        rm -f "$MONITOR_PID_FILE"
    fi

    # Look for the monitor process
    local pids=$(pgrep -f "bash.*${MONITOR_SCRIPT}" 2>/dev/null || true)
    if [[ -n "$pids" ]]; then
        # Return the first matching PID
        echo "$pids" | head -n 1
        return 0
    fi

    echo "0"
    return 1
}

# Check monitor log status and age
check_log_status() {
    if [[ ! -f "$MONITOR_LOG" ]]; then
        print_warning "⚠️ Monitor log file not found at: $MONITOR_LOG"

        # Try to locate it using find
        echo "Searching for monitor log file..."
        local found_logs=$(find "${ARK_DIR}" -name "server_monitor.log" -type f 2>/dev/null)
        if [[ -n "$found_logs" ]]; then
            echo "Found possible logs:"
            echo "$found_logs"
            # Suggest updating the path
            echo ""
            print_info "You may need to set the MONITOR_LOG environment variable to one of these paths"
        fi
        return 1
    fi

    # Check log file timestamp
    local log_time=$(stat -c %y "$MONITOR_LOG" 2>/dev/null || date -r "$MONITOR_LOG" "+%Y-%m-%d %H:%M:%S" 2>/dev/null)
    echo "Last log update: $log_time"

    # Check if log has been updated recently
    local log_age=$(($(date +%s) - $(date -d "$log_time" +%s 2>/dev/null || date -j -f "%Y-%m-%d %H:%M:%S" "$log_time" +%s 2>/dev/null)))
    if [[ $log_age -gt 300 ]]; then # 5 minutes
        print_warning "⚠️ Monitor log hasn't been updated in $(($log_age / 60)) minutes"
    else
        print_info "Monitor log updated $(($log_age / 60)) minutes $(($log_age % 60)) seconds ago"
    fi

    return 0
}

# =============================================================================
# SERVER MANAGEMENT FUNCTIONS
# =============================================================================

# Check monitor status
check_monitor_status() {
    local pid=$(get_monitor_pid)

    if [[ "$pid" == "0" ]]; then
        print_warning "⚠️ Monitor is not running"
        return 1
    fi

    print_success "✅ Monitor is running (PID: $pid)"

    # Show process details
    echo ""
    echo "Monitor process details:"
    ps -f -p "$pid"

    # Show uptime
    local start_time=$(ps -o lstart= -p "$pid")
    echo ""
    echo "Monitor started at: $start_time"

    # Print monitor log location for debugging
    echo "Monitor log path: $MONITOR_LOG"

    # Check log file status
    check_log_status

    return 0
}

# Start the monitor
start_monitor() {
    # First check if it's already running
    local pid=$(get_monitor_pid)

    if [[ "$pid" != "0" ]]; then
        print_warning "⚠️ Monitor is already running (PID: $pid)"
        return 0
    fi

    print_header "🚀 Starting ARK Server Monitor"

    # Create log directory if it doesn't exist
    mkdir -p "$(dirname "$MONITOR_LOG")" 2>/dev/null || true

    # Start the monitor script in the background
    nohup "$MONITOR_SCRIPT" >"$MONITOR_LOG" 2>&1 &
    local new_pid=$!

    # Save PID to file
    echo "$new_pid" >"$MONITOR_PID_FILE"

    sleep 2

    # Verify monitor started successfully
    if ! ps -p "$new_pid" >/dev/null; then
        print_error "❌ Failed to start monitor"
        rm -f "$MONITOR_PID_FILE"
        return 1
    fi

    print_success "✅ Monitor started successfully (PID: $new_pid)"
    return 0
}

# Stop the monitor gracefully
stop_monitor_gracefully() {
    local pid=$1

    if kill -15 "$pid" 2>/dev/null; then
        print_info "Sent SIGTERM to monitor process ($pid)..."

        # Wait for process to exit
        local counter=0
        while ps -p "$pid" >/dev/null && [[ $counter -lt 10 ]]; do
            sleep 1
            counter=$((counter + 1))
        done

        return 0
    fi

    return 1
}

# Force stop the monitor
force_stop_monitor() {
    local pid=$1

    print_warning "⚠️ Monitor didn't terminate gracefully, forcing..."
    if kill -9 "$pid" 2>/dev/null; then
        sleep 1
        return 0
    fi

    return 1
}

# Stop the monitor
stop_monitor() {
    local pid=$(get_monitor_pid)

    if [[ "$pid" == "0" ]]; then
        print_warning "⚠️ Monitor is not running"
        return 0
    fi

    print_header "🛑 Stopping ARK Server Monitor"

    # Try graceful shutdown first
    stop_monitor_gracefully "$pid"

    # Check if process is still running
    if ps -p "$pid" >/dev/null; then
        # If still running, force stop
        if ! force_stop_monitor "$pid"; then
            print_error "❌ Failed to stop monitor (PID: $pid)"
            return 1
        fi
    fi

    # Verify process is gone
    if ps -p "$pid" >/dev/null; then
        print_error "❌ Failed to stop monitor (PID: $pid)"
        return 1
    fi

    print_success "✅ Monitor stopped successfully"
    rm -f "$MONITOR_PID_FILE"
    return 0
}

# Restart the monitor
restart_monitor() {
    print_header "🔄 Restarting ARK Server Monitor"

    # Stop the monitor first
    stop_monitor

    # Add a small delay
    sleep 2

    # Start the monitor
    if ! start_monitor; then
        print_error "❌ Failed to restart monitor"
        return 1
    fi

    print_success "✅ Monitor restarted successfully"
    return 0
}

# Show monitor logs
show_monitor_logs() {
    if [[ ! -f "$MONITOR_LOG" ]]; then
        print_error "❌ Monitor log file not found at: $MONITOR_LOG"
        return 1
    fi

    local lines=${1:-50}
    print_header "📋 Last $lines lines of monitor log"
    tail -n "$lines" "$MONITOR_LOG"

    return 0
}

# Follow monitor logs in real-time
follow_monitor_logs() {
    if [[ ! -f "$MONITOR_LOG" ]]; then
        print_error "❌ Monitor log file not found at: $MONITOR_LOG"
        return 1
    fi

    print_header "📋 Following monitor logs in real-time (press CTRL+C to stop)"
    echo ""

    # Show last 10 lines and then follow
    tail -n 10 -f "$MONITOR_LOG"

    return 0
}

# =============================================================================
# COMMAND LINE PARSING
# =============================================================================

# Parse command line arguments
parse_arguments() {
    COMMAND=""
    LOG_LINES=50

    if [[ $# -gt 0 ]]; then
        COMMAND="$1"
        shift

        # Check for additional args
        if [[ "$COMMAND" == "logs" && $# -gt 0 ]]; then
            LOG_LINES="$1"
        fi
    fi
}

# Script-specific cleanup function that will be called by common_cleanup
script_cleanup() {
    print_info "Cleaning up monitor manager resources..."

    # Any cleanup needed for monitorManager.sh
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

# Set up trap to call cleanup on exit
trap script_cleanup EXIT INT TERM

# Main function
main() {
    # Parse command line arguments
    parse_arguments "$@"

    # Check required environment variables
    check_required_env MONITOR_REQUIRED_VARS || exit 1

    # Execute requested command
    case "$COMMAND" in
    "status")
        check_monitor_status
        ;;
    "start")
        start_monitor
        ;;
    "stop")
        stop_monitor
        ;;
    "restart")
        restart_monitor
        ;;
    "logs")
        show_monitor_logs "$LOG_LINES"
        ;;
    "follow")
        follow_monitor_logs
        ;;
    *)
        # Default to showing status and usage
        check_monitor_status
        echo ""
        echo "Usage: ./monitorManager.sh [command]"
        echo "Commands:"
        echo "  status         - Check if the monitor is running"
        echo "  start          - Start the monitor"
        echo "  stop           - Stop the monitor"
        echo "  restart        - Restart the monitor"
        echo "  logs [lines]   - Show monitor logs (default: last 50 lines)"
        echo "  follow         - Follow monitor logs in real-time"
        ;;
    esac

    exit $?
}

# Execute the main function with all arguments
main "$@"
