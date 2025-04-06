#!/bin/bash
# Simplified logManager.sh with continuous monitoring and color coding

# Source color definitions from colorPrinter.sh if MANAGER_DIR is set
source "$MANAGER_DIR/utils/colorPrinter.sh"
source "$MANAGER_DIR/utils/baseUtils.sh"

# Get environment variables or set defaults
CHECK_INTERVAL=${CHECK_INTERVAL:-10} # How often to check for new log files (seconds)

# Improved cleanup function to ensure colors are reset
cleanup() {
    local exit_code=$?

    # Kill any background processes we've started
    if [ -n "$TAIL_PID" ]; then
        kill -9 $TAIL_PID 2>/dev/null || true
        wait $TAIL_PID 2>/dev/null || true
    fi

    # Force color reset to terminal
    printf "${NC}"

    # Extra newline for clean exit
    echo ""
    echo "Log monitoring stopped."

    exit $exit_code
}

# Set trap to ensure cleanup on exit, including SIGINT (Ctrl+C)
trap cleanup EXIT INT TERM HUP

# Function to format log line with color based on source
format_log_line() {
    local log_type="$1"
    local line="$2"
    local timestamp=$(date +%H:%M:%S)

    case "$log_type" in
    "MAIN")
        echo -e "${BLUE}[$timestamp] [MAIN]${NC} $line"
        ;;
    "GAME")
        echo -e "${GREEN}[$timestamp] [GAME]${NC} $line"
        ;;
    "API")
        echo -e "${MAGENTA}[$timestamp] [API]${NC} $line"
        ;;
    "WINE")
        echo -e "${YELLOW}[$timestamp] [WINE]${NC} $line"
        ;;
    "MONITOR")
        echo -e "${CYAN}[$timestamp] [MONITOR]${NC} $line"
        ;;
    *)
        echo -e "${NC}[$timestamp] [UNKNOWN]${NC} $line"
        ;;
    esac
}

# Function to monitor all logs with continuous checking for new files
monitor_all_logs() {
    # Register another trap specifically for this function
    trap 'echo -e "\n${NC}"; return' INT

    print_script_header "📊 Monitoring All ARK Server Logs"

    print_info "Checking for new logs every $CHECK_INTERVAL seconds"
    print_info "Press Ctrl+C to exit monitoring"
    echo ""

    # Variable to track current logs being monitored
    local current_files=""
    local TAIL_PID=""

    # Main monitoring loop
    while true; do
        # Prepare the list of files to tail
        local files_to_tail=""
        local found_logs=0

        # Add main log if it exists
        if file_exists "$LOG_FILE"; then
            files_to_tail="$LOG_FILE"
            ((found_logs++))
        fi

        # Add game log if it exists
        local latest_game_log=$(ls -t $GAME_LOG_FILE 2>/dev/null | head -n 1)
        if file_exists "$latest_game_log" && is_not_empty "$latest_game_log"; then
            files_to_tail="$files_to_tail $latest_game_log"
            ((found_logs++))
        fi

        # Add API log if it exists
        local latest_api_log=$(ls -t $API_LOG_FILE 2>/dev/null | head -n 1)
        if file_exists "$latest_api_log" && is_not_empty "$latest_api_log"; then
            files_to_tail="$files_to_tail $latest_api_log"
            ((found_logs++))
        fi

        # Add Wine log if it exists
        if file_exists "$WINE_LOG_FILE" && is_not_empty "$WINE_LOG_FILE"; then
            files_to_tail="$files_to_tail $WINE_LOG_FILE"
            ((found_logs++))
        fi

        # Add Monitor log if it exists
        if file_exists "$MONITOR_LOG" && is_not_empty "$MONITOR_LOG"; then
            files_to_tail="$files_to_tail $MONITOR_LOG"
            ((found_logs++))
        fi

        # Add Crash log if it exists
        if file_exists "$CRASH_LOG_FILE" && is_not_empty "$CRASH_LOG_FILE"; then
            files_to_tail="$files_to_tail $CRASH_LOG_FILE"
            ((found_logs++))
        fi

        # Check if we have any log files to tail and if they've changed
        if is_empty "$files_to_tail"; then
            print_info "Waiting for log files to appear..."
            sleep $CHECK_INTERVAL
            continue
        fi

        # If files have changed, restart tail
        if [ "$files_to_tail" != "$current_files" ]; then
            # Kill previous tail if running
            if [ -n "$TAIL_PID" ]; then
                kill $TAIL_PID 2>/dev/null || true
                wait $TAIL_PID 2>/dev/null || true
            fi

            current_files="$files_to_tail"
            print_info "Monitoring $found_logs log file(s)"

            # Start new tail process in background
            tail -f $files_to_tail | while read -r line; do
                format_log_line "$CURRENT_LOG_TYPE" "$line"
            done &
            TAIL_PID=$!
        fi

        # Wait before checking for new files
        sleep $CHECK_INTERVAL
    done
}

# Function to monitor the main log only
monitor_main_log() {
    # Register another trap specifically for this function
    trap 'echo -e "\n${NC}"; return' INT

    print_script_header "📝 Monitoring Main Log"

    local current_log=""
    local TAIL_PID=""

    # Continuous monitoring loop
    while true; do
        # Only continue if log file exists or has changed
        if file_exists "$LOG_FILE" && [ "$LOG_FILE" != "$current_log" ]; then
            # Kill previous tail if running
            if [ -n "$TAIL_PID" ]; then
                kill $TAIL_PID 2>/dev/null || true
                wait $TAIL_PID 2>/dev/null || true
            fi

            current_log="$LOG_FILE"
            print_info "Monitoring main log file: $current_log"

            # Start new tail process in background
            tail -f "$current_log" | while read -r line; do
                format_log_line "MAIN" "$line"
            done &
            TAIL_PID=$!
        elif file_does_not_exist "$LOG_FILE"; then
            print_info "Waiting for log file to appear: $LOG_FILE"
            current_log=""
        fi

        sleep $CHECK_INTERVAL
    done
}

# Function to monitor the Crash log
monitor_crash_log() {
    # Register another trap specifically for this function
    trap 'echo -e "\n${NC}"; return' INT

    print_script_header "💥 Monitoring Crash Log"

    local current_log=""
    local TAIL_PID=""

    # Continuous monitoring loop
    while true; do
        # Only continue if log file exists or has changed
        if file_exists "$CRASH_LOG_FILE" && [ "$CRASH_LOG_FILE" != "$current_log" ]; then
            # Kill previous tail if running
            if [ -n "$TAIL_PID" ]; then
                kill $TAIL_PID 2>/dev/null || true
                wait $TAIL_PID 2>/dev/null || true
            fi

            current_log="$CRASH_LOG_FILE"
            print_info "Monitoring crash log file: $current_log"

            # Start new tail process in background
            tail -f "$current_log" | while read -r line; do
                format_log_line "CRASH" "$line"
            done &
            TAIL_PID=$!
        elif file_does_not_exist "$CRASH_LOG_FILE"; then
            print_info "Waiting for crash log file to appear: $CRASH_LOG_FILE"
            current_log=""
        fi

        sleep $CHECK_INTERVAL
    done
}

# Function to monitor only Wine logs
monitor_wine_logs() {
    # Register another trap specifically for this function
    trap 'echo -e "\n${NC}"; return' INT

    print_script_header "🍷 Monitoring Wine Logs"

    local current_log=""
    local TAIL_PID=""

    # Continuous monitoring loop
    while true; do
        # Only continue if log file exists or has changed
        if file_exists "$WINE_LOG_FILE" && [ "$WINE_LOG_FILE" != "$current_log" ]; then
            # Kill previous tail if running
            if [ -n "$TAIL_PID" ]; then
                kill $TAIL_PID 2>/dev/null || true
                wait $TAIL_PID 2>/dev/null || true
            fi

            current_log="$WINE_LOG_FILE"
            print_info "Monitoring wine log file: $current_log"

            # Start new tail process in background
            tail -f "$current_log" | while read -r line; do
                format_log_line "WINE" "$line"
            done &
            TAIL_PID=$!
        elif file_does_not_exist "$WINE_LOG_FILE"; then
            print_info "Waiting for wine log file to appear: $WINE_LOG_FILE"
            current_log=""
        fi

        sleep $CHECK_INTERVAL
    done
}

# Function to monitor only game logs
monitor_game_logs() {
    # Register another trap specifically for this function
    trap 'echo -e "\n${NC}"; return' INT

    print_script_header "🎮 Monitoring Game Logs"

    local current_log=""
    local TAIL_PID=""

    # Continuous monitoring loop
    while true; do
        local latest_game_log=$(ls -t $GAME_LOG_FILE 2>/dev/null | head -n 1)

        # Only continue if a new log file exists and has changed
        if file_exists "$latest_game_log" && [ "$latest_game_log" != "$current_log" ]; then
            # Kill previous tail if running
            if [ -n "$TAIL_PID" ]; then
                kill $TAIL_PID 2>/dev/null || true
                wait $TAIL_PID 2>/dev/null || true
            fi

            current_log="$latest_game_log"
            print_info "Monitoring game log file: $current_log"

            # Start new tail process in background
            tail -f "$current_log" | while read -r line; do
                format_log_line "GAME" "$line"
            done &
            TAIL_PID=$!
        elif [ -z "$latest_game_log" ]; then
            # No game logs found
            print_info "Waiting for game log files to appear matching: $GAME_LOG_FILE"
            current_log=""
        fi

        sleep $CHECK_INTERVAL
    done
}

# Function to monitor only API logs
monitor_api_logs() {
    # Register another trap specifically for this function
    trap 'echo -e "\n${NC}"; return' INT

    print_script_header "🔌 Monitoring API Logs"

    local current_log=""
    local TAIL_PID=""

    # Continuous monitoring loop
    while true; do
        local latest_api_log=$(ls -t $API_LOG_FILE 2>/dev/null | head -n 1)

        # Only continue if a new log file exists and has changed
        if file_exists "$latest_api_log" && [ "$latest_api_log" != "$current_log" ]; then
            # Kill previous tail if running
            if [ -n "$TAIL_PID" ]; then
                kill $TAIL_PID 2>/dev/null || true
                wait $TAIL_PID 2>/dev/null || true
            fi

            current_log="$latest_api_log"
            print_info "Monitoring API log file: $current_log"

            # Start new tail process in background
            tail -f "$current_log" | while read -r line; do
                format_log_line "API" "$line"
            done &
            TAIL_PID=$!
        elif [ -z "$latest_api_log" ]; then
            # No API logs found
            print_info "Waiting for API log files to appear matching: $API_LOG_FILE"
            current_log=""
        fi

        sleep $CHECK_INTERVAL
    done
}

# Function to monitor the monitor log
monitor_monitor_log() {
    # Register another trap specifically for this function
    trap 'echo -e "\n${NC}"; return' INT

    print_script_header "🔍 Monitoring Monitor Log"

    local current_log=""
    local TAIL_PID=""

    # Continuous monitoring loop
    while true; do
        # Only continue if log file exists or has changed
        if file_exists "$MONITOR_LOG" && [ "$MONITOR_LOG" != "$current_log" ]; then
            # Kill previous tail if running
            if [ -n "$TAIL_PID" ]; then
                kill $TAIL_PID 2>/dev/null || true
                wait $TAIL_PID 2>/dev/null || true
            fi

            current_log="$MONITOR_LOG"
            print_info "Monitoring monitor log file: $current_log"

            # Start new tail process in background
            tail -f "$current_log" | while read -r line; do
                format_log_line "MONITOR" "$line"
            done &
            TAIL_PID=$!
        elif file_does_not_exist "$MONITOR_LOG"; then
            print_info "Waiting for monitor log file to appear: $MONITOR_LOG"
            current_log=""
        fi

        sleep $CHECK_INTERVAL
    done
}
