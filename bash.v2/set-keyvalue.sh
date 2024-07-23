#!/bin/bash

# Display usage information
usage() {
    printf "Usage: $0 <key> <value> \n"
    printf "          [--protected|-p]\n"
    printf "          [--key|-k=<2048|3072|4096>]\n"
    printf "          [--path|-p=<installation path>]\n"
    printf "          [--totp]\n"
    printf "    or\n"
    printf "       $0 <-i|--interactive>\n\n"
    exit 1
}

# Parse command-line arguments
parse_args() {
    for arg in "$@"; do
        case $arg in
        --protected | -p)
            flag_protected=true
            ;;
        --interactive | -i)
            flag_interactive=true
            ;;
        --path=* | -p=*)
            KEYVAULT_DIR="${arg#*=}"
            ;;
        --key=* | -k=*)
            key_size="${arg#*=}"
            ;;
        --type=* | -t=*)
            message_type="${arg#*=}"
            ;;
        --totp)
            flag_totp=true
            ;;
        --help | -h)
            usage
            exit 1
            ;;
        esac
    done
}

# Parse configuration from INI file
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

# Retrieve a key's value from a file
get_key_value_in_file() {
    local key=$1
    local subkey=$2
    local file_location=$3

    local value=$(jq -r --arg key "$key" --arg subkey "$subkey" '.[$key][$subkey] // empty' "$file_location")
    printf "%s" "$value"
}

# Encrypt a value using RSA public key
encrypt_value() {
    local value=$1
    local public_key_path=$2
    printf "%s" "$value" |
        openssl pkeyutl -encrypt -pubin -inkey "$public_key_path" | base64
}

# Add or replace a key-value pair
add_key_value() {
    local parent=$1
    local subkey=$2
    local value=$3
    local file_location=$4

    # Create the JSON file if it doesn't exist
    if [ ! -f "$file_location" ]; then
        echo "{}" >"$file_location"
    fi

    # Read the content of the JSON file into a variable
    local json_content
    json_content=$(cat "$file_location")

    # Initialize the parent if it doesn't exist or isn't an object
    json_content=$(printf "%s" "$json_content" |
        jq --arg parent "$parent" 'if .[$parent] == null then .[$parent] = {} elif .[$parent] | type != "object" then error("Parent key is not an object") else . end')

    if [ $? -ne 0 ]; then
        echo "Error: Parent key is not an object." >&2
        return 1
    fi

    # Check if the subkey exists under the parent
    if printf "%s" "$json_content" | jq -e --arg parent "$parent" --arg subkey "$subkey" '.[$parent] | has($subkey)' >/dev/null; then
        echo "Subkey already exists under parent. Overwrite? (yes/no)" >&2
        read -r overwrite
        while [[ "$overwrite" != "yes" && "$overwrite" != "no" ]]; do
            echo "Invalid input. Please enter yes or no: " >&2
            read -r overwrite
        done

        if [ "$overwrite" == "yes" ]; then
            # Add the new subkey-value pair under the parent
            json_content=$(printf "%s" "$json_content" |
                jq --arg parent "$parent" --arg subkey "$subkey" --arg value "$value" '.[$parent][$subkey] = $value')
            # Save the updated JSON content back to the file
            printf "%s" "$json_content" >"$file_location"
            echo "Key value updated successfully." >&2
            return 0
        else
            echo "Operation aborted." >&2
            return 1
        fi
    else
        # Add the new subkey-value pair under the parent
        json_content=$(printf "%s" "$json_content" |
            jq --arg parent "$parent" --arg subkey "$subkey" --arg value "$value" '.[$parent][$subkey] = $value')
        # Save the updated JSON content back to the file
        printf "%s" "$json_content" >"$file_location"
        echo "Key value added successfully." >&2
        return 0
    fi
}

add_key_value_force() {
    local parent=$1
    local subkey=$2
    local value=$3
    local file_location=$4

    # Create the JSON file if it doesn't exist
    if [ ! -f "$file_location" ]; then
        echo "{}" >"$file_location"
    fi

    # Read the content of the JSON file into a variable
    local json_content
    json_content=$(cat "$file_location")

    # Initialize the parent if it doesn't exist or isn't an object
    json_content=$(printf "%s" "$json_content" | jq --arg parent "$parent" 'if .[$parent] == null then .[$parent] = {} elif .[$parent] | type != "object" then error("Parent key is not an object") else . end')

    if [ $? -ne 0 ]; then
        echo "Error: Parent key is not an object." >&2
        return 1
    fi

    # Add the new subkey-value pair under the parent
    json_content=$(printf "%s" "$json_content" | jq --arg parent "$parent" --arg subkey "$subkey" --arg value "$value" '.[$parent][$subkey] = $value')

    # Save the updated JSON content back to the file
    printf "%s" "$json_content" >"$file_location"
    return 0
}

# Interactive mode for user input
interactive_mode() {
    # Prompt user for key
    echo -n "Enter key: "
    read key

    # Prompt user for value
    echo -n "Enter value for '$key': "
    read value

    # Prompt user for key size
    echo -n "Enter key size (2048, 3072, 4096): "
    read key_size

    # Validate key size input (optional)
    while [[ ! "$key_size" =~ ^(2048|3072|4096)$ ]]; do
        echo -n "Invalid key size. Please enter 2048, 3072, or 4096: "
        read key_size
    done

    # Prompt user for password protection
    echo -n "Do you want to use password protected keys? (yes/no): "
    read flag

    # Validate flag input (optional)
    while [[ "$flag" != "yes" && "$flag" != "no" ]]; do
        echo -n "Invalid input. Please enter 'yes' or 'no': "
        read flag
    done

    # Convert flag to boolean
    if [[ "$flag" == "yes" ]]; then
        flag_protected=true
    else
        flag_protected=false
    fi

    # Prompt user for TOTP usage
    echo -n "Is this used by One Time Password? (yes/no): "
    read flag

    # Validate flag input (optional)
    while [[ "$flag" != "yes" && "$flag" != "no" ]]; do
        echo -n "Invalid input. Please enter 'yes' or 'no': "
        read flag
    done

    # Convert flag to boolean
    if [[ "$flag" == "yes" ]]; then
        flag_totp=true
    else
        flag_totp=false
    fi
}

##### Main Script Execution #####

KEYVAULT_DIR="$HOME/.config/keyvault"
key_size="2048"        # Default key size
flag_protected=false   # Default to non-protected private key
flag_interactive=false # Default to non-interactive mode
flag_totp=false        # Default to non-TOTP usage
message_type="string"

# Parse command-line arguments
parse_args "$@"

KEYVAULT_CONFIG="$KEYVAULT_DIR/config.ini"
parse_ini "$KEYVAULT_CONFIG"

# Determine execution mode: interactive or command-line
if [ $flag_interactive = true ]; then
    interactive_mode
else
    # Check if there are at least two arguments provided
    if [ "$#" -lt 2 ]; then
        echo "Insufficient arguments provided."
        usage
    else
        key=$1
        value=$2
    fi
fi

# Determine secret type (plain or TOTP)
if [ $flag_totp = true ]; then
    secret_type=1
    message_type="totp"
else
    secret_type=0
fi

# Calculate padding based on secret type and key protection
padding=$((secret_type * 2))
if $flag_protected; then
    ((padding = padding + 1))
fi
padding_char=$(printf "%s" "$padding")

# Encrypt and store value based on specified key size
case "$key_size" in
2048)
    if $flag_protected; then
        encryption_key="$ini_key2048_protected_public"
    else
        encryption_key="$ini_key2048_public"
    fi
    ;;
3072)
    if $flag_protected; then
        encryption_key="$ini_key3072_protected_public"
    else
        encryption_key="$ini_key3072_public"
    fi
    ;;
4096)
    if $flag_protected; then
        encryption_key="$ini_key4096_protected_public"
    else
        encryption_key="$ini_key4096_public"
    fi
    ;;
*)
    usage
    ;;
esac
#encrypted_value="$(encrypt_value "$value" "$encryption_key")$padding_char"
encrypted_value="$(encrypt_value "$value" "$encryption_key")"
add_key_value "$key" "message" "$encrypted_value" "$ini_keyvault_db"
if [ $? -eq 0 ]; then
    add_key_value_force "$key" "messagetype" "$message_type" "$ini_keyvault_db"
    add_key_value_force "$key" "messagekey" "$(basename "$encryption_key")" "$ini_keyvault_db"
    add_key_value_force "$key" "messagekeyprot" "$flag_protected" "$ini_keyvault_db"
fi
