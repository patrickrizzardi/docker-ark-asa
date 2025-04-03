#!/bin/bash

# Load utilities
UTILS_PATH="$MANAGER_DIR/utils"
source "${UTILS_PATH}/colorPrinter.sh"

# Get environment variables or set defaults
LOG_FILE=${LOG_FILE:-"/steam/steamapps/common/asa-server/ShooterGame/Saved/Logs/ShooterGame.log"}
GAME_LOG_FILE=${GAME_LOG_FILE:-"/steam/steamapps/common/asa-server/ShooterGame/Saved/Logs/ServerGame.*.log"}
API_LOG_FILE=${API_LOG_FILE:-"/steam/steamapps/common/asa-server/ShooterGame/Binaries/Win64/logs/ArkApi_*.log"}
WINE_LOG_FILE=${WINE_LOG_FILE:-"/steam/steamapps/common/asa-server/ShooterGame/Binaries/Win64/logs/wine.log"}
MONITOR_LOG=${MONITOR_LOG:-"/steam/steamapps/common/asa-server/logs/server_monitor.log"}

# Function to monitor all logs using a multi-tailing approach
tail_logs() {
    print_header "📊 Monitoring All ARK Server Logs"
    echo ""
    print_info "Starting comprehensive log monitoring..."

    # Debug: Show which log files the function found
    echo "Checking for log files..."
    echo "Main log: $LOG_FILE - Exists: $([ -f "$LOG_FILE" ] && echo "Yes" || echo "No")"

    # Check for game logs
    echo "Game logs pattern: $GAME_LOG_FILE"
    local game_logs=$(ls -t $GAME_LOG_FILE 2>/dev/null)
    if [ -n "$game_logs" ]; then
        echo "Found game logs:"
        echo "$game_logs"
        local latest_game_log=$(echo "$game_logs" | head -n 1)
        echo "Will tail: $latest_game_log"
    else
        echo "No game logs found matching pattern: $GAME_LOG_FILE"
    fi

    # Check for API logs
    echo "API logs pattern: $API_LOG_FILE"
    local api_logs=$(ls -t $API_LOG_FILE 2>/dev/null)
    if [ -n "$api_logs" ]; then
        echo "Found API logs:"
        echo "$api_logs"
        local latest_api_log=$(echo "$api_logs" | head -n 1)
        echo "Will tail: $latest_api_log"
    else
        echo "No API logs found matching pattern: $API_LOG_FILE"
    fi

    # Check for Wine log
    echo "Wine log: $WINE_LOG_FILE - Exists: $([ -f "$WINE_LOG_FILE" ] && echo "Yes" || echo "No")"

    # Check for Monitor log
    echo "Monitor log: $MONITOR_LOG - Exists: $([ -f "$MONITOR_LOG" ] && echo "Yes" || echo "No")"

    echo ""
    print_info "Press Ctrl+C to exit monitoring"
    echo ""

    # Simplified approach - dump recent content from each log first
    if [ -f "$LOG_FILE" ]; then
        echo -e "\033[1;34m===== RECENT MAIN LOG ENTRIES =====\033[0m"
        tail -n 20 "$LOG_FILE" | while read -r line; do
            echo -e "\033[1;34m[MAIN] $line\033[0m"
        done
        echo ""
    fi

    local latest_game_log=$(ls -t $GAME_LOG_FILE 2>/dev/null | head -n 1)
    if [ -f "$latest_game_log" ]; then
        echo -e "\033[1;32m===== RECENT GAME LOG ENTRIES =====\033[0m"
        tail -n 20 "$latest_game_log" | while read -r line; do
            echo -e "\033[1;32m[GAME] $line\033[0m"
        done
        echo ""
    fi

    local latest_api_log=$(ls -t $API_LOG_FILE 2>/dev/null | head -n 1)
    if [ -f "$latest_api_log" ]; then
        echo -e "\033[1;35m===== RECENT API LOG ENTRIES =====\033[0m"
        tail -n 20 "$latest_api_log" | while read -r line; do
            echo -e "\033[1;35m[API] $line\033[0m"
        done
        echo ""
    fi

    if [ -f "$WINE_LOG_FILE" ]; then
        echo -e "\033[1;33m===== RECENT WINE LOG ENTRIES =====\033[0m"
        tail -n 20 "$WINE_LOG_FILE" | while read -r line; do
            echo -e "\033[1;33m[WINE] $line\033[0m"
        done
        echo ""
    fi

    if [ -f "$MONITOR_LOG" ]; then
        echo -e "\033[1;36m===== RECENT MONITOR LOG ENTRIES =====\033[0m"
        tail -n 20 "$MONITOR_LOG" | while read -r line; do
            echo -e "\033[1;36m[MONITOR] $line\033[0m"
        done
        echo ""
    fi

    # Now set up the real-time monitoring
    echo -e "\033[1;37m===== STARTING REAL-TIME LOG MONITORING =====\033[0m"
    echo ""

    # Use a single command with multiple tails to ensure this works in Docker
    # This simpler approach is more compatible with containerized environments

    # First, prepare the log files to tail
    local files_to_tail=""

    # Add main log if it exists
    if [ -f "$LOG_FILE" ]; then
        files_to_tail="$LOG_FILE"
    fi

    # Add game log if it exists
    local latest_game_log=$(ls -t $GAME_LOG_FILE 2>/dev/null | head -n 1)
    if [ -f "$latest_game_log" ]; then
        files_to_tail="$files_to_tail $latest_game_log"
    fi

    # Add API log if it exists
    local latest_api_log=$(ls -t $API_LOG_FILE 2>/dev/null | head -n 1)
    if [ -f "$latest_api_log" ]; then
        files_to_tail="$files_to_tail $latest_api_log"
    fi

    # Add Wine log if it exists
    if [ -f "$WINE_LOG_FILE" ]; then
        files_to_tail="$files_to_tail $WINE_LOG_FILE"
    fi

    # Add Monitor log if it exists
    if [ -f "$MONITOR_LOG" ]; then
        files_to_tail="$files_to_tail $MONITOR_LOG"
    fi

    # Check if we have any log files to tail
    if [ -z "$files_to_tail" ]; then
        print_error "❌ No log files found to tail!"
        return 1
    fi

    # Print the files we'll be monitoring
    echo "Tailing log files: $files_to_tail"
    echo ""

    # Track which log file we're currently reading from
    CURRENT_LOG_TYPE="UNKNOWN"

    # Use a simple but effective approach with tail -F
    tail -F $files_to_tail | while read -r line; do
        # Check if this is a file header line from tail -F
        if [[ "$line" == "==> "* ]]; then
            local current_file=$(echo "$line" | sed 's/==> \(.*\) <==/\1/')
            local filename=$(basename "$current_file")

            # Determine the log type based on the filename
            if [[ "$filename" == "ShooterGame.log" ]]; then
                CURRENT_LOG_TYPE="MAIN"
                echo -e "\033[1;34m[$(date +%H:%M:%S)] [HEADER] Switched to main log\033[0m"
            elif [[ "$filename" == "ServerGame"* ]]; then
                CURRENT_LOG_TYPE="GAME"
                echo -e "\033[1;32m[$(date +%H:%M:%S)] [HEADER] Switched to game log\033[0m"
            elif [[ "$filename" == "ArkApi"* ]]; then
                CURRENT_LOG_TYPE="API"
                echo -e "\033[1;35m[$(date +%H:%M:%S)] [HEADER] Switched to API log\033[0m"
            elif [[ "$filename" == "wine.log" ]]; then
                CURRENT_LOG_TYPE="WINE"
                echo -e "\033[1;33m[$(date +%H:%M:%S)] [HEADER] Switched to Wine log\033[0m"
            elif [[ "$filename" == "server_monitor.log" ]]; then
                CURRENT_LOG_TYPE="MONITOR"
                echo -e "\033[1;36m[$(date +%H:%M:%S)] [HEADER] Switched to monitor log\033[0m"
            else
                CURRENT_LOG_TYPE="UNKNOWN"
                echo -e "\033[1;37m[$(date +%H:%M:%S)] [HEADER] Switched to unknown log: $filename\033[0m"
            fi

            continue
        fi

        # Color and format based on the current log type
        case "$CURRENT_LOG_TYPE" in
        "MAIN")
            echo -e "\033[1;34m[$(date +%H:%M:%S)] [MAIN] $line\033[0m"
            ;;
        "GAME")
            echo -e "\033[1;32m[$(date +%H:%M:%S)] [GAME] $line\033[0m"
            ;;
        "API")
            echo -e "\033[1;35m[$(date +%H:%M:%S)] [API] $line\033[0m"
            ;;
        "WINE")
            echo -e "\033[1;33m[$(date +%H:%M:%S)] [WINE] $line\033[0m"
            ;;
        "MONITOR")
            echo -e "\033[1;36m[$(date +%H:%M:%S)] [MONITOR] $line\033[0m"
            ;;
        *)
            # Try to identify based on content patterns as a fallback
            if [[ "$line" == *"ShooterGame"*"]"* || "$line" == *"["*"-"*"-"*":"*"]"* ]]; then
                # This looks like a main log entry
                echo -e "\033[1;34m[$(date +%H:%M:%S)] [MAIN] $line\033[0m"
            elif [[ "$line" == *"ServerGame"* ]]; then
                echo -e "\033[1;32m[$(date +%H:%M:%S)] [GAME] $line\033[0m"
            elif [[ "$line" == *"ArkApi"* ]]; then
                echo -e "\033[1;35m[$(date +%H:%M:%S)] [API] $line\033[0m"
            elif [[ "$line" == *"wine"* || "$line" == *"WINE"* ]]; then
                echo -e "\033[1;33m[$(date +%H:%M:%S)] [WINE] $line\033[0m"
            elif [[ "$line" == *"Monitor"* || "$line" == *"monitor"* || "$line" == *"0m"* ]]; then
                echo -e "\033[1;36m[$(date +%H:%M:%S)] [MONITOR] $line\033[0m"
            else
                # Default to white for truly unknown sources
                echo -e "\033[1;37m[$(date +%H:%M:%S)] [UNKNOWN] $line\033[0m"
            fi
            ;;
        esac
    done
}

# Function to monitor the main log only
monitor_main_log() {
    print_header "📝 Monitoring Main Log"
    echo ""

    if [ -f "$LOG_FILE" ]; then
        print_info "Monitoring main log file: $LOG_FILE"
        tail -f "$LOG_FILE"
    else
        print_error "❌ Main log file not found: $LOG_FILE"
        return 1
    fi
}

# Function to monitor only Wine logs
monitor_wine_logs() {
    print_header "🍷 Monitoring Wine Logs"
    echo ""

    if [ -f "$WINE_LOG_FILE" ]; then
        print_info "Monitoring Wine log file: $WINE_LOG_FILE"
        tail -f "$WINE_LOG_FILE"
    else
        print_error "❌ Wine log file not found: $WINE_LOG_FILE"
        return 1
    fi
}

# Function to monitor only game logs
monitor_game_logs() {
    print_header "🎮 Monitoring Game Logs"
    echo ""

    # Find latest game log
    local latest_game_log=$(ls -t $GAME_LOG_FILE 2>/dev/null | head -n 1)

    if [ -n "$latest_game_log" ]; then
        print_info "Monitoring game log file: $latest_game_log"
        tail -f "$latest_game_log"
    else
        print_error "❌ No game log files found matching pattern: $GAME_LOG_FILE"
        return 1
    fi
}

# Function to monitor only API logs
monitor_api_logs() {
    print_header "🔌 Monitoring API Logs"
    echo ""

    # Find latest API log
    local latest_api_log=$(ls -t $API_LOG_FILE 2>/dev/null | head -n 1)

    if [ -n "$latest_api_log" ]; then
        print_info "Monitoring API log file: $latest_api_log"
        tail -f "$latest_api_log"
    else
        print_error "❌ No API log files found matching pattern: $API_LOG_FILE"
        return 1
    fi
}

# Function to monitor the monitor log
monitor_monitor_log() {
    print_header "🔍 Monitoring Monitor Log"
    echo ""

    if [ -f "$MONITOR_LOG" ]; then
        print_info "Monitoring monitor log file: $MONITOR_LOG"
        tail -f "$MONITOR_LOG"
    else
        print_error "❌ Monitor log file not found: $MONITOR_LOG"
        return 1
    fi
}

# Function to monitor all logs (wrapper around tail_logs with proper header)
monitor_all_logs() {
    # Call the tail_logs function directly
    tail_logs
}
