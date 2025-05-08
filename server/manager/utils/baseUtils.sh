#!/bin/bash

# ARK Server Base Utilities
# Fundamental utility functions used across multiple scripts

# =============================================================================
# STRING UTILITIES
# =============================================================================

# Check if a variable is empty
# Returns 0 (true) if empty, 1 (false) if not
# Example usage:
# if is_empty "$var"; then
#     echo "Variable is empty"
# fi
is_empty() { [[ -z "$1" ]]; }

# Check if a variable is not empty
# Returns 0 (true) if not empty, 1 (false) if empty
# Example usage:
# if is_not_empty "$var"; then
#     echo "Variable has content"
# fi
is_not_empty() { [[ -n "$1" ]]; }

# Check if a variable equals a value
# Returns 0 (true) if equal, 1 (false) if not
# Example usage:
# if equals "$var" "value"; then
#     echo "Variable equals value"
# fi
equals() { [[ "$1" == "$2" ]]; }

# Check if a variable does not equal a value
# Returns 0 (true) if not equal, 1 (false) if equal
# Example usage:
# if does_not_equal "$var" "value"; then
#     echo "Variable does not equal value"
# fi
does_not_equal() { [[ "$1" != "$2" ]]; }

# Check if a variable contains a substring
# Returns 0 (true) if contains, 1 (false) if not
# Example usage:
# if contains "$var" "substring"; then
#     echo "Variable contains substring"
# fi
contains() { [[ "$1" == *"$2"* ]]; }

# Check if a variable does not contain a substring
# Returns 0 (true) if does not contain, 1 (false) if contains
# Example usage:
# if does_not_contain "$var" "substring"; then
#     echo "Variable does not contain substring"
# fi
does_not_contain() { [[ "$1" != *"$2"* ]]; }

# =============================================================================
# FILE UTILITIES
# =============================================================================

# Check if a file exists
# Returns 0 (true) if file exists, 1 (false) if it doesn't
# Example usage:
# if file_exists "/path/to/file.txt"; then
#     echo "File exists"
# fi
file_exists() {
    [[ -f "$1" ]]
    return $?
}

# Check if a file does not exist
# Returns 0 (true) if file doesn't exist, 1 (false) if it does
# Example usage:
# if file_does_not_exist "/path/to/file.txt"; then
#     echo "File does not exist"
# fi
file_does_not_exist() {
    [[ ! -f "$1" ]]
    return $?
}

# Check if a directory exists
# Returns 0 (true) if directory exists, 1 (false) if it doesn't
# Example usage:
# if dir_exists "/path/to/directory"; then
#     echo "Directory exists"
# fi
dir_exists() {
    [[ -d "$1" ]]
    return $?
}

# Check if a directory does not exist
# Returns 0 (true) if directory does not exist, 1 (false) if it does
# Example usage:
# if dir_does_not_exist "/path/to/directory"; then
#     echo "Directory does not exist"
# fi
dir_does_not_exist() {
    [[ ! -d "$1" ]]
    return $?
}

# Check if a file is executable
# Returns 0 (true) if executable, 1 (false) if not
# Example usage:
# if is_executable "/path/to/script.sh"; then
#     echo "File is executable"
# fi
is_executable() { [[ -x "$1" ]]; }

# Check if a file is not executable
# Returns 0 (true) if not executable, 1 (false) if it is
# Example usage:
# if is_not_executable "/path/to/script.sh"; then
#     echo "File is not executable"
# fi
is_not_executable() { [[ ! -x "$1" ]]; }

# Check if a file is readable
# Returns 0 (true) if readable, 1 (false) if not
# Example usage:
# if is_readable "/path/to/file.txt"; then
#     echo "File is readable"
# fi
is_readable() { [[ -r "$1" ]]; }

# Check if a file is not readable
# Returns 0 (true) if not readable, 1 (false) if it is
# Example usage:
# if is_not_readable "/path/to/file.txt"; then
#     echo "File is not readable"
# fi
is_not_readable() { [[ ! -r "$1" ]]; }

# Check if a file is writable
# Returns 0 (true) if writable, 1 (false) if not
# Example usage:
# if is_writable "/path/to/file.txt"; then
#     echo "File is writable"
# fi
is_writable() { [[ -w "$1" ]]; }

# Check if a file is not writable
# Returns 0 (true) if not writable, 1 (false) if it is
# Example usage:
# if is_not_writable "/path/to/file.txt"; then
#     echo "File is not writable"
# fi
is_not_writable() { [[ ! -w "$1" ]]; }

# Check if a file is empty
# Returns 0 (true) if empty, 1 (false) if not
# Example usage:
# if is_empty_file "/path/to/file.txt"; then
#     echo "File is empty"
# fi
is_empty_file() { [[ -s "$1" ]]; }

# Check if a file is not empty
# Returns 0 (true) if not empty, 1 (false) if it is
# Example usage:
# if is_not_empty_file "/path/to/file.txt"; then
#     echo "File is not empty"
# fi
is_not_empty_file() { [[ ! -s "$1" ]]; }

# =============================================================================
# COMMAND UTILITIES
# =============================================================================

# Execute a command and capture both stdout and stderr
# Returns the command's exit code
# Example usage:
# result=$(capture_all_output ark rcon "ListPlayers" --silent)
# exit_code=$?
# if [ $exit_code -ne 0 ]; then
#     echo "Command failed with: $result"
# fi
capture_all_output() {
    "$@" 2>&1
    return $?
}
