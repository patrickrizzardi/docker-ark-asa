#!/bin/bash

# Load utilities
UTILS_PATH="$MANAGER_DIR/utils"
source "${UTILS_PATH}/colorPrinter.sh"

# Function to extract zip file using multiple methods
extract_zip() {
    local zip_file="$1"
    local destination="$2"
    local flags="$3"
    
    print_info "Extracting $zip_file to $destination..."
    
    # Ensure destination directory exists
    mkdir -p "$destination"
    
    # Check if file exists
    if [ ! -f "$zip_file" ]; then
        print_error "Zip file does not exist: $zip_file"
        return 1
    fi
    
    # Determine if we should use flatten mode
    local use_flatten=0
    if [[ "$flags" == *"flatten"* ]]; then
        use_flatten=1
    fi
    
    # Try standard unzip first (with or without flatten)
    if [ $use_flatten -eq 1 ]; then
        print_info "Trying unzip with flatten option (-j)..."
        if unzip -o -j "$zip_file" -d "$destination" > /dev/null 2>&1; then
            print_success "Extraction with flatten option completed successfully"
            return 0
        fi
    else
        print_info "Trying standard unzip..."
        if unzip -o "$zip_file" -d "$destination" > /dev/null 2>&1; then
            print_success "Standard extraction completed successfully"
            return 0
        fi
    fi
    
    print_warning "First extraction attempt failed, trying alternatives..."
    
    # Try opposite of what was initially attempted
    if [ $use_flatten -eq 1 ]; then
        print_info "Trying standard unzip without flatten option..."
        if unzip -o "$zip_file" -d "$destination" > /dev/null 2>&1; then
            print_success "Standard extraction completed successfully"
            return 0
        fi
    else
        print_info "Trying unzip with flatten option (-j)..."
        if unzip -o -j "$zip_file" -d "$destination" > /dev/null 2>&1; then
            print_success "Extraction with flatten option completed successfully"
            return 0
        fi
    fi
    
    # Try 7z if available
    if command -v 7z >/dev/null 2>&1; then
        print_info "Trying 7z extractor..."
        if 7z x -o"$destination" "$zip_file" > /dev/null 2>&1; then
            print_success "Extraction with 7z completed successfully"
            return 0
        fi
    fi
    
    # Try Python's zipfile module if available
    if command -v python3 >/dev/null 2>&1; then
        print_info "Trying Python zipfile extraction..."
        if python3 -c "
import zipfile, sys, os
try:
    with zipfile.ZipFile('$zip_file', 'r') as z:
        z.extractall('$destination')
    print('Extraction with Python completed')
    sys.exit(0)
except Exception as e:
    print(f'Python extraction failed: {e}')
    sys.exit(1)
" > /dev/null 2>&1; then
            print_success "Extraction with Python completed successfully"
            return 0
        fi
    fi
    
    # Try busybox unzip if available
    if command -v busybox >/dev/null 2>&1; then
        print_info "Trying busybox unzip..."
        if busybox unzip -o "$zip_file" -d "$destination" > /dev/null 2>&1; then
            print_success "Extraction with busybox completed successfully"
            return 0
        fi
    fi
    
    # Try jar tool if available (for Java jars which are zip files)
    if command -v jar >/dev/null 2>&1; then
        print_info "Trying Java jar tool for extraction..."
        (cd "$destination" && jar xf "$zip_file" > /dev/null 2>&1)
        if [ $? -eq 0 ]; then
            print_success "Extraction with jar tool completed successfully"
            return 0
        fi
    fi
    
    # Try to unpack as tar.gz (in case it's mislabeled)
    if command -v tar >/dev/null 2>&1; then
        print_info "Trying to extract as tar.gz in case of mislabeling..."
        if tar -xzf "$zip_file" -C "$destination" > /dev/null 2>&1; then
            print_success "Extraction with tar (gzip) completed successfully"
            return 0
        fi
    fi
    
    # Try verbose extraction as last resort
    print_warning "All silent extraction methods failed, trying with verbose output..."
    
    if [ $use_flatten -eq 1 ]; then
        unzip -o -j "$zip_file" -d "$destination"
    else
        unzip -o "$zip_file" -d "$destination"
    fi
    
    # Check if any files were extracted regardless of exit code
    if [ "$(ls -A "$destination")" ]; then
        print_success "Files were extracted to destination despite errors"
        return 0
    fi
    
    # Manual file copy as absolute last resort
    print_warning "All extraction methods failed - copying zip file to destination as last resort"
    cp "$zip_file" "$destination/"
    print_warning "Manual intervention may be required to extract: $destination/$(basename "$zip_file")"
    
    # Consider this a failure since we couldn't properly extract
    print_error "Failed to extract $zip_file using all available methods"
    return 1
} 