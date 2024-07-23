#!/bin/bash

# Variables
service="${1:-KeyVault}"  # Use the first argument or default to "KeyVault"
account="private.key.password"

# Retrieve the password
password=$(security find-generic-password -s "$service" -a "$account" -w)

# Check if the retrieval was successful
if [ $? -eq 0 ];  then
    echo "Password for $service: $password"
else
    echo "Failed to retrieve the password for $service"
fi
