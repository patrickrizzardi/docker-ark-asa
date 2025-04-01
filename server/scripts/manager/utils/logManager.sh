#!/bin/bash

# Load utilities
UTILS_PATH="$MANAGER_DIR/utils"
source "${UTILS_PATH}/colorPrinter.sh"

# Get environment variables or set defaults
LOG_FILE=${LOG_FILE:-"/steam/steamapps/common/asa-server/ShooterGame/Saved/Logs/ShooterGame.log"}
GAME_LOG_FILE=${GAME_LOG_FILE:-"/steam/steamapps/common/asa-server/ShooterGame/Saved/Logs/ServerGame.*.log"}
API_LOG_FILE=${API_LOG_FILE:-"/steam/steamapps/common/asa-server/ShooterGame/Binaries/Win64/logs/ArkApi_*.log"}
WINE_LOG_FILE=${WINE_LOG_FILE:-"/steam/steamapps/common/asa-server/ShooterGame/Binaries/Win64/logs/wine.log"}

# List of log files currently being tailed
declare -a TAILED_LOGS=()

# Start tailing a specific log file
start_tailing_log() {
    local log_file="$1"
    
    # Check if we're already tailing this file
    for tailed in "${TAILED_LOGS[@]}"; do
        if [ "$tailed" = "$log_file" ]; then
            return 0
        fi
    done
    
    print_info "Starting to monitor log file: $log_file"
    # Start tail in background and save PID
    tail -F "$log_file" &
    
    # Add to the list of tailed logs
    TAILED_LOGS+=("$log_file")
}

# Find and tail the latest log file matching a pattern
tail_latest_log_file() {
    local log_pattern="$1"
    
    # Use ls to find latest log for pattern
    local latest_log
    latest_log=$(ls -t $log_pattern 2>/dev/null | head -n 1)
    
    if [ -n "$latest_log" ]; then
        start_tailing_log "$latest_log"
    fi
}

# Function to tail multiple log files
tail_logs() {    
    # Check if main log file exists and start tailing
    if [ -f "$LOG_FILE" ]; then
        start_tailing_log "$LOG_FILE"
    fi
    
    # Check other log patterns
    tail_latest_log_file "$GAME_LOG_FILE"
    tail_latest_log_file "$API_LOG_FILE"
    tail_latest_log_file "$WINE_LOG_FILE"
    
    # Set up a loop to periodically check for new log files
    while true; do
        sleep 5
        
        # Check if main log file exists and start tailing
        if [ -f "$LOG_FILE" ]; then
            start_tailing_log "$LOG_FILE"
        fi
        
        # Check other log patterns
        tail_latest_log_file "$GAME_LOG_FILE"
        tail_latest_log_file "$API_LOG_FILE"
        tail_latest_log_file "$WINE_LOG_FILE"
    done
} 