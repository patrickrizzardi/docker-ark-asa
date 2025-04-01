#!/bin/bash

# Environment Variable Management Utility
# Provides functions to check and validate environment variables

# Load utilities
UTILS_PATH="$MANAGER_DIR/utils"
source "${UTILS_PATH}/colorPrinter.sh"

# Check if an array of environment variables are set
# Params:
#   $1 - Array of variable names to check
#   $2 - Optional flag (0 = required, 1 = optional)
# Returns:
#   0 if all required variables are set, 1 otherwise
check_env_variables() {
    local -n vars_to_check=$1
    local optional=${2:-0}
    local prefix="required"
    
    if [ "$optional" = "1" ]; then
        prefix="optional"
    fi
    
    print_info "Checking ${prefix} environment variables..."
    
    # Check each variable and collect missing ones
    local missing=0
    local missing_vars=""
    
    for var in "${vars_to_check[@]}"; do
        if [ -z "${!var}" ]; then
            if [ "$optional" = "1" ]; then
                print_warning "⚠️ Warning: Optional environment variable $var is not set"
            else
                print_error "❌ Required environment variable $var is not set"
                missing=1
                if [ -z "$missing_vars" ]; then
                    missing_vars="$var"
                else
                    missing_vars="$missing_vars, $var"
                fi
            fi
        fi
    done
    
    if [ $missing -eq 1 ] && [ "$optional" = "0" ]; then
        print_error "❌ Environment check failed: Missing required variables: ${missing_vars}"
        return 1
    fi
    
    if [ "$optional" = "0" ]; then
        print_success "✅ All required environment variables are set"
    fi
    
    return 0
}

# Sets default values for environment variables if they are not set
# Params:
#   $1 - Variable name
#   $2 - Default value
set_env_default() {
    local var_name=$1
    local default_value=$2
    
    # Only set if variable is empty
    if [ -z "${!var_name}" ]; then
        eval "${var_name}=\"${default_value}\""
    fi
}

# Exports environment variables with default values
# Params:
#   $1 - Variable name
#   $2 - Default value
export_env_default() {
    local var_name=$1
    local default_value=$2
    
    # Only set if variable is empty
    if [ -z "${!var_name}" ]; then
        export "${var_name}=${default_value}"
    fi
} 