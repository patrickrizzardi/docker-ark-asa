# Helper function to collect missing environment variables
_collect_missing_vars() {
    local -n vars_array=$1
    local -n missing_list_ref=$2

    # Initialize missing list
    missing_list_ref=""
    local has_missing=0

    for var in "${vars_array[@]}"; do
        if [ -z "${!var}" ]; then
            has_missing=1
            if [ -z "$missing_list_ref" ]; then
                missing_list_ref="$var"
            else
                missing_list_ref="$missing_list_ref, $var"
            fi
        fi
    done

    # Return 1 if missing vars found, 0 otherwise
    return $has_missing
}

# Function to check required environment variables
check_required_env() {
    local -n vars=$1

    if [[ -z "$vars" ]]; then
        print_warning "⚠️ No required environment variables specified"
        return 0
    fi

    print_info "Checking required environment variables..."

    local missing_vars=""
    _collect_missing_vars vars missing_vars
    local missing_status=$?

    if [ $missing_status -eq 1 ]; then
        print_error "❌ Environment check failed: Missing required variables: ${missing_vars}"
        return 1
    fi

    print_success "✅ All required environment variables are set"
    return 0
}

# Function to check optional environment variables
check_optional_env() {
    local -n vars=$1

    if [[ -z "$vars" ]]; then
        return 0
    fi

    print_info "Checking optional environment variables..."

    for var in "${vars[@]}"; do
        if [ -z "${!var}" ]; then
            print_warning "⚠️ Warning: Optional environment variable $var is not set"
        fi
    done

    return 0
}
