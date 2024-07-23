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
usage() {
    echo "Usage: $0 <key> [--display]"
    echo "use -display if password is not displayed properly"
    exit 1
}

# Function to parse command-line arguments
parse_args() {
    for arg in "$@"; do
        case $arg in
        --nobackup | -n)
            flag_nobackup=true
            ;;
        --foreground | -f)
            flag_foreground=true
            ;;
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

#############

# Main Script Execution

KEYVAULT_DIR="$HOME/.config/keyvault"
flag_foreground=false
flag_nobackup=false
# Parse command-line arguments
parse_args "$@"

# Parse the configuration file
KEYVAULT_CONFIG="$KEYVAULT_DIR/config.ini"
parse_ini "$KEYVAULT_CONFIG"

if [ "$flag_nobackup" = false ]; then
    if [ -f "$ini_keyvault_db" ]; then
        NOW=$(date +"%Y%m%d-%H%M%S")
        mv "$ini_keyvault_db" "$ini_keyvault_db.$NOW"
        if [ $flag_foreground = "true" ]; then
            printf "$(date) [INFO] backup $ini_keyvault_db.$NOW\n" | tee -a "$ini_sync_log"
        else
            printf "$(date) [INFO] backup $ini_keyvault_db.$NOW\n" >>"$ini_sync_log"
        fi
    fi
fi

folderpath=$(dirname "$ini_keyvault_db")

if [ $flag_foreground = "true" ]; then
    printf "$(date) [INFO] download started\n" | tee -a "$ini_sync_log"

    rclone copy "$ini_sync_rclone_remote" "$folderpath" >>"$ini_sync_log" 2>&1
    if [[ $? -eq 0 ]]; then
        printf "$(date) [INFO] download successful\n" | tee -a "$ini_sync_log"
    else
        tail -n 1 "$ini_sync_log"
        printf "$(date) [ERROR] download failed\n" | tee -a "$ini_sync_log"
    fi
else
    (
        printf "$(date) [INFO] download started\n" >>"$ini_sync_log"
        rclone copy "$ini_sync_rclone_remote" "$folderpath" >>"$ini_sync_log" 2>&1
        if [[ $? -eq 0 ]]; then
            printf "$(date) [INFO] download successful\n" >>"$ini_sync_log"
        else
            printf "$(date) [ERROR] download failed\n" >>"$ini_sync_log"
        fi
    ) &
fi
