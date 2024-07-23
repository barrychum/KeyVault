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
  local file_location=$2

  local value=$(awk -F= -v key="$key" \
    '$1 == key {print substr($0, index($0, "=") + 1)}' \
    "$file_location")
  printf "%s" "$value"
}

parse_ini "$KEYVAULT_CONFIG"

# Prepare the list with anotation
fzf_list=$(awk -F= '
{
  key = $1
  value = substr($0, index($0, "=") + 1)
  value_length = length(value)
  last_char = substr(value, value_length, 1)  
  if ((value_length == 345 || \
      value_length == 513 || \
      value_length == 685) && \
      (last_char == "2" || last_char == "3" )) {
    print key             
  }
}' "$ini_keyvault_db")

# Use fzf to select the key
selected_key=$(echo -e "$fzf_list" | fzf --prompt="Select a key: ")

# Check if a key was selected
if [ -n "$selected_key" ]; then
  # Remove anotation from the selected key
  clean_key=$(echo -e "$selected_key" | sed 's/ (locked)$//g')
  # Get the line corresponding to the selected key
  value=$(get_key_value_in_file "$clean_key" $ini_keyvault_db)
else
  echo "No key selected"
  exit 1
fi

script_path=$(realpath "$0")

# Split the script path into directory name and file name
script_dir=$(dirname "$script_path")
script_file=$(basename "$script_path")

# Run the get-keyvalue.sh in the same directory to retrieve key
decrypted_value=$(${script_dir}/get-keyvalue.sh "$clean_key")

token=$(get-otp.sh "${decrypted_value}" "--batch")

unset decrypted_value

echo "Token in clipboard valids for $((30 - ($(date +%s) % 30))) seconds"
printf "%s\n" "$token"
printf "%s" "$token" | pbcopy
