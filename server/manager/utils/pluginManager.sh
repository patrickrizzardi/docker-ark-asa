#!/bin/bash

# ARK Server Plugin Management Utility
# Provides functions to check, download, and install plugins

UTILS_PATH="$MANAGER_DIR/utils"
source "${UTILS_PATH}/common.sh"

# Required environment variables
declare -a REQUIRED_VARS=(
    "MANAGER_DIR" # Manager directory
)

# Define cleanup function for trap
cleanup() {
    local exit_code=$?
    # Clean up any temporary files
    [[ -n "$TMP_PLUGIN_FILE" && -f "$TMP_PLUGIN_FILE" ]] && rm -f "$TMP_PLUGIN_FILE"
    # Clean up any backup files
    for cfg in "${PLUGIN_CONFIG_BACKUPS[@]}"; do
        [[ -f "$cfg" ]] && rm -f "$cfg"
    done
    exit $exit_code
}

# Set trap for cleanup
trap cleanup EXIT INT TERM

# Validate required environment variables
check_required_env REQUIRED_VARS || {
    print_error "❌ Missing required environment variables"
    exit 1
}

# Set default CDN URL if not already set
CDN_URL=${CDN_URL:-"https://cdn.redact.digital/ark"}

# Plugin definitions with their latest versions and additional files
declare -A PLUGIN_VERSIONS=(
    ["ArkShop"]="1.06"
    ["TurretManagerFREE"]="1.08"
    ["AdvancedMessagesAscended"]="1.2"
)

# Additional configuration files to preserve for each plugin
declare -A PLUGIN_CONFIG_FILES=(
    ["ArkShop"]="config.json Commented.json"
    ["TurretManagerFREE"]="config.json"
    ["AdvancedMessagesAscended"]="config.json config_help.json"
)

# Array to track backup files (used for cleanup)
PLUGIN_CONFIG_BACKUPS=()

# Simple function to install a plugin, no fancy stuff
# Params:
#   $1 - Plugin name
#   $2 - Latest release version
#   $3 - URL
#   $4 - Destination directory
install_plugin() {
    local plugin_name="$1"
    local latest_release="$2"
    local url="$3"
    local destination="$4"

    # Validate required parameters
    [[ -z "$plugin_name" ]] && {
        print_error "Missing plugin name parameter"
        return 1
    }

    [[ -z "$latest_release" ]] && {
        print_error "Missing version parameter for plugin $plugin_name"
        return 1
    }

    [[ -z "$url" ]] && {
        print_error "Missing URL parameter for plugin $plugin_name"
        return 1
    }

    [[ -z "$destination" ]] && {
        print_error "Missing destination parameter for plugin $plugin_name"
        return 1
    }

    # Make sure the destination directory exists
    ensure_dir "$destination" || {
        print_error "Failed to create destination directory: $destination"
        return 1
    }

    # Reset the backup array for this plugin
    PLUGIN_CONFIG_BACKUPS=()

    # Backup existing config files
    for config_file in ${PLUGIN_CONFIG_FILES[$plugin_name]}; do
        [[ -f "${destination}/${config_file}" ]] && {
            print_info "Backing up ${config_file}"
            local backup_file="/tmp/${plugin_name}_${config_file}.bak"
            cp "${destination}/${config_file}" "$backup_file" || {
                print_warning "Failed to backup ${config_file}, continuing anyway"
                continue
            }
            PLUGIN_CONFIG_BACKUPS+=("$backup_file")
        }
    done

    # Prepare download URL and temp file
    local download_url="${url}/${plugin_name}_${latest_release}.zip"
    TMP_PLUGIN_FILE="/tmp/${plugin_name}_${latest_release}.zip"

    # Download the plugin
    print_info "Downloading ${plugin_name} version ${latest_release} from ${download_url}..."

    curl -s -L -o "$TMP_PLUGIN_FILE" "$download_url" || {
        print_error "Failed to download plugin from ${download_url}"
        return 1
    }

    # Clean destination directory but keep backups
    rm -rf "${destination}"
    ensure_dir "${destination}" || {
        print_error "Failed to recreate destination directory: $destination"
        return 1
    }

    local install_success=1

    # Use TurretManagerFREE-specific extraction with flatten
    if [[ "$plugin_name" = "TurretManagerFREE" ]]; then
        print_info "Using 'flatten' option for TurretManagerFREE extraction..."
        extract_zip "$TMP_PLUGIN_FILE" "$destination" "flatten" && install_success=0
    else
        # Use regular extraction for other plugins
        extract_zip "$TMP_PLUGIN_FILE" "$destination" && install_success=0
    fi

    # If standard extraction failed, try alternative URL for TurretManagerFREE
    [[ $install_success -eq 1 && "$plugin_name" = "TurretManagerFREE" ]] && {
        print_info "Trying alternative URL for TurretManagerFREE..."
        local alt_url="${url}/TurretManagerFREE.zip"

        curl -s -L -o "$TMP_PLUGIN_FILE" "$alt_url" || {
            print_error "Failed to download plugin from alternative URL ${alt_url}"
            # Continue to restore configs even if download failed
        }

        # Try extraction with flatten option again
        extract_zip "$TMP_PLUGIN_FILE" "$destination" "flatten" && install_success=0
    }

    # Clean up the temporary file
    rm -f "$TMP_PLUGIN_FILE"
    TMP_PLUGIN_FILE=""

    # Restore config files
    for config_file in ${PLUGIN_CONFIG_FILES[$plugin_name]}; do
        local backup_file="/tmp/${plugin_name}_${config_file}.bak"
        [[ -f "$backup_file" ]] && {
            print_info "Restoring ${config_file}"
            cp "$backup_file" "${destination}/${config_file}" || {
                print_warning "Failed to restore ${config_file}"
            }
            rm -f "$backup_file"
            # Remove from the backup array
            for i in "${!PLUGIN_CONFIG_BACKUPS[@]}"; do
                [[ "${PLUGIN_CONFIG_BACKUPS[i]}" = "$backup_file" ]] && {
                    unset 'PLUGIN_CONFIG_BACKUPS[i]'
                    break
                }
            done
        }
    done

    # Save version information if successful
    [[ $install_success -eq 0 ]] && {
        echo "$latest_release" >"${destination}/last_${plugin_name}_release.txt"
        print_success "${plugin_name} updated to ${latest_release}"
        return 0
    }

    print_error "Failed to install ${plugin_name}"
    return 1
}

# Check if a plugin is already installed and up to date
# Params:
#   $1 - Plugin name
#   $2 - Latest version
#   $3 - Plugin directory
# Returns:
#   0 if plugin is up to date, 1 if needs update/install
is_plugin_up_to_date() {
    local plugin="$1"
    local latest_version="$2"
    local plugin_dir="$3"

    [[ -z "$plugin" || -z "$latest_version" || -z "$plugin_dir" ]] && return 1

    # Check if plugin directory exists
    [[ ! -d "$plugin_dir" ]] && return 1

    # Check if plugin is already up-to-date
    local last_release_file="${plugin_dir}/last_${plugin}_release.txt"
    [[ ! -f "$last_release_file" ]] && return 1

    local last_release=$(cat "$last_release_file")
    [[ "$last_release" = "$latest_version" ]] && return 0

    return 1
}

# Install or update all plugins
# Params:
#   $1 - ARK_DIR - The ARK server directory
install_plugins() {
    local ark_dir="$1"

    [[ -z "$ark_dir" ]] && {
        print_error "ARK_DIR is not set or is empty"
        return 1
    }

    [[ ! -d "$ark_dir" ]] && {
        print_error "ARK directory does not exist: $ark_dir"
        return 1
    }

    print_script_header "Installing/Updating Plugins"

    # Make sure the plugins directory exists
    local plugins_base_dir="${ark_dir}/ShooterGame/Binaries/Win64/ArkApi/Plugins"
    ensure_dir "$plugins_base_dir" || {
        print_error "Failed to create plugins directory: $plugins_base_dir"
        return 1
    }

    # Track failures
    local failures=0
    local success_count=0
    local already_updated=0

    # Install each plugin
    for plugin in "${!PLUGIN_VERSIONS[@]}"; do
        local plugin_version="${PLUGIN_VERSIONS[$plugin]}"
        local plugin_dir="${plugins_base_dir}/${plugin}"

        # Check if plugin is already up-to-date
        is_plugin_up_to_date "$plugin" "$plugin_version" "$plugin_dir" && {
            print_success "${plugin} is up to date: ${plugin_version}"
            ((already_updated++))
            continue
        }

        # Get current version if available
        local last_release=""
        local last_release_file="${plugin_dir}/last_${plugin}_release.txt"
        [[ -f "$last_release_file" ]] && last_release=$(cat "$last_release_file")

        # Install/update plugin
        print_info "Installing/Updating ${plugin} from ${last_release:-'not installed'} to ${plugin_version}..."

        install_plugin "$plugin" "$plugin_version" "$CDN_URL" "$plugin_dir" && {
            print_success "✅ ${plugin} updated to ${plugin_version}"
            ((success_count++))
        } || {
            print_error "❌ Failed to install/update ${plugin}"
            ((failures++))
        }
    done

    [[ $failures -eq 0 ]] && {
        local count=$((success_count + already_updated))
        local msg="All plugins processed successfully"
        [[ $already_updated -gt 0 ]] && msg="${msg} (${already_updated} already up-to-date)"
        [[ $success_count -gt 0 ]] && msg="${msg} (${success_count} updated)"
        print_success "✅ ${msg}"
        return 0
    }

    print_warning "⚠️ Some plugins failed to install/update: $failures out of ${#PLUGIN_VERSIONS[@]}"
    return $failures
}

# Install a specific plugin by name
# Params:
#   $1 - ARK_DIR - The ARK server directory
#   $2 - Plugin name
install_specific_plugin() {
    local ark_dir="$1"
    local plugin_name="$2"

    [[ -z "$ark_dir" ]] && {
        print_error "ARK_DIR is not set or is empty"
        return 1
    }

    [[ -z "$plugin_name" ]] && {
        print_error "Plugin name is not specified"
        return 1
    }

    [[ ! -d "$ark_dir" ]] && {
        print_error "ARK directory does not exist: $ark_dir"
        return 1
    }

    # Check if plugin exists in the definitions
    [[ -z "${PLUGIN_VERSIONS[$plugin_name]}" ]] && {
        print_error "Unknown plugin: $plugin_name"
        print_info "Available plugins: ${!PLUGIN_VERSIONS[*]}"
        return 1
    }

    # Get plugin version
    local plugin_version="${PLUGIN_VERSIONS[$plugin_name]}"

    # Make sure the plugins directory exists
    local plugins_base_dir="${ark_dir}/ShooterGame/Binaries/Win64/ArkApi/Plugins"
    local plugin_dir="${plugins_base_dir}/${plugin_name}"

    ensure_dir "$plugins_base_dir" || {
        print_error "Failed to create plugins directory: $plugins_base_dir"
        return 1
    }

    print_script_header "Installing/Updating Plugin: $plugin_name"

    # Check if plugin is already up-to-date
    is_plugin_up_to_date "$plugin_name" "$plugin_version" "$plugin_dir" && {
        print_success "${plugin_name} is already up to date: ${plugin_version}"
        return 0
    }

    # Get current version if available
    local last_release=""
    local last_release_file="${plugin_dir}/last_${plugin_name}_release.txt"
    [[ -f "$last_release_file" ]] && last_release=$(cat "$last_release_file")

    # Install/update plugin
    print_info "Installing/Updating ${plugin_name} from ${last_release:-'not installed'} to ${plugin_version}..."

    install_plugin "$plugin_name" "$plugin_version" "$CDN_URL" "$plugin_dir" && {
        print_success "✅ ${plugin_name} updated to ${plugin_version}"
        return 0
    }

    print_error "❌ Failed to install/update ${plugin_name}"
    return 1
}

# List all available plugins and their status
# Params:
#   $1 - ARK_DIR - The ARK server directory
list_plugins() {
    local ark_dir="$1"

    [[ -z "$ark_dir" ]] && {
        print_error "ARK_DIR is not set or is empty"
        return 1
    }

    [[ ! -d "$ark_dir" ]] && {
        print_error "ARK directory does not exist: $ark_dir"
        return 1
    }

    print_script_header "Available Plugins"

    # Make sure the plugins directory exists
    local plugins_base_dir="${ark_dir}/ShooterGame/Binaries/Win64/ArkApi/Plugins"
    local header_printed=0

    # Table header
    printf "%-25s %-12s %-12s %-12s\n" "Plugin Name" "Latest" "Installed" "Status"
    printf "%-25s %-12s %-12s %-12s\n" "$(printf '%0.s-' {1..25})" "$(printf '%0.s-' {1..12})" "$(printf '%0.s-' {1..12})" "$(printf '%0.s-' {1..12})"

    # List each plugin
    for plugin in "${!PLUGIN_VERSIONS[@]}"; do
        local plugin_version="${PLUGIN_VERSIONS[$plugin]}"
        local plugin_dir="${plugins_base_dir}/${plugin}"
        local installed_version="Not installed"
        local status="Not installed"

        # Check if plugin directory exists
        [[ -d "$plugin_dir" ]] && {
            # Check if version file exists
            local last_release_file="${plugin_dir}/last_${plugin}_release.txt"
            [[ -f "$last_release_file" ]] && {
                installed_version=$(cat "$last_release_file")
                [[ "$installed_version" == "$plugin_version" ]] && status="Up to date" || status="Needs update"
            } || {
                status="Unknown"
            }
        }

        printf "%-25s %-12s %-12s %-12s\n" "$plugin" "$plugin_version" "$installed_version" "$status"
    done

    return 0
}
