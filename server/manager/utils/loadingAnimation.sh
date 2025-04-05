#!/bin/bash
#
# ARK Server Loading Animation Utilities
# Provides clean spinner animation functions for all ARK server scripts
#
# =============================================================================

# Import color definitions if not already available
source "${MANAGER_DIR}/utils/colorPrinter.sh"

# =============================================================================
# SPINNER CONFIGURATION
# =============================================================================

# Initialize spinner variables with dots style (Braille pattern)
SPINNER=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
SPINNER_COLOR="${CYAN}"
SPINNER_DELAY_MS=100 # Delay in milliseconds (was 0.1 seconds)
SPINNER_IDX=0
LAST_SPIN_TIME=0

# =============================================================================
# SPINNER FUNCTIONS
# =============================================================================

# Internal function to show a single frame of the spinner
_show_spinner() {
    local message="$1"
    local now

    # Get current time in milliseconds (compatible with both GNU and BSD date)
    if date +%s%N >/dev/null 2>&1; then
        # Linux with nanoseconds support
        now=$(date +%s%N | cut -b1-13)
    else
        # macOS/BSD without nanoseconds
        now=$(($(date +%s) * 1000))
    fi

    # Only update spinner if enough time has passed
    if ((now - LAST_SPIN_TIME >= SPINNER_DELAY_MS)); then
        local current_spinner=${SPINNER[$SPINNER_IDX]}
        SPINNER_IDX=$(((SPINNER_IDX + 1) % ${#SPINNER[@]}))
        printf "\r${SPINNER_COLOR}${current_spinner}${NC} ${message}   "
        LAST_SPIN_TIME=$now
    fi
}

# Combined loading function that handles both command execution and status display
# Usage:
#   loading "command" "Loading message"   - Run a command with spinner and capture output
#   loading "Status message"              - Just show a spinner with a message (for loops)
# This is useful when you don't know the percentage of the progress, the show_progress function is better for known progress
loading() {
    # If two arguments are provided, treat it as command execution mode
    if [ $# -eq 2 ]; then
        local command="$1"
        local message="$2"

        # Create temporary file for output
        local tmp_out=$(mktemp)

        # Start command in background
        eval "$command" >"$tmp_out" 2>&1 &
        local cmd_pid=$!

        # Track start time for elapsed time display
        local start_time=$(date +%s)

        # Show spinner while command runs
        while kill -0 $cmd_pid 2>/dev/null; do
            local elapsed=$(($(date +%s) - start_time))
            _show_spinner "${message} (${elapsed}s)"
            sleep 0.05
        done

        # Clear spinner line
        printf "\r%-80s\r" ""

        # Get command exit status
        wait $cmd_pid
        local status=$?

        # Capture output
        SPINNER_OUTPUT=$(<"$tmp_out")
        rm -f "$tmp_out"

        # Only display completion message if not in silent mode
        if does_not_equal "$COMMON_SILENT" "true"; then
            if equals "$status" "0"; then
                echo -e "${GREEN}✅ ${message} completed${NC}"
            else
                echo -e "${RED}❌ ${message} failed${NC}"
            fi
        fi

        # Output the command result to stdout so it can be captured by command substitution
        echo "$SPINNER_OUTPUT"

        return $status

    # If one argument is provided, treat it as status display mode
    elif [ $# -eq 1 ]; then
        local message="$1"
        _show_spinner "$message"
    fi
}

# Display a progress bar
# Usage: show_progress 45 "Copying files"
# This is useful when you know the percentage of the progress, the loading_output function is better for unknown progress
show_progress() {
    local percent=$1
    local message=$2
    local width=40

    # Calculate how many progress bar characters to show
    local progress_width=$((percent * width / 100))

    # Build the progress bar
    local progress_bar=""
    for ((i = 0; i < width; i++)); do
        if ((i < progress_width)); then
            progress_bar+="█"
        else
            progress_bar+="░"
        fi
    done

    # Display the progress bar
    printf "\r[${GREEN}${progress_bar}${NC}] ${percent}%% ${message}"
}
