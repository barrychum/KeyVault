#!/bin/bash

# Function to parse an INI file and set variables
parse_ini() {
    local ini_file="$1"
    local section=""
    local line
    while IFS= read -r line; do
        # Remove leading and trailing whitespaces
        local line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

        # Skip empty lines and comments
        if [[ -z "$line" || "$line" =~ ^# ]]; then
            continue
        fi

        # Handle section headers
        if [[ "$line" =~ ^\[.*\]$ ]]; then
            local section=$(echo "$line" | sed 's/\[\(.*\)\]/\1/')
            continue
        fi

        # Handle key-value pairs
        if [[ "$line" =~ ^[^=]+=[^=]+$ ]]; then
            local key=$(echo "$line" | cut -d '=' -f 1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            local value=$(echo "$line" | cut -d '=' -f 2- | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            if [[ -n "$section" ]]; then
                local key="${section}_${key}"
            fi
            export "ini_$key"="$value"
        fi
    done <"$ini_file"
}

# Function to display usage information
show_usage() {
    echo "Usage: $0"
    exit 1
}

# Function to retrieve the value associated with a key from a file
get_key_value_in_file() {
    local key="$1"
    local file_location="$2"
    
    grep "^$key=" "$file_location" | cut -d'=' -f2-
}

# Function to check if a key exists in a file
test_key_exists_in_file() {
    local key="$1"
    local file_location="$2"
    
    grep -q "^$key=" "$file_location"
}

# Function to parse command-line arguments
parse_args() {
    for arg in "$@"; do
        case $arg in
        --path=* | -p=*)
            KEYVAULT_DIR="${arg#*=}"
            ;;
        --help | -h)
            usage
            exit 1
            ;;
        esac
    done
}

# Main Script Execution

# Determine the directory path for the key vault
KEYVAULT_DIR="$HOME/.config/keyvault"

# Parse command-line arguments
parse_args "$@"

# Read key-value pairs from the configuration file
KEYVAULT_CONFIG="$KEYVAULT_DIR/config.ini"
parse_ini "$KEYVAULT_CONFIG"

# Extract the file name from the key vault database path
ini_file=$(echo "$ini_keyvault_db" | sed -E 's/.*[\/\\]//')
old_path=$(echo "$ini_keyvault_db" | sed "s|$ini_file$||")
echo "Old path: $old_path"

# Obtain the directory path of the current INI file
current_ini_path=$(dirname "$KEYVAULT_CONFIG")
echo "Ini path: $current_ini_path"

# Prompt the user to enter a new path or use the current location of the INI file
read -p "Enter new path or press Enter to use the current location of ini: " new_path

if [ -n "$new_path" ]; then
    echo "New path provided"
    # Ensure the new path ends with a separator (/ or \)
    new_path=$(echo "$new_path" | sed 's|[/\\]*$|/|')
    echo "Replacing: $old_path --> $new_path"
else
    new_path=$(dirname "$KEYVAULT_CONFIG")/
    echo "Replacing: $old_path --> $new_path"
fi

# Replace the old path with the new path in the INI file content
awk -v old="$old_path" -v new="$new_path" '{gsub(old, new)}1' "$KEYVAULT_CONFIG" > tmpfile && mv tmpfile "$KEYVAULT_CONFIG"

