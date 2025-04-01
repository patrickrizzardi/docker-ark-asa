#!/bin/bash
#
# ARK Server Log Tail Utility
# Shows all server logs in one consolidated view with color coding
#
# Usage: ./tail.sh [log-type]
# Options:
#   all          - Show all logs (default)
#   main         - Show only main server log
#   game         - Show only game logs
#   api          - Show only API logs
#   wine         - Show only Wine logs
#   monitor      - Show only monitor logs
#
# =============================================================================

# Load environment variables and utilities
UTILS_PATH="$MANAGER_DIR/utils"
source "${UTILS_PATH}/colorPrinter.sh"
source "${UTILS_PATH}/logManager.sh"

# Parse command line arguments
parse_arguments() {
    LOG_TYPE="all"

    if [[ $# -gt 0 ]]; then
        LOG_TYPE="$1"
    fi
}

# Main function
main() {
    # Parse command line arguments
    parse_arguments "$@"

    # Execute requested log viewing mode
    case "$LOG_TYPE" in
    "main")
        monitor_main_log
        ;;
    "game")
        monitor_game_logs
        ;;
    "api")
        monitor_api_logs
        ;;
    "wine")
        monitor_wine_logs
        ;;
    "monitor")
        monitor_monitor_log
        ;;
    "all" | *)
        monitor_all_logs
        ;;
    esac
}

# Execute the main function with all arguments
main "$@"
