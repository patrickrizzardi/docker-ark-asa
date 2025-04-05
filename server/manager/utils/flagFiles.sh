#!/bin/bash

source "$MANAGER_DIR/utils/colorPrinter.sh"

# Function to check if the server is running
flag_exists() {
    local flag="$1"
    local flag_file="${ARK_DIR}/${flag}.flag"
    local stale_minutes=${2:-30} # Default to 30 minutes for stale detection

    _verify_flag_names "$flag" || exit 1

    if file_exists "$flag_file"; then
        # Check if the flag file is stale (older than specified minutes)
        if [[ $(find "$flag_file" -mmin +${stale_minutes} -print 2>/dev/null) ]]; then
            print_warning "⚠️ Found stale ${flag} lock file, removing it"
            rm -f "$flag_file"
            return 1
        fi
        return 0
    fi
    return 1
}

# A function to create the flag file
create_flag() {
    local flag="$1"
    local flag_file="${ARK_DIR}/${flag}.flag"

    _verify_flag_names "$flag" || exit 1

    touch "$flag_file"
    print_info "Created flag file: $flag_file"
}

# A function to remove the flag file
remove_flag() {
    local flag="$1"
    local flag_file="${ARK_DIR}/${flag}.flag"

    _verify_flag_names "$flag" || exit 1

    rm -f "$flag_file"
}

# A function to get the age of a flag file in minutes
get_flag_age() {
    local flag="$1"
    local flag_file="${ARK_DIR}/${flag}.flag"

    _verify_flag_names "$flag" || exit 1

    if ! file_exists "$flag_file"; then
        echo "0"
        return 1
    fi

    local current_time=$(date +%s)
    local file_time=$(stat -c %Y "$flag_file")
    local age_seconds=$((current_time - file_time))
    local age_minutes=$((age_seconds / 60))

    echo "$age_minutes"
    return 0
}

# A helper function to verify the flag names that are used to check if the server is running
_verify_flag_names() {
    local valid_flags=("start" "update" "restart" "stop" "save" "first_launch_recovery_completed", "shutdown")
    local flag="$1"

    for valid_flag in "${valid_flags[@]}"; do
        if [[ "$flag" == "$valid_flag" ]]; then
            return 0
        fi
    done

    print_error "Invalid flag name: $flag. Accepted options are: ${valid_flags[*]}"
    return 1
}
