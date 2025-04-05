#!/bin/bash
# Load utilities
source "${MANAGER_DIR}/utils/colorPrinter.sh"
source "${MANAGER_DIR}/utils/fileManager.sh"

# Set defaults
ARK_DIR=${ARK_DIR:-"/steam/steamapps/common/asa-server"}
ARK_SERVER_API_LATEST_RELEASE=${ARK_SERVER_API_LATEST_RELEASE:-"1.17"}
CDN_URL=${CDN_URL:-"https://cdn.redact.digital/ark"}

# Downloads and installs the Server API
install_server_api() {
    local latest_release="$1"

    print_info "Installing latest API ${GREEN}$latest_release"

    local tmp_zip="/tmp/AsaApi.zip"
    local tmp_dir="/tmp/AsaApi"

    # Download
    print_info "Downloading ${CDN_URL}/AsaApi_${latest_release}.zip to ${tmp_zip}..."

    if ! curl -s -L -o "$tmp_zip" "${CDN_URL}/AsaApi_${latest_release}.zip"; then
        print_error "Failed to download AsaApi_${latest_release}.zip"
        return 1
    fi

    # Ensure tmp directory exists
    mkdir -p "$tmp_dir"

    # Extract ZIP
    if ! extract_zip "$tmp_zip" "$tmp_dir"; then
        print_error "Failed to extract API zip file"
        return 1
    fi

    # Create directories
    mkdir -p "${ARK_DIR}/ShooterGame/Binaries/Win64/ArkApi/Plugins/Permissions"

    # Move files
    move_api_files "$tmp_dir"

    # Update version record
    echo "$latest_release" >"${ARK_DIR}/ShooterGame/Binaries/last_server_api_release.txt"

    print_success "API installation completed"
    return 0
}

# Moves API files from temporary directory to their final destination
move_api_files() {
    local tmp_dir="$1"

    print_info "Moving API files to final destination..."

    # Define source and destination pairs
    local -a moves=(
        "${tmp_dir}/AsaApiLoader.exe" "${ARK_DIR}/ShooterGame/Binaries/Win64/AsaApiLoader.exe"
        "${tmp_dir}/AsaApiLoader.pdb" "${ARK_DIR}/ShooterGame/Binaries/Win64/AsaApiLoader.pdb"
        "${tmp_dir}/msdia140.dll" "${ARK_DIR}/ShooterGame/Binaries/Win64/msdia140.dll"
        "${tmp_dir}/ArkApi/pdbignores.txt" "${ARK_DIR}/ShooterGame/Binaries/Win64/ArkApi/pdbignores.txt"
        "${tmp_dir}/ArkApi/Plugins/Permissions/Permissions.dll" "${ARK_DIR}/ShooterGame/Binaries/Win64/ArkApi/Plugins/Permissions/Permissions.dll"
        "${tmp_dir}/ArkApi/Plugins/Permissions/Permissions.pdb" "${ARK_DIR}/ShooterGame/Binaries/Win64/ArkApi/Plugins/Permissions/Permissions.pdb"
        "${tmp_dir}/ArkApi/AsaApi.dll" "${ARK_DIR}/ShooterGame/Binaries/Win64/ArkApi/AsaApi.dll"
        "${tmp_dir}/ArkApi/AsaApi.pdb" "${ARK_DIR}/ShooterGame/Binaries/Win64/ArkApi/AsaApi.pdb"
        "${tmp_dir}/ArkApi/Plugins/Permissions/PluginInfo.json" "${ARK_DIR}/ShooterGame/Binaries/Win64/ArkApi/Plugins/Permissions/PluginInfo.json"
    )

    # Process each file pair
    local i=0
    while [ $i -lt ${#moves[@]} ]; do
        local src="${moves[$i]}"
        local dest="${moves[$i + 1]}"

        if [ -f "$src" ]; then
            safe_move "$src" "$dest"
        else
            print_warning "Warning: Source file $src does not exist, skipping move operation"
        fi

        i=$((i + 2))
    done

    print_success "API files moved successfully"
}

# Check and update the Server API if needed
check_and_update_server_api() {
    print_info "Checking server API status..."

    if [ -f "${ARK_DIR}/ShooterGame/Binaries/Win64/AsaApiLoader.exe" ]; then
        local last_release=""
        local api_release_path="${ARK_DIR}/ShooterGame/Binaries/last_server_api_release.txt"

        if [ -f "$api_release_path" ]; then
            last_release=$(cat "$api_release_path")
        fi

        if [ "$last_release" = "$ARK_SERVER_API_LATEST_RELEASE" ]; then
            print_info "Server API is up to date: ${GREEN}$ARK_SERVER_API_LATEST_RELEASE"
            return 0
        else
            install_server_api "$ARK_SERVER_API_LATEST_RELEASE"
            return $?
        fi
    else
        install_server_api "$ARK_SERVER_API_LATEST_RELEASE"
        return $?
    fi
}
