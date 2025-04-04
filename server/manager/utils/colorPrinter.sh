#!/bin/bash
# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
WHITE='\033[0;37m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Function to print information messages (blue)
print_info() {
    echo -e "${BLUE}$1${NC}"
}

# Function to print success messages (green)
print_success() {
    echo -e "${GREEN}$1${NC}"
}

# Function to print warning messages (yellow)
print_warning() {
    echo -e "${YELLOW}$1${NC}"
}

# Function to print error messages (red)
print_error() {
    echo -e "${RED}$1${NC}" >&2
}

# Function to print script header with consistent format
print_script_header() {
    local title="$1"
    local char="="
    local width=80
    local padding=$(((width - ${#title} - 2) / 2))
    local line=$(printf "%${width}s" | tr " " "$char")

    echo ""
    echo "$line"
    printf "%s %s %s\n" "$(printf "%${padding}s" | tr " " "$char")" "$title" "$(printf "%${padding}s" | tr " " "$char")"
    echo "$line"
    echo ""
}
