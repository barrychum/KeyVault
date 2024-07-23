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
    local file_location=$2

    local value=$(awk -F= -v key="$key" \
        '$1 == key {print substr($0, index($0, "=") + 1)}' \
        "$file_location")
    printf "%s" "$value"
}

# Encrypt a value using RSA public key
encrypt_value() {
    local value=$1
    local public_key_path=$2
    printf "%s" "$value" |
        openssl pkeyutl -encrypt -pubin -inkey "$public_key_path" | base64
}

# Add or replace a key-value pair in sec_env
add_key_value() {
    local key=$1
    local value=$2

    # Create sec_env file if it doesn't exist
    touch "$ini_keyvault_db"

    # Check if key exists and replace its value if confirmed
    if grep -q "^$key=" "$ini_keyvault_db"; then
        echo "Key already exists. Overwrite? (yes/no)"
        read -r overwrite
        while [[ "$overwrite" != "yes" && "$overwrite" != "no" ]]; do
            echo "Invalid input. Please enter yes or no: "
            read -r overwrite
        done

        if [ "$overwrite" == "yes" ]; then
            sed -i "" "s|^$key=.*|$key=$value|" "$ini_keyvault_db"
        else
            echo "Abort"
            exit 1
        fi
    else
        echo "$key=$value" >>"$ini_keyvault_db"
    fi
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
        encrypted_value="$(encrypt_value "$value" \
            "$ini_key2048_protected_public")$padding_char"
    else
        encrypted_value="$(encrypt_value "$value" \
            "$ini_key2048_public")$padding_char"
    fi
    add_key_value "$key" "$encrypted_value"
    ;;
3072)
    if $flag_protected; then
        encrypted_value="$(encrypt_value "$value" \
            "$ini_key3072_protected_public")$padding_char"
    else
        encrypted_value="$(encrypt_value "$value" \
            "$ini_key3072_public")$padding_char"
    fi
    add_key_value "$key" "$encrypted_value"
    ;;
4096)
    if $flag_protected; then
        encrypted_value="$(encrypt_value "$value" \
            "$ini_key4096_protected_public")$padding_char"
    else
        encrypted_value="$(encrypt_value "$value" \
            "$ini_key4096_public")$padding_char"
    fi
    add_key_value "$key" "$encrypted_value"
    ;;
*)
    usage
    ;;
esac

