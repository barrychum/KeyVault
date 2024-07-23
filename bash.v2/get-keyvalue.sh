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

# Retrieve a key's value from a file
get_key_value_in_file() {
    local key=$1
    local subkey=$2
    local file_location=$3

    local value=$(jq -r --arg key "$key" --arg subkey "$subkey" '.[$key][$subkey] // empty' "$file_location")
    printf "%s" "$value"
}

# Function to read a password with asterisks and handle backspace/delete
read_password() {
    local password=""
    local char=""

    # Turn off echoing
    stty -echo

    while IFS= read -r -s -n 1 char; do
        # Enter key is pressed (ASCII 10, 13 or Null)
        if [[ $char == $'\n' || $char == $'\r' || $char == $'\x0' ]]; then
            break
        fi

        # Backspace is pressed (ASCII 127 or 8)
        if [[ $char == $'\x7f' || $char == $'\b' ]]; then
            if [ -n "$password" ]; then
                # Remove the last character from password
                password=${password%?}
                # Move cursor back, overwrite with space, move cursor back again
                printf "\b \b" >&2
            fi
        else
            # Add the character to password
            password+="$char"
            # Print an asterisk
            printf "*" >&2
        fi
    done

    # Turn echoing back on
    stty echo
    printf "\n" >&2
    printf "%s" "$password"
}

# Function to retrieve a password from the keychain or prompt the user
get_password() {
    # Retrieve the password from the keychain if available
    keychain_password=$(security find-generic-password -s "$ini_keychain_service" -a "$ini_keychain_account" -w)
    if [ $? -eq 0 ]; then
        echo "Private key password obtained from keychain" >&2
        printf "%s" "$keychain_password"
    else
        # Prompt the user to enter the private key password
        echo "Private key password not in keychain. Please enter private key password: " >&2
        userinput=$(read_password)
        echo >&2
        printf "%s" "$userinput"
    fi
}

# Function to check if a key exists in a file
key_exist_in_file() {
    local key=$1
    local file_location=$2

    grep -q "^${key}=" "$file_location" || return 1
    return 0
}

# Function to decrypt a value using a private key
decrypt_value() {
    local encrypted_value="$1"
    local private_key="$2"
    local private_key_protected="$3"

    if $private_key_protected == "true"; then
        local private_key_password=$(get_password)
        printf "%s" "$encrypted_value" | base64 --decode |
            openssl pkeyutl -decrypt -inkey "$private_key" -passin pass:"$private_key_password"
    else
        printf "%s" "$encrypted_value" | base64 --decode |
            openssl pkeyutl -decrypt -inkey "$private_key"
    fi

}

# Function to parse command-line arguments
parse_args() {
    for arg in "$@"; do
        case $arg in
        --display | -d)
            flag_display=true
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
flag_display=false

# Parse command-line arguments
parse_args "$@"

# Parse the configuration file
KEYVAULT_CONFIG="$KEYVAULT_DIR/config.ini"
parse_ini "$KEYVAULT_CONFIG"

# Check if the mandatory argument is provided
if [ -z "$1" ]; then
    usage
fi
key=$1

# Determine display format based on flag
if [ $flag_display = true ]; then
    display_format="%s\n"
else
    display_format="%s"
fi

value=$(get_key_value_in_file "$key" "message" "$ini_keyvault_db")
if [ -n "$value" ]; then
    valuekey=$(get_key_value_in_file "$key" "messagekey" "$ini_keyvault_db")
    privatekey="$ini_keyvault_keys/${valuekey/%_public.pem/_private.pem}"
    privatekeyprotection=$(get_key_value_in_file "$key" "messagekeyprot" "$ini_keyvault_db")

    printf "$display_format" "$(decrypt_value "$value" "$privatekey" "$privatekeyprotection")"
fi
