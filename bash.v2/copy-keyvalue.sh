#!/bin/bash

KEYVAULT_CONFIG="$HOME/.config/keyvault/config.ini"
clipboard_duration=30

# Function to parse INI file and export variables
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

get_key_value_in_file() {
  local key=$1
  local subkey=$2
  local file_location=$3

  local value=$(jq -r --arg key "$key" --arg subkey "$subkey" '.[$key][$subkey] // empty' "$file_location")
  printf "%s" "$value"
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
    esac
  done
}

generate_list() {
  local file_location=$1

  keys=$(jq -r 'keys[]' "$file_location")
  for key in $keys; do
    output="$key"
    messagetype=$(get_key_value_in_file "$key" "messagetype" "$file_location")
    messagekeyprot=$(get_key_value_in_file "$key" "messagekeyprot" "$file_location")

    if [ "$messagetype" == "totp" ]; then
      output+=" (TOTP)"
    fi

    if [ "$messagekeyprot" == "true" ]; then
      output+=" (locked)"
    fi

    echo "$output"
  done
}

###########

KEYVAULT_DIR="$HOME/.config/keyvault"
flag_display=false

parse_args "$@"

KEYVAULT_CONFIG="$KEYVAULT_DIR/config.ini"
parse_ini "$KEYVAULT_CONFIG"

fzf_list=$(generate_list "$ini_keyvault_db")

selected_key=$(echo -e "$fzf_list" | fzf --prompt="Select a key: ")

# Check if a key was selected
if [ -n "$selected_key" ]; then
  # Remove anotation from the selected key
  clean_key=$(echo -e "$selected_key" | sed 's/ (locked)$//g')
  clean_key=$(echo -e "$clean_key" | sed 's/ (TOTP)$//g')
  # Get the line corresponding to the selected key
  value=$(get_key_value_in_file "$clean_key" "message" $ini_keyvault_db)
else
  echo "No key selected"
  exit 1
fi

# Split the script path into directory name and file name
script_path=$(realpath "$0")
script_dir=$(dirname "$script_path")
script_file=$(basename "$script_path")

# Run the get-keyvalue.sh in the same directory to retrieve key
decrypted_value=$(${script_dir}/get-keyvalue.sh "$clean_key" "-p=${KEYVAULT_DIR}")

printf "\n"
if [ $flag_display = true ]; then
  printf "$clean_key : \n"
  printf "%s\n\n" "$decrypted_value"
else
  if [ "$decrypted_value" ]; then
    # Copy the value to the clipboard
    printf "$clean_key value available in clipboard for $clipboard_duration seconds\n\n"
    printf "%s" "$decrypted_value" | pbcopy

    (
      echo "$$" >/tmp/keyvault.pid
      sleep $clipboard_duration
      if [ -f /tmp/keyvault.pid ] &&
        [ "$(cat /tmp/keyvault.pid)" -eq "$$" ]; then
        printf "%s" "" | pbcopy
      fi
    ) &
  fi
fi


