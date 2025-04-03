#!/bin/bash
#
# ARK Server Log Tail Utility
# Shows all server logs in one consolidated view with color coding
#
# Usage: ./tail.sh [options]
# Options:
#   --all         - Show all logs (default)
#   --game        - Show only game logs
#   --api         - Show only API logs
#   --main        - Show only main server log
#   --wine        - Show only Wine logs
#   --monitor     - Show only monitor logs
#   --lines N     - Show the last N lines (default: 100)
#   --follow      - Follow the log output in real-time (default)
#   --no-follow   - Don't follow logs, just show and exit
#
# =============================================================================

# Load environment variables and utilities
UTILS_PATH="$MANAGER_DIR/utils"
source "${UTILS_PATH}/colorPrinter.sh"
source "${UTILS_PATH}/logManager.sh"

# Parse command line arguments
parse_arguments() {
    LOG_TYPE="all"
    LINES=100
    FOLLOW=true

    while [[ $# -gt 0 ]]; do
        case "$1" in
        "--all")
            LOG_TYPE="all"
            shift
            ;;
        "--game")
            LOG_TYPE="game"
            shift
            ;;
        "--api")
            LOG_TYPE="api"
            shift
            ;;
        "--main")
            LOG_TYPE="main"
            shift
            ;;
        "--wine")
            LOG_TYPE="wine"
            shift
            ;;
        "--monitor")
            LOG_TYPE="monitor"
            shift
            ;;
        "--lines")
            if [[ $# -gt 1 && "$2" =~ ^[0-9]+$ ]]; then
                LINES="$2"
                shift 2
            else
                print_error "Missing or invalid value for --lines"
                exit 1
            fi
            ;;
        "--follow")
            FOLLOW=true
            shift
            ;;
        "--no-follow")
            FOLLOW=false
            shift
            ;;
        *)
            # For backward compatibility
            LOG_TYPE="$1"
            shift
            ;;
        esac
    done
}

# Main function
main() {
    # Parse command line arguments
    parse_arguments "$@"

    # Build the tail command with options
    TAIL_OPTS=""
    if [ "$FOLLOW" = true ]; then
        TAIL_OPTS="-f"
    fi
    TAIL_OPTS="$TAIL_OPTS -n $LINES"

    # Execute requested log viewing mode
    case "$LOG_TYPE" in
    "main")
        monitor_main_log "$TAIL_OPTS"
        ;;
    "game")
        monitor_game_logs "$TAIL_OPTS"
        ;;
    "api")
        monitor_api_logs "$TAIL_OPTS"
        ;;
    "wine")
        monitor_wine_logs "$TAIL_OPTS"
        ;;
    "monitor")
        monitor_monitor_log "$TAIL_OPTS"
        ;;
    "all" | *)
        monitor_all_logs "$TAIL_OPTS"
        ;;
    esac
}

# Execute the main function with all arguments
main "$@"
