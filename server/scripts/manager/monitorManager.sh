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
source "${UTILS_PATH}/colorPrinter.sh"
source "${UTILS_PATH}/processManager.sh"
source "${UTILS_PATH}/envManager.sh"

# =============================================================================
# CONFIGURATION
# =============================================================================

# Required environment variables
declare -a MONITOR_REQUIRED_VARS=(
    "MANAGER_DIR" # Manager scripts directory
)

# Log file for the monitor - use environment variable if set, otherwise use default
MONITOR_SCRIPT="${MANAGER_DIR}/monitor.sh"
MONITOR_PID_FILE="${ARK_DIR}/monitor.pid"

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Create log directory if it doesn't exist
mkdir -p "$(dirname "$MONITOR_LOG")" 2>/dev/null || true

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

# Check monitor status
check_monitor_status() {
    local pid=$(get_monitor_pid)

    if [[ "$pid" == "0" ]]; then
        print_warning "⚠️ Monitor is not running"
        return 1
    else
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

        # Check log file timestamp
        if [[ -f "$MONITOR_LOG" ]]; then
            local log_time=$(stat -c %y "$MONITOR_LOG" 2>/dev/null || date -r "$MONITOR_LOG" "+%Y-%m-%d %H:%M:%S" 2>/dev/null)
            echo "Last log update: $log_time"

            # Check if log has been updated recently
            local log_age=$(($(date +%s) - $(date -d "$log_time" +%s 2>/dev/null || date -j -f "%Y-%m-%d %H:%M:%S" "$log_time" +%s 2>/dev/null)))
            if [[ $log_age -gt 300 ]]; then # 5 minutes
                print_warning "⚠️ Monitor log hasn't been updated in $(($log_age / 60)) minutes"
            else
                print_info "Monitor log updated $(($log_age / 60)) minutes $(($log_age % 60)) seconds ago"
            fi
        else
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
        fi

        return 0
    fi
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
    if ps -p "$new_pid" >/dev/null; then
        print_success "✅ Monitor started successfully (PID: $new_pid)"
        return 0
    else
        print_error "❌ Failed to start monitor"
        rm -f "$MONITOR_PID_FILE"
        return 1
    fi
}

# Stop the monitor
stop_monitor() {
    local pid=$(get_monitor_pid)

    if [[ "$pid" == "0" ]]; then
        print_warning "⚠️ Monitor is not running"
        return 0
    fi

    print_header "🛑 Stopping ARK Server Monitor"

    # Kill the process
    if kill -15 "$pid" 2>/dev/null; then
        print_info "Sent SIGTERM to monitor process ($pid)..."

        # Wait for process to exit
        local counter=0
        while ps -p "$pid" >/dev/null && [[ $counter -lt 10 ]]; do
            sleep 1
            counter=$((counter + 1))
        done

        if ps -p "$pid" >/dev/null; then
            print_warning "⚠️ Monitor didn't terminate gracefully, forcing..."
            kill -9 "$pid" 2>/dev/null
            sleep 1
        fi

        # Verify process is gone
        if ps -p "$pid" >/dev/null; then
            print_error "❌ Failed to stop monitor (PID: $pid)"
            return 1
        else
            print_success "✅ Monitor stopped successfully"
            rm -f "$MONITOR_PID_FILE"
            return 0
        fi
    else
        print_error "❌ Failed to send stop signal to monitor"
        return 1
    fi
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
# MAIN EXECUTION
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

# Main function
main() {
    # Parse command line arguments
    parse_arguments "$@"

    # Check required environment variables
    if ! check_env_variables MONITOR_REQUIRED_VARS 0; then
        print_error "❌ Missing required environment variables"
        exit 1
    fi

    # Additional required variable check
    if [[ -z "$MONITOR_LOG" && -z "$ARK_DIR" ]]; then
        print_error "❌ Neither MONITOR_LOG nor ARK_DIR environment variables are set"
        print_info "Please set either MONITOR_LOG directly or ARK_DIR for default log location"
        exit 1
    fi

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
        stop_monitor && start_monitor
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
