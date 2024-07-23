param (
    [string]$path
)

# Function to read key-value pairs from an INI file
function Read-Ini {
    <#
    .SYNOPSIS
        Reads key-value pairs from an INI configuration file.
    .DESCRIPTION
        Parses an INI file and sets variables in the script scope accordingly.
    .PARAMETER iniFile
        Specifies the path to the INI configuration file.
    #>

    param (
        [string]$iniFile
    )

    $section = ""
    Get-Content $iniFile | ForEach-Object {
        $line = $_.Trim()

        if ($line -eq "" -or $line.StartsWith("#")) {
            return
        }

        if ($line -match '^\[.*\]$') {
            $section = $line -replace '[\[\]]', ''
            return
        }

        if ($line -match '^[^=]+=') {
            $key, $value = $line -split '=', 2
            $key = $key.Trim()
            $value = $value.Trim()
            if ($section) {
                $key = "${section}_${key}"
            }
            Set-Variable -Name "ini_$key" -Value $value -Scope Script
        }
    }
}

# Function to display usage information
function Show-Usage {
    <#
    .SYNOPSIS
        Displays the usage information for the script.
    .DESCRIPTION
        Outputs the correct usage syntax for the script.
    #>

    Write-Host "Usage: $($MyInvocation.MyCommand.Name)"
    exit 1
}

# Function to retrieve the value associated with a key from a file
function Get-KeyValueInFile {
    <#
    .SYNOPSIS
        Retrieves the value associated with a specific key from a file.
    .DESCRIPTION
        Searches for a key-value pair in a file and returns the corresponding value.
    .PARAMETER key
        Specifies the key whose value is to be retrieved.
    .PARAMETER fileLocation
        Specifies the path to the file where the key-value pairs are stored.
    #>

    param (
        [string]$key,
        [string]$fileLocation
    )

    $value = Get-Content $fileLocation | 
    Where-Object { $_ -match "^$key=" } | 
    ForEach-Object { $_.Split('=', 2)[1] }
    return $value
}

# Function to check if a key exists in a file
function Test-KeyExistsInFile {
    <#
    .SYNOPSIS
        Checks if a key exists in a specific file.
    .DESCRIPTION
        Searches for the presence of a key in a file and returns true if found, false otherwise.
    .PARAMETER key
        Specifies the key to search for.
    .PARAMETER fileLocation
        Specifies the path to the file where the key is expected to be found.
    #>

    param (
        [string]$key,
        [string]$fileLocation
    )

    return (Select-String -Path $fileLocation -Pattern "^$key=" -Quiet)
}

# Main Script Execution

# Determine the directory path for the key vault
$KEYVAULT_DIR = if ($path) { $path } else { Join-Path $env:LOCALAPPDATA "keyvault" }
$KEYVAULT_CONFIG = Join-Path $KEYVAULT_DIR "config.ini"

# Read key-value pairs from the configuration file
Read-Ini $KEYVAULT_CONFIG

# Extract the file name from the key vault database path
$iniFile = Split-Path -Path $ini_keyvault_db -Leaf
$escapedLast = [regex]::Escape($iniFile)
$oldPath = [regex]::Replace($ini_keyvault_db, "$escapedLast$", '')
"Old path: $oldPath"

# Obtain the directory path of the current INI file
$currentIniPath = (Split-Path -Path $KEYVAULT_CONFIG -Parent) + '\'
"Ini path: $currentIniPath"

# Prompt the user to enter a new path or use the current location of the INI file
$newPath = Read-Host "Enter new path or 'enter' to use the current location of ini"

if ($newPath) {
    "New path provided"

    # Format the new path correctly
    $newPath = (Split-Path -Path (Join-Path $newPath "fakefile") -Parent) + '\'

    "Replacing: $oldPath --> $newPath"
    
    # Replace the old path with the new path in the INI file content
    $fileContent = Get-Content -Path $KEYVAULT_CONFIG
    $escapedOldPath = [regex]::Escape($oldPath)
    $newContent = $fileContent -replace $escapedOldPath, $newPath
    Set-Content -Path $KEYVAULT_CONFIG -Value $newContent
}
else {
    # Ensure a trailing backslash for the current path
    $newPath = (Split-Path -Path $KEYVAULT_CONFIG -Parent) + '\'

    "Replacing: $oldPath --> $newPath"

    # Replace the old path with the current path in the INI file content
    $fileContent = Get-Content -Path $KEYVAULT_CONFIG
    $escapedOldPath = [regex]::Escape($oldPath)
    $newContent = $fileContent -replace $escapedOldPath, $newPath
    Set-Content -Path $KEYVAULT_CONFIG -Value $newContent
}
