#!/bin/bash
# Simplified logManager.sh with continuous monitoring and color coding

# Source color definitions from colorPrinter.sh if MANAGER_DIR is set
source "$MANAGER_DIR/utils/colorPrinter.sh"

# Define log-specific colors using the sourced colors or our fallbacks
COLOR_MAIN=$BLUE     # Blue
COLOR_GAME=$GREEN    # Green
COLOR_API=$MAGENTA   # Magenta
COLOR_WINE=$YELLOW   # Yellow
COLOR_MONITOR=$CYAN  # Cyan
COLOR_UNKNOWN=$WHITE # White

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
    printf "\033[0m\n"

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
        echo -e "${COLOR_MAIN}[$timestamp] [MAIN] $line${COLOR_RESET}"
        ;;
    "GAME")
        echo -e "${COLOR_GAME}[$timestamp] [GAME] $line${COLOR_RESET}"
        ;;
    "API")
        echo -e "${COLOR_API}[$timestamp] [API] $line${COLOR_RESET}"
        ;;
    "WINE")
        echo -e "${COLOR_WINE}[$timestamp] [WINE] $line${COLOR_RESET}"
        ;;
    "MONITOR")
        echo -e "${COLOR_MONITOR}[$timestamp] [MONITOR] $line${COLOR_RESET}"
        ;;
    *)
        echo -e "${COLOR_UNKNOWN}[$timestamp] [UNKNOWN] $line${COLOR_RESET}"
        ;;
    esac
}

# Function to monitor all logs with continuous checking for new files
tail_logs() {
    # Register another trap specifically for this function
    trap 'echo -e "\n${COLOR_RESET}"; return' INT

    echo -e "${COLOR_MAIN}📊 Monitoring All ARK Server Logs${COLOR_RESET}"
    echo -e "${COLOR_MAIN}Starting comprehensive log monitoring...${COLOR_RESET}"
    echo -e "${COLOR_MAIN}Checking for new logs every $CHECK_INTERVAL seconds${COLOR_RESET}"
    echo -e "${COLOR_MAIN}Press Ctrl+C to exit monitoring${COLOR_RESET}"
    echo ""

    # Variable to track current logs being monitored
    local current_files=""

    # Main monitoring loop
    while true; do
        # Prepare the list of files to tail
        local files_to_tail=""
        local found_logs=0

        # Add main log if it exists
        if [ -f "$LOG_FILE" ]; then
            files_to_tail="$LOG_FILE"
            ((found_logs++))
        fi

        # Add game log if it exists
        local latest_game_log=$(ls -t $GAME_LOG_FILE 2>/dev/null | head -n 1)
        if [ -n "$latest_game_log" ] && [ -f "$latest_game_log" ]; then
            if [ -n "$files_to_tail" ]; then
                files_to_tail="$files_to_tail $latest_game_log"
            else
                files_to_tail="$latest_game_log"
            fi
            ((found_logs++))
        fi

        # Add API log if it exists
        local latest_api_log=$(ls -t $API_LOG_FILE 2>/dev/null | head -n 1)
        if [ -n "$latest_api_log" ] && [ -f "$latest_api_log" ]; then
            if [ -n "$files_to_tail" ]; then
                files_to_tail="$files_to_tail $latest_api_log"
            else
                files_to_tail="$latest_api_log"
            fi
            ((found_logs++))
        fi

        # Add Wine log if it exists
        if [ -f "$WINE_LOG_FILE" ]; then
            if [ -n "$files_to_tail" ]; then
                files_to_tail="$files_to_tail $WINE_LOG_FILE"
            else
                files_to_tail="$WINE_LOG_FILE"
            fi
            ((found_logs++))
        fi

        # Add Monitor log if it exists
        if [ -f "$MONITOR_LOG" ]; then
            if [ -n "$files_to_tail" ]; then
                files_to_tail="$files_to_tail $MONITOR_LOG"
            else
                files_to_tail="$MONITOR_LOG"
            fi
            ((found_logs++))
        fi

        # Check if we have any log files to tail and if they've changed
        if is_empty "$files_to_tail"; then
            echo -e "${COLOR_UNKNOWN}Waiting for log files to appear...${COLOR_RESET}"
            sleep $CHECK_INTERVAL
            continue
        fi

        # Check if the files list has changed
        if does_not_equal "$files_to_tail" "$current_files"; then
            # Kill previous tail process if it exists
            if [ -n "$TAIL_PID" ]; then
                kill -9 $TAIL_PID 2>/dev/null || true
                wait $TAIL_PID 2>/dev/null || true
                unset TAIL_PID
            fi

            # Update current files list
            current_files="$files_to_tail"

            # Print the files we'll be monitoring
            echo -e "${COLOR_UNKNOWN}===== STARTING/UPDATING LOG MONITORING =====${COLOR_RESET}"
            echo -e "${COLOR_UNKNOWN}Tailing $found_logs log files: $files_to_tail${COLOR_RESET}"
            echo ""

            # Create a simple script for our tail process that will handle its own cleanup
            TEMP_SCRIPT=$(mktemp)

            cat >$TEMP_SCRIPT <<'EOF'
#!/bin/bash
# Define color codes for standalone script
COLOR_BLUE="\033[1;34m"       # Bold Blue
COLOR_GREEN="\033[1;32m"      # Bold Green
COLOR_MAGENTA="\033[1;35m"    # Bold Magenta
COLOR_YELLOW="\033[1;33m"     # Bold Yellow
COLOR_CYAN="\033[1;36m"       # Bold Cyan
COLOR_WHITE="\033[1;37m"      # Bold White
COLOR_RESET="\033[0m"         # Reset

# Map to specific log colors
COLOR_MAIN="$COLOR_BLUE"
COLOR_GAME="$COLOR_GREEN"
COLOR_API="$COLOR_MAGENTA"
COLOR_WINE="$COLOR_YELLOW"
COLOR_MONITOR="$COLOR_CYAN"
COLOR_UNKNOWN="$COLOR_WHITE"

# Cleanup on exit or interrupt
cleanup() {
    printf "\033[0m\n"
    exit
}
trap cleanup EXIT INT TERM

# Function to format log line
format_log_line() {
    local log_type="$1"
    local line="$2"
    local timestamp=$(date +%H:%M:%S)

    case "$log_type" in
    "MAIN")
        echo -e "${COLOR_MAIN}[$timestamp] [MAIN] $line${COLOR_RESET}"
        ;;
    "GAME")
        echo -e "${COLOR_GAME}[$timestamp] [GAME] $line${COLOR_RESET}"
        ;;
    "API")
        echo -e "${COLOR_API}[$timestamp] [API] $line${COLOR_RESET}"
        ;;
    "WINE")
        echo -e "${COLOR_WINE}[$timestamp] [WINE] $line${COLOR_RESET}"
        ;;
    "MONITOR")
        echo -e "${COLOR_MONITOR}[$timestamp] [MONITOR] $line${COLOR_RESET}"
        ;;
    *)
        echo -e "${COLOR_UNKNOWN}[$timestamp] [UNKNOWN] $line${COLOR_RESET}"
        ;;
    esac
}

# Initial log type
CURRENT_LOG_TYPE="UNKNOWN"

# Tail all logs and format output
tail -F "$@" 2>/dev/null | while read -r line; do
    # Check if this is a file header from tail -F
    if [[ "$line" == "==> "* ]]; then
        current_file=$(echo "$line" | sed 's/==> \(.*\) <==/\1/')
        filename=$(basename "$current_file")
        
        # Determine the log type based on the filename
        if [[ "$filename" == "ShooterGame.log" ]]; then
            CURRENT_LOG_TYPE="MAIN"
            echo -e "${COLOR_MAIN}[$(date +%H:%M:%S)] [HEADER] Switched to main log${COLOR_RESET}"
        elif [[ "$filename" == "ServerGame"* ]]; then
            CURRENT_LOG_TYPE="GAME"
            echo -e "${COLOR_GAME}[$(date +%H:%M:%S)] [HEADER] Switched to game log${COLOR_RESET}"
        elif [[ "$filename" == "ArkApi"* ]]; then
            CURRENT_LOG_TYPE="API"
            echo -e "${COLOR_API}[$(date +%H:%M:%S)] [HEADER] Switched to API log${COLOR_RESET}"
        elif [[ "$filename" == "wine.log" ]]; then
            CURRENT_LOG_TYPE="WINE"
            echo -e "${COLOR_WINE}[$(date +%H:%M:%S)] [HEADER] Switched to Wine log${COLOR_RESET}"
        elif [[ "$filename" == "server_monitor.log" ]]; then
            CURRENT_LOG_TYPE="MONITOR"
            echo -e "${COLOR_MONITOR}[$(date +%H:%M:%S)] [HEADER] Switched to monitor log${COLOR_RESET}"
        else
            CURRENT_LOG_TYPE="UNKNOWN"
            echo -e "${COLOR_UNKNOWN}[$(date +%H:%M:%S)] [HEADER] Switched to unknown log: $filename${COLOR_RESET}"
        fi
        
        continue
    fi
    
    # Format and display the log line
    format_log_line "$CURRENT_LOG_TYPE" "$line"
done
EOF

            # Make it executable
            chmod +x $TEMP_SCRIPT

            # Run the script in the background
            $TEMP_SCRIPT $files_to_tail &
            TAIL_PID=$!

            # Remove the temp script when the parent exits
            trap "rm -f $TEMP_SCRIPT; cleanup" EXIT INT TERM
        fi

        # Wait before checking for new files
        sleep $CHECK_INTERVAL
    done
}

# Function to monitor the main log only
monitor_main_log() {
    # Register another trap specifically for this function
    trap 'echo -e "\n${COLOR_RESET}"; return' INT

    echo -e "${COLOR_MAIN}📝 Monitoring Main Log${COLOR_RESET}"

    if [ -f "$LOG_FILE" ]; then
        echo -e "${COLOR_MAIN}Monitoring main log file: $LOG_FILE${COLOR_RESET}"
        tail -f "$LOG_FILE" | while read -r line; do
            format_log_line "MAIN" "$line"
        done
        echo -e "${COLOR_RESET}"
    else
        echo -e "${COLOR_UNKNOWN}❌ Main log file not found: $LOG_FILE${COLOR_RESET}"
        echo -e "${COLOR_UNKNOWN}Waiting for log file to appear...${COLOR_RESET}"

        # Wait for log file to appear
        while [ ! -f "$LOG_FILE" ]; do
            sleep 5
            echo -e "${COLOR_UNKNOWN}Still waiting for log file...${COLOR_RESET}"
        done

        echo -e "${COLOR_MAIN}Log file found! Starting to monitor.${COLOR_RESET}"
        tail -f "$LOG_FILE" | while read -r line; do
            format_log_line "MAIN" "$line"
        done
        echo -e "${COLOR_RESET}"
    fi
}

# Function to monitor only Wine logs
monitor_wine_logs() {
    # Register another trap specifically for this function
    trap 'echo -e "\n${COLOR_RESET}"; return' INT

    echo -e "${COLOR_WINE}🍷 Monitoring Wine Logs${COLOR_RESET}"

    if [ -f "$WINE_LOG_FILE" ]; then
        echo -e "${COLOR_WINE}Monitoring Wine log file: $WINE_LOG_FILE${COLOR_RESET}"
        tail -f "$WINE_LOG_FILE" | while read -r line; do
            format_log_line "WINE" "$line"
        done
        echo -e "${COLOR_RESET}"
    else
        echo -e "${COLOR_UNKNOWN}❌ Wine log file not found: $WINE_LOG_FILE${COLOR_RESET}"
        echo -e "${COLOR_UNKNOWN}Waiting for log file to appear...${COLOR_RESET}"

        # Wait for log file to appear
        while [ ! -f "$WINE_LOG_FILE" ]; do
            sleep 5
            echo -e "${COLOR_UNKNOWN}Still waiting for log file...${COLOR_RESET}"
        done

        echo -e "${COLOR_WINE}Log file found! Starting to monitor.${COLOR_RESET}"
        tail -f "$WINE_LOG_FILE" | while read -r line; do
            format_log_line "WINE" "$line"
        done
        echo -e "${COLOR_RESET}"
    fi
}

# Function to monitor only game logs
monitor_game_logs() {
    # Register another trap specifically for this function
    trap 'echo -e "\n${COLOR_RESET}"; return' INT

    echo -e "${COLOR_GAME}🎮 Monitoring Game Logs${COLOR_RESET}"

    # Find latest game log in a loop
    while true; do
        local latest_game_log=$(ls -t $GAME_LOG_FILE 2>/dev/null | head -n 1)

        if [ -n "$latest_game_log" ]; then
            echo -e "${COLOR_GAME}Monitoring game log file: $latest_game_log${COLOR_RESET}"
            tail -f "$latest_game_log" | while read -r line; do
                format_log_line "GAME" "$line"
            done
            echo -e "${COLOR_RESET}"
            break
        else
            echo -e "${COLOR_UNKNOWN}❌ No game log files found matching pattern: $GAME_LOG_FILE${COLOR_RESET}"
            echo -e "${COLOR_UNKNOWN}Waiting for log files to appear...${COLOR_RESET}"
            sleep 5
        fi
    done
}

# Function to monitor only API logs
monitor_api_logs() {
    # Register another trap specifically for this function
    trap 'echo -e "\n${COLOR_RESET}"; return' INT

    echo -e "${COLOR_API}🔌 Monitoring API Logs${COLOR_RESET}"

    # Find latest API log in a loop
    while true; do
        local latest_api_log=$(ls -t $API_LOG_FILE 2>/dev/null | head -n 1)

        if [ -n "$latest_api_log" ]; then
            echo -e "${COLOR_API}Monitoring API log file: $latest_api_log${COLOR_RESET}"
            tail -f "$latest_api_log" | while read -r line; do
                format_log_line "API" "$line"
            done
            echo -e "${COLOR_RESET}"
            break
        else
            echo -e "${COLOR_UNKNOWN}❌ No API log files found matching pattern: $API_LOG_FILE${COLOR_RESET}"
            echo -e "${COLOR_UNKNOWN}Waiting for log files to appear...${COLOR_RESET}"
            sleep 5
        fi
    done
}

# Function to monitor the monitor log
monitor_monitor_log() {
    # Register another trap specifically for this function
    trap 'echo -e "\n${COLOR_RESET}"; return' INT

    echo -e "${COLOR_MONITOR}🔍 Monitoring Monitor Log${COLOR_RESET}"

    if [ -f "$MONITOR_LOG" ]; then
        echo -e "${COLOR_MONITOR}Monitoring monitor log file: $MONITOR_LOG${COLOR_RESET}"
        tail -f "$MONITOR_LOG" | while read -r line; do
            format_log_line "MONITOR" "$line"
        done
        echo -e "${COLOR_RESET}"
    else
        echo -e "${COLOR_UNKNOWN}❌ Monitor log file not found: $MONITOR_LOG${COLOR_RESET}"
        echo -e "${COLOR_UNKNOWN}Waiting for log file to appear...${COLOR_RESET}"

        # Wait for log file to appear
        while [ ! -f "$MONITOR_LOG" ]; do
            sleep 5
            echo -e "${COLOR_UNKNOWN}Still waiting for log file...${COLOR_RESET}"
        done

        echo -e "${COLOR_MONITOR}Log file found! Starting to monitor.${COLOR_RESET}"
        tail -f "$MONITOR_LOG" | while read -r line; do
            format_log_line "MONITOR" "$line"
        done
        echo -e "${COLOR_RESET}"
    fi
}

# Function to monitor all logs (wrapper for tail_logs)
monitor_all_logs() {
    # Call the tail_logs function directly
    tail_logs
}
