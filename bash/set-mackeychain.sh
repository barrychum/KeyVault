#!/bin/bash

# Function to prompt for password and confirmation
prompt_password() {
    while true; do
        read -s -p "Enter password: " password
        echo
        read -s -p "Confirm password: " password_confirm
        echo

        if [ "$password" == "$password_confirm" ]; then
            break
        else
            echo "Passwords do not match. Please try again."
        fi
    done
}

# Variables
service="KeyVault"
account="private.key.password"

# Prompt the user for the password
prompt_password

# Save the key-value pair to the keychain
security add-generic-password -s "$service" -a "$account" -w "$password" \
-j "use by keyvault application" -U

# Check if the saving was successful
if [ $? -eq 0 ]; then
    echo "Password for $service has been saved successfully."
else
    echo "Failed to save the password for $service."
fi

