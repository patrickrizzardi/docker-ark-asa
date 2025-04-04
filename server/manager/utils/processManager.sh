#!/bin/bash
# Temporary simplified processManager.sh to fix segmentation fault

# Directly source color definitions
source "$(dirname "$0")/colorPrinter.sh"

# Get the PID of a running server process
# Params:
#   $1 - process name to check (e.g. "ArkAscendedServer.exe")
# Returns:
#   PID if found, 0 if not found
get_server_pid() {
    local process_name="$1"
    local pid=$(ps aux | grep -v grep | grep -i "${process_name}" | awk '{print $2}' | head -1)
    echo "${pid:-0}"
}

# Check if a specific server process is running
# Params:
#   $1 - process name to check (e.g. "ArkAscendedServer.exe")
# Returns:
#   0 if process is running, 1 if not
is_process_running() {
    local process_name="$1"
    local pid=$(get_server_pid "$process_name")
    [[ "$pid" != "0" ]]
}

# Get the PID of the running ARK server (either API or game server)
# Returns:
#   PID if found, 0 if not found
get_ark_server_pid() {
    # Try ArkAscendedServer.exe first
    local pid=$(get_server_pid "ArkAscendedServer.exe")
    if [[ "$pid" != "0" ]]; then
        echo "$pid"
        return 0
    fi

    # Try AsaApiLoader.exe as fallback
    pid=$(get_server_pid "AsaApiLoader.exe")
    if [[ "$pid" != "0" ]]; then
        echo "$pid"
        return 0
    fi

    echo "0"
    return 1
}

# Safely terminate a process with increasing force
# Params:
#   $1 - PID to terminate
#   $2 - Optional timeout between SIGTERM and SIGKILL (default: 30s)
# Returns:
#   0 if process was terminated, 1 if failed
safe_terminate_process() {
    local pid="$1"
    local timeout="${2:-30}"

    [[ -z "$pid" || "$pid" == "0" ]] && {
        print_warning "No valid PID provided for termination"
        return 1
    }

    # Check if process exists
    ps -p "$pid" >/dev/null || {
        print_info "Process $pid is already terminated"
        return 0
    }

    print_info "Attempting graceful termination of process $pid"

    # First try SIGTERM for graceful shutdown
    kill -15 "$pid" 2>/dev/null

    # Wait for process to terminate
    local count=0
    while [[ $count -lt $timeout ]]; do
        ps -p "$pid" >/dev/null || {
            print_success "Process $pid terminated gracefully"
            return 0
        }
        sleep 1
        ((count++))
    done

    # If still running, use SIGKILL
    print_warning "Process $pid did not terminate gracefully, forcing kill"
    kill -9 "$pid" 2>/dev/null

    # Verify process is killed
    sleep 1
    ps -p "$pid" >/dev/null && {
        print_error "Failed to terminate process $pid even with SIGKILL"
        return 1
    }

    print_success "Process $pid forcefully terminated with SIGKILL"
    return 0
}

# Get resource usage for a specific process
# Params:
#   $1 - PID to check
# Returns:
#   JSON-formatted resource usage if process exists, empty string otherwise
get_process_resources() {
    local pid="$1"

    [[ -z "$pid" || "$pid" == "0" ]] && {
        echo "{}"
        return 1
    }

    # Check if process exists
    ps -p "$pid" >/dev/null || {
        echo "{}"
        return 1
    }

    # Get CPU and memory usage
    local cpu=$(ps -p "$pid" -o %cpu= | tr -d ' ')
    local mem=$(ps -p "$pid" -o %mem= | tr -d ' ')
    local vsz=$(ps -p "$pid" -o vsz= | tr -d ' ')
    local rss=$(ps -p "$pid" -o rss= | tr -d ' ')
    local start=$(ps -p "$pid" -o start= | tr -d ' ')
    local time=$(ps -p "$pid" -o time= | tr -d ' ')
    local command=$(ps -p "$pid" -o cmd= | head -c 50)

    # Return as JSON
    echo "{ \"pid\": $pid, \"cpu\": $cpu, \"memory\": $mem, \"vsz\": $vsz, \"rss\": $rss, \"start\": \"$start\", \"time\": \"$time\", \"command\": \"$command\" }"
    return 0
}

# Wait for a process to start
# Params:
#   $1 - Process name to check (e.g. "ArkAscendedServer.exe")
#   $2 - Optional timeout in seconds (default: 60)
#   $3 - Optional check interval in seconds (default: 2)
# Returns:
#   0 if process started within timeout, 1 if not
wait_for_process_start() {
    local process_name="$1"
    local timeout="${2:-60}"
    local interval="${3:-2}"

    [[ -z "$process_name" ]] && {
        print_error "No process name provided for wait_for_process_start"
        return 1
    }

    local end_time=$(($(date +%s) + timeout))

    print_info "Waiting for process '$process_name' to start (timeout: ${timeout}s)"

    while [[ $(date +%s) -lt $end_time ]]; do
        is_process_running "$process_name" && {
            local pid=$(get_server_pid "$process_name")
            print_success "Process '$process_name' started with PID: $pid"
            return 0
        }
        sleep $interval
    done

    print_error "Timeout waiting for process '$process_name' to start"
    return 1
}

# Wait for a process to stop
# Params:
#   $1 - Process name to check or PID
#   $2 - Optional timeout in seconds (default: 60)
#   $3 - Optional check interval in seconds (default: 2)
# Returns:
#   0 if process stopped within timeout, 1 if not
wait_for_process_stop() {
    local process="$1"
    local timeout="${2:-60}"
    local interval="${3:-2}"

    [[ -z "$process" ]] && {
        print_error "No process name or PID provided for wait_for_process_stop"
        return 1
    }

    local end_time=$(($(date +%s) + timeout))
    local is_pid=0
    local pid=0

    # Check if input is a PID or process name
    if [[ "$process" =~ ^[0-9]+$ ]]; then
        is_pid=1
        pid=$process
        [[ ! -d "/proc/$pid" ]] && {
            print_info "Process with PID $pid is already stopped"
            return 0
        }
    else
        is_process_running "$process" || {
            print_info "Process '$process' is already stopped"
            return 0
        }
        pid=$(get_server_pid "$process")
    fi

    print_info "Waiting for process${is_pid:+" with PID $pid"} to stop (timeout: ${timeout}s)"

    while [[ $(date +%s) -lt $end_time ]]; do
        if [[ $is_pid -eq 1 ]]; then
            [[ ! -d "/proc/$pid" ]] && {
                print_success "Process with PID $pid stopped"
                return 0
            }
        else
            is_process_running "$process" || {
                print_success "Process '$process' stopped"
                return 0
            }
        fi
        sleep $interval
    done

    print_error "Timeout waiting for process${is_pid:+" with PID $pid"} to stop"
    return 1
}

# Get all child processes of a given PID
# Params:
#   $1 - Parent PID
# Returns:
#   Space-separated list of child PIDs
get_child_pids() {
    local parent_pid="$1"

    [[ -z "$parent_pid" || "$parent_pid" == "0" ]] && {
        echo ""
        return 1
    }

    # Check if process exists
    ps -p "$parent_pid" >/dev/null || {
        echo ""
        return 1
    }

    # Get all child PIDs
    local children=$(pgrep -P "$parent_pid" | tr '\n' ' ')
    echo "$children"
    return 0
}

# Kill a process and all its children
# Params:
#   $1 - Parent PID
#   $2 - Optional signal (default: TERM)
#   $3 - Optional timeout before SIGKILL (default: 10s)
# Returns:
#   0 if process and children were terminated, 1 if failed
kill_process_tree() {
    local parent_pid="$1"
    local signal="${2:-TERM}"
    local timeout="${3:-10}"

    [[ -z "$parent_pid" || "$parent_pid" == "0" ]] && {
        print_warning "No valid PID provided for termination"
        return 1
    }

    # Check if process exists
    ps -p "$parent_pid" >/dev/null || {
        print_info "Process $parent_pid is already terminated"
        return 0
    }

    # Get all child PIDs
    local children=$(get_child_pids "$parent_pid")

    # Kill children first
    for child in $children; do
        kill_process_tree "$child" "$signal" "$timeout"
    done

    # Now kill parent
    print_info "Terminating process $parent_pid with signal $signal"
    kill -s "$signal" "$parent_pid" 2>/dev/null

    # Wait for termination
    local count=0
    while [[ $count -lt $timeout ]]; do
        ps -p "$parent_pid" >/dev/null || {
            print_success "Process $parent_pid terminated"
            return 0
        }
        sleep 1
        ((count++))
    done

    # Force kill if still running
    print_warning "Process $parent_pid did not terminate with signal $signal, using SIGKILL"
    kill -9 "$parent_pid" 2>/dev/null

    # Verify process is killed
    sleep 1
    ps -p "$parent_pid" >/dev/null && {
        print_error "Failed to terminate process $parent_pid even with SIGKILL"
        return 1
    }

    print_success "Process $parent_pid forcefully terminated with SIGKILL"
    return 0
}
