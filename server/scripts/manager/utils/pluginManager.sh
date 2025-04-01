#!/bin/bash

# ARK Server Plugin Management Utility
# Provides functions to check, download, and install plugins

# Load utilities
UTILS_PATH="$MANAGER_DIR/utils"
source "${UTILS_PATH}/colorPrinter.sh"
source "${UTILS_PATH}/zipExtractor.sh"

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
    
    # Make sure the destination directory exists
    mkdir -p "$destination"
    
    # Backup existing config files
    for config_file in ${PLUGIN_CONFIG_FILES[$plugin_name]}; do
        if [ -f "${destination}/${config_file}" ]; then
            print_info "Backing up ${config_file}"
            cp "${destination}/${config_file}" "/tmp/${config_file}.bak"
        fi
    done
    
    # Prepare download URL and temp file
    local download_url="${url}/${plugin_name}_${latest_release}.zip"
    local tmp_file="/tmp/${plugin_name}.zip"
    
    # Download the plugin
    print_info "Downloading ${plugin_name} version ${latest_release} from ${download_url}..."
    
    curl -s -L -o "$tmp_file" "$download_url" || {
        print_error "Failed to download plugin from ${download_url}"
        return 1
    }
    
    # Clean destination directory but keep backups
    rm -rf "${destination}"
    mkdir -p "${destination}"
    
    local install_success=1
    
    # Use TurretManagerFREE-specific extraction with flatten
    if [ "$plugin_name" = "TurretManagerFREE" ]; then
        print_info "Using 'flatten' option for TurretManagerFREE extraction..."
        if extract_zip "$tmp_file" "$destination" "flatten"; then
            install_success=0
        fi
    else
        # Use regular extraction for other plugins
        if extract_zip "$tmp_file" "$destination"; then
            install_success=0
        fi
    fi
    
    # If standard extraction failed, try alternative URL for TurretManagerFREE
    if [ $install_success -eq 1 ] && [ "$plugin_name" = "TurretManagerFREE" ]; then
        print_info "Trying alternative URL for TurretManagerFREE..."
        local alt_url="${url}/TurretManagerFREE.zip"
        
        curl -s -L -o "$tmp_file" "$alt_url" || {
            print_error "Failed to download plugin from alternative URL ${alt_url}"
            # Continue to restore configs even if download failed
        }
        
        # Try extraction with flatten option again
        if extract_zip "$tmp_file" "$destination" "flatten"; then
            install_success=0
        fi
    fi
    
    # Clean up the temporary file
    rm -f "$tmp_file"
    
    # Restore config files
    for config_file in ${PLUGIN_CONFIG_FILES[$plugin_name]}; do
        if [ -f "/tmp/${config_file}.bak" ]; then
            print_info "Restoring ${config_file}"
            cp "/tmp/${config_file}.bak" "${destination}/${config_file}"
            rm "/tmp/${config_file}.bak"
        fi
    done
    
    # Save version information if successful
    if [ $install_success -eq 0 ]; then
        echo "$latest_release" > "${destination}/last_${plugin_name}_release.txt"
        print_success "${plugin_name} updated to ${latest_release}"
        return 0
    else
        print_error "Failed to install ${plugin_name}"
        return 1
    fi
}

# Install or update all plugins
# Params:
#   $1 - ARK_DIR - The ARK server directory
install_plugins() {
    local ark_dir="$1"
    
    if [ -z "$ark_dir" ]; then
        print_error "ARK_DIR is not set or is empty"
        return 1
    fi
    
    print_header "🔌 Installing/Updating plugins..."
    
    # Make sure the plugins directory exists
    local plugins_base_dir="${ark_dir}/ShooterGame/Binaries/Win64/ArkApi/Plugins"
    mkdir -p "$plugins_base_dir"
    
    # Track failures
    local failures=0
    
    # Install each plugin
    for plugin in "${!PLUGIN_VERSIONS[@]}"; do
        local plugin_version="${PLUGIN_VERSIONS[$plugin]}"
        local plugin_dir="${plugins_base_dir}/${plugin}"
        
        # Check if plugin is already up-to-date
        local last_release_file="${plugin_dir}/last_${plugin}_release.txt"
        local last_release=""
        
        if [ -f "$last_release_file" ]; then
            last_release=$(cat "$last_release_file")
        fi
        
        # Compare versions
        if [ "$last_release" = "$plugin_version" ]; then
            print_success "${plugin} is up to date: ${GREEN}${plugin_version}${NC}"
        else
            print_info "Installing/Updating ${plugin} from ${last_release} to ${plugin_version}..."
            if install_plugin "$plugin" "$plugin_version" "$CDN_URL" "$plugin_dir"; then
                print_success "✅ ${plugin} updated to ${GREEN}${plugin_version}${NC}"
            else
                print_error "❌ Failed to install/update ${plugin}"
                ((failures++))
            fi
        fi
    done
    
    if [ $failures -eq 0 ]; then
        print_header "✅ All plugins installed/updated successfully"
        return 0
    else
        print_header "⚠️ Some plugins failed to install/update: $failures"
        return $failures
    fi
} 