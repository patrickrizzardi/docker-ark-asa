#!/bin/bash
# Zip extractor utility for ARK Server Manager

source "${UTILS_PATH}/common.sh"

# Define cleanup function for trap
cleanup() {
    local exit_code=$?
    # Clean up any temporary files in case of unexpected exit
    if is_not_empty "$TEMP_ZIP_FILE" && file_exists "$TEMP_ZIP_FILE"; then
        rm -f "$TEMP_ZIP_FILE"
    fi
    exit $exit_code
}

# Set trap for cleanup
trap cleanup EXIT INT TERM

# Validate required environment variables
check_required_env REQUIRED_VARS || {
    print_error "❌ Missing required environment variables"
    exit 1
}

# Function to extract zip file using multiple methods
extract_zip() {
    local zip_file="$1"
    local destination="$2"
    local flags="$3"

    print_info "Extracting $zip_file to $destination..."

    # Ensure destination directory exists
    ensure_dir "$destination" || return 1

    # Check if file exists
    [[ ! -f "$zip_file" ]] && {
        print_error "Zip file does not exist: $zip_file"
        return 1
    }

    # Determine if we should use flatten mode
    local use_flatten=0
    if contains "$flags" "flatten"; then
        use_flatten=1
    fi

    # Try standard unzip first (with or without flatten)
    if [ $use_flatten -eq 1 ]; then
        print_info "Trying unzip with flatten option (-j)..."
        unzip -o -j "$zip_file" -d "$destination" >/dev/null 2>&1 && {
            print_success "Extraction with flatten option completed successfully"
            return 0
        }
    else
        print_info "Trying standard unzip..."
        unzip -o "$zip_file" -d "$destination" >/dev/null 2>&1 && {
            print_success "Standard extraction completed successfully"
            return 0
        }
    fi

    print_warning "First extraction attempt failed, trying alternatives..."

    # Try opposite of what was initially attempted
    if [ $use_flatten -eq 1 ]; then
        print_info "Trying standard unzip without flatten option..."
        unzip -o "$zip_file" -d "$destination" >/dev/null 2>&1 && {
            print_success "Standard extraction completed successfully"
            return 0
        }
    else
        print_info "Trying unzip with flatten option (-j)..."
        unzip -o -j "$zip_file" -d "$destination" >/dev/null 2>&1 && {
            print_success "Extraction with flatten option completed successfully"
            return 0
        }
    fi

    # Try 7z if available
    command -v 7z >/dev/null 2>&1 && {
        print_info "Trying 7z extractor..."
        7z x -o"$destination" "$zip_file" >/dev/null 2>&1 && {
            print_success "Extraction with 7z completed successfully"
            return 0
        }
    }

    # Try Python's zipfile module if available
    command -v python3 >/dev/null 2>&1 && {
        print_info "Trying Python zipfile extraction..."
        python3 -c "
import zipfile, sys, os
try:
    with zipfile.ZipFile('$zip_file', 'r') as z:
        z.extractall('$destination')
    print('Extraction with Python completed')
    sys.exit(0)
except Exception as e:
    print(f'Python extraction failed: {e}')
    sys.exit(1)
" >/dev/null 2>&1 && {
            print_success "Extraction with Python completed successfully"
            return 0
        }
    }

    # Try busybox unzip if available
    command -v busybox >/dev/null 2>&1 && {
        print_info "Trying busybox unzip..."
        busybox unzip -o "$zip_file" -d "$destination" >/dev/null 2>&1 && {
            print_success "Extraction with busybox completed successfully"
            return 0
        }
    }

    # Try jar tool if available (for Java jars which are zip files)
    command -v jar >/dev/null 2>&1 && {
        print_info "Trying Java jar tool for extraction..."
        (cd "$destination" && jar xf "$zip_file" >/dev/null 2>&1) && {
            print_success "Extraction with jar tool completed successfully"
            return 0
        }
    }

    # Try to unpack as tar.gz (in case it's mislabeled)
    command -v tar >/dev/null 2>&1 && {
        print_info "Trying to extract as tar.gz in case of mislabeling..."
        tar -xzf "$zip_file" -C "$destination" >/dev/null 2>&1 && {
            print_success "Extraction with tar (gzip) completed successfully"
            return 0
        }
    }

    # Try verbose extraction as last resort
    print_warning "All silent extraction methods failed, trying with verbose output..."

    if [ $use_flatten -eq 1 ]; then
        unzip -o -j "$zip_file" -d "$destination"
    else
        unzip -o "$zip_file" -d "$destination"
    fi

    # Check if any files were extracted regardless of exit code
    [[ "$(ls -A "$destination")" ]] && {
        print_success "Files were extracted to destination despite errors"
        return 0
    }

    # Manual file copy as absolute last resort
    print_warning "All extraction methods failed - copying zip file to destination as last resort"
    cp "$zip_file" "$destination/" || {
        print_error "Failed to even copy the zip file to destination"
        return 1
    }

    print_warning "Manual intervention may be required to extract: $destination/$(basename "$zip_file")"
    print_error "Failed to extract $zip_file using all available methods"
    return 1
}

# Function to download and extract a ZIP file from a URL
download_and_extract() {
    local url="$1"
    local destination="$2"
    local flags="$3"
    local temp_dir="${4:-/tmp}"

    # Validate required arguments
    if is_empty "$url"; then
        print_error "Missing required URL parameter for download_and_extract"
        return 1
    fi

    if is_empty "$destination"; then
        print_error "Missing required destination parameter for download_and_extract"
        return 1
    fi

    # Create temp directory if it doesn't exist
    ensure_dir "$temp_dir" || return 1

    # Generate a unique filename for the download
    TEMP_ZIP_FILE="$temp_dir/$(basename "$url").$(date +%s).zip"

    print_info "Downloading $url to $TEMP_ZIP_FILE..."

    # Try wget first
    command -v wget >/dev/null 2>&1 && {
        wget -q "$url" -O "$TEMP_ZIP_FILE" || {
            print_error "Failed to download using wget: $url"
            if file_exists "$TEMP_ZIP_FILE"; then
                rm -f "$TEMP_ZIP_FILE"
                TEMP_ZIP_FILE=""
            fi
            return 1
        }
    } || {
        # Try curl if wget not available
        command -v curl >/dev/null 2>&1 && {
            curl -s -L "$url" -o "$TEMP_ZIP_FILE" || {
                print_error "Failed to download using curl: $url"
                if file_exists "$TEMP_ZIP_FILE"; then
                    rm -f "$TEMP_ZIP_FILE"
                    TEMP_ZIP_FILE=""
                fi
                return 1
            }
        } || {
            print_error "Neither wget nor curl available for download"
            if file_exists "$TEMP_ZIP_FILE"; then
                rm -f "$TEMP_ZIP_FILE"
                TEMP_ZIP_FILE=""
            fi
            return 1
        }
    }

    # Verify file was downloaded successfully
    [[ ! -f "$TEMP_ZIP_FILE" || ! -s "$TEMP_ZIP_FILE" ]] && {
        print_error "Download failed or created empty file: $url"
        if file_exists "$TEMP_ZIP_FILE"; then
            rm -f "$TEMP_ZIP_FILE"
            TEMP_ZIP_FILE=""
        fi
        return 1
    }

    print_success "Download completed: $TEMP_ZIP_FILE"

    # Extract the zip file
    extract_zip "$TEMP_ZIP_FILE" "$destination" "$flags"
    local extract_status=$?

    # Clean up the temp file
    if file_exists "$TEMP_ZIP_FILE"; then
        rm -f "$TEMP_ZIP_FILE"
        TEMP_ZIP_FILE=""
    fi

    return $extract_status
}
