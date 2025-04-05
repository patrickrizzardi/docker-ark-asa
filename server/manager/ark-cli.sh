#!/bin/bash
# TODO

# ARK Server CLI Wrapper
# Provides a unified interface for ARK Server management commands

source "${MANAGER_DIR}/utils/common.sh"

# Get the name of this script (for error messages)
SCRIPT_NAME=$(basename "$0")
# Determine if we're being run directly or as a symlink
if [ -L "$0" ]; then
    # Just use the basename of the symlink without resolving it
    COMMAND_NAME=$(basename "$0")
else
    COMMAND_NAME="$SCRIPT_NAME"
fi

# Define the commands and their descriptions
declare -A COMMANDS=(
    ["init"]="Initialize server environment (runs automatically on startup)"
    ["monitor"]="Manage the server monitor (status, start, stop, logs, etc.)"
    ["update"]="Update the ARK server"
    ["stop"]="Stop the ARK server"
    ["start"]="Start the ARK server"
    ["restart"]="Restart the ARK server"
    ["status"]="Check server status"
    ["logs"]="View server logs"
    ["rcon"]="Access the remote console"
    ["backup"]="Backup server data"
    ["restore"]="Restore server data from backup"
)

# Function to display the main help
show_help() {
    echo -e "${BLUE}ARK Server Management CLI${NC}"
    echo -e "${YELLOW}Usage:${NC} $COMMAND_NAME [command] [options]"
    echo
    echo -e "${YELLOW}Available commands:${NC}"

    # Get the longest command name for padding
    local max_length=0
    for cmd in "${!COMMANDS[@]}"; do
        if [ ${#cmd} -gt $max_length ]; then
            max_length=${#cmd}
        fi
    done

    # Sort commands alphabetically and display with descriptions
    for cmd in $(echo "${!COMMANDS[@]}" | tr ' ' '\n' | sort); do
        printf "  ${GREEN}%-${max_length}s${NC}  %s\n" "$cmd" "${COMMANDS[$cmd]}"
    done

    echo
    echo -e "${YELLOW}For command-specific help, run:${NC} $COMMAND_NAME [command] --help"
}

# Function to run a command
run_command() {
    local cmd="$1"
    shift

    # Map commands to script files if needed
    local script_file="${cmd}"
    case "${cmd}" in
    "init")
        script_file="init"
        ;;
    "logs")
        script_file="logs"
        ;;
    "restore")
        script_file="restore"
        ;;
    "rcon")
        script_file="rcon"
        ;;
    "start")
        script_file="start"
        ;;
    "stop")
        script_file="stop"
        ;;
    "restart")
        script_file="restart"
        ;;
    "status")
        script_file="status"
        ;;
    "backup")
        script_file="backup"
        ;;
    "update")
        script_file="update"
        ;;
    "monitor")
        script_file="monitorManager"
        ;;
    "wipe")
        script_file="wipe"
        ;;
    esac

    # Check if command exists
    if file_does_not_exist "${MANAGER_DIR}/${script_file}.sh"; then
        echo -e "${RED}Error:${NC} Command '${cmd}' not found."
        echo "Run '$COMMAND_NAME --help' to see available commands."
        return 1
    fi

    # Check for help flag
    if contains "$*" "--help" || contains "$*" "-h"; then
        show_command_help "$cmd"
        return 0
    fi

    # Execute the command with all arguments
    "${MANAGER_DIR}/${script_file}.sh" "$@"
    return $?
}

# Function to show command-specific help
show_command_help() {
    local cmd="$1"

    echo -e "${BLUE}ARK Server Management CLI - ${GREEN}${cmd}${NC}"
    echo -e "${YELLOW}Description:${NC} ${COMMANDS[$cmd]}"
    echo

    case "$cmd" in
    init)
        echo -e "${YELLOW}Usage:${NC} $COMMAND_NAME init"
        echo "Initializes the ARK server environment. This is run automatically on container startup."
        ;;
    monitor)
        echo -e "${YELLOW}Usage:${NC} $COMMAND_NAME monitor [command]"
        echo "Manages the ARK server monitor."
        echo
        echo -e "${YELLOW}Available commands:${NC}"
        echo "  status       Check if the monitor is running"
        echo "  start        Start the monitor"
        echo "  stop         Stop the monitor"
        echo "  restart      Restart the monitor"
        echo "  logs         Show monitor logs"
        echo "  follow       Follow monitor logs in real-time"
        echo
        echo -e "${YELLOW}Examples:${NC}"
        echo "  $COMMAND_NAME monitor status     Check current monitor status"
        echo "  $COMMAND_NAME monitor start      Start the monitor process"
        echo "  $COMMAND_NAME monitor logs       View the monitor logs"
        ;;
    update)
        echo -e "${YELLOW}Usage:${NC} $COMMAND_NAME update"
        echo "Updates the ARK server to the latest version."
        ;;
    stop)
        echo -e "${YELLOW}Usage:${NC} $COMMAND_NAME stop [options]"
        echo "Stops the ARK server gracefully."
        echo
        echo -e "${YELLOW}Options:${NC}"
        echo "  --force      Force stop the server immediately"
        ;;
    start)
        echo -e "${YELLOW}Usage:${NC} $COMMAND_NAME start [options]"
        echo "Starts the ARK server."
        ;;
    restart)
        echo -e "${YELLOW}Usage:${NC} $COMMAND_NAME restart"
        echo "Restarts the ARK server gracefully."
        ;;
    status)
        echo -e "${YELLOW}Usage:${NC} $COMMAND_NAME status"
        echo "Displays the current status of the ARK server."
        ;;
    logs)
        echo -e "${YELLOW}Usage:${NC} $COMMAND_NAME logs [options]"
        echo "Shows the ARK server logs."
        echo
        echo -e "${YELLOW}Options:${NC}"
        echo "  --lines N    Show the last N lines (default: 100)"
        echo "  --follow     Follow the log output in real-time (default)"
        echo "  --game       Show only game logs"
        echo "  --api        Show only API logs"
        echo "  --all        Show all logs (default)"
        echo
        echo -e "${YELLOW}Examples:${NC}"
        echo "  $COMMAND_NAME logs              Follow all logs in real-time"
        echo "  $COMMAND_NAME logs --lines 200  Show last 200 lines of all logs"
        echo "  $COMMAND_NAME logs --game       Show only game logs"
        ;;
    rcon)
        echo -e "${YELLOW}Usage:${NC} $COMMAND_NAME rcon [command]"
        echo "Executes RCON commands on the ARK server."
        echo
        echo -e "${YELLOW}Examples:${NC}"
        echo "  $COMMAND_NAME rcon listplayers           List all players on the server"
        echo "  $COMMAND_NAME rcon broadcast \"Hello\"     Broadcast a message to all players"
        ;;
    backup)
        echo -e "${YELLOW}Usage:${NC} $COMMAND_NAME backup [name]"
        echo "Creates a backup of the ARK server data."
        echo
        echo -e "${YELLOW}Arguments:${NC}"
        echo "  name        Optional name for the backup (default: timestamp)"
        ;;
    restore)
        echo -e "${YELLOW}Usage:${NC} $COMMAND_NAME restore [options]"
        echo "Restores the ARK server data from a backup."
        echo
        echo -e "${YELLOW}Options:${NC}"
        echo "  --list      List all available backups"
        echo "  --latest    Restore the latest backup"
        echo "  --backup N  Restore the specified backup by name or number"
        ;;
    wipe)
        echo -e "${YELLOW}Usage:${NC} $COMMAND_NAME wipe [options]"
        echo "Wipes the ARK server data."
        echo
        echo -e "${YELLOW}Options:${NC}"
        echo "  --force      Force wipe the server data"
        echo "  --help       Show help"
        ;;
    *)
        echo "No specific help available for this command."
        ;;
    esac
}

# Main function
main() {
    # No arguments provided, show help
    if equals "$#" "0"; then
        show_help
        return 0
    fi

    # Just --help without a command, show general help
    if equals "$#" "1" && (equals "$1" "--help" || equals "$1" "-h"); then
        show_help
        return 0
    fi

    local command="$1"
    shift

    # Execute the requested command
    run_command "$command" "$@"
    return $?
}

# Run the main function
main "$@"
