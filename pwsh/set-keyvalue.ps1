<#
.SYNOPSIS
    Encrypts sensitive data and stores it securely in a key vault configuration file.
.DESCRIPTION
    This script facilitates the encryption and storage of sensitive information using OpenSSL for encryption and INI files for configuration storage.
    It supports both interactive and parameterized modes for flexibility in usage.
.PARAMETER key
    Specifies the key under which the encrypted value will be stored in the key vault.
.PARAMETER value
    Specifies the sensitive data to be encrypted and stored.
.PARAMETER path
    Specifies the directory path where the configuration files are stored. Defaults to $env:LOCALAPPDATA\keyvault.
.PARAMETER protected
    Switch parameter. When specified, indicates that the encryption key should be password-protected.
.PARAMETER interactive
    Switch parameter. When specified, prompts the user for input interactively.
.PARAMETER keySize
    Specifies the size of the encryption key. Allowed values are 2048, 3072, or 4096 bits. Defaults to 2048 bits.
.PARAMETER totp
    Switch parameter. When specified, indicates that the value is used for One Time Password.
.NOTES
    - Requires OpenSSL to be installed and accessible from the system's PATH environment variable.
    - Assumes INI files for key configurations are present and accessible.
.EXAMPLE
    Encrypts and stores a value in the key vault:
    PS C:\> .\Encrypt-SensitiveData.ps1 "myKey" "mySecret" -protected -keySize 3072
.EXAMPLE
    Runs the script in interactive mode:
    PS C:\> .\Encrypt-SensitiveData.ps1 -Interactive
#>

param (
    [Parameter(Position = 0)]
    [string]$key,
    [Parameter(Position = 1)]
    $value,
    [string]$path,
    [switch]$protected,
    [switch]$interactive,
    $keySize = "2048",
    [switch]$totp
)

$KEYVAULT_DIR = if ($path) { $path } else { Join-Path $env:LOCALAPPDATA "keyvault" }
$KEYVAULT_CONFIG = Join-Path $KEYVAULT_DIR "config.ini"

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

function Show-Usage {
    <#
    .SYNOPSIS
        Displays usage instructions for the script.
    .DESCRIPTION
        Shows how to use the script with examples of valid command syntax.
    #>

    Write-Host "Usage: $($MyInvocation.MyCommand.Name) <key> <value> [-protected] [-keySize <2048|3072|4096>]"
    Write-Host "   or"
    Write-Host "       $($MyInvocation.MyCommand.Name) [-Interactive]"
    exit 1
}

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

function Encrypt-Value {
    <#
    .SYNOPSIS
        Encrypts a given value using OpenSSL.
    .DESCRIPTION
        Encrypts a string value using OpenSSL and returns the encrypted value as a base64-encoded string.
    .PARAMETER value
        Specifies the value to be encrypted.
    .PARAMETER publicKeyPath
        Specifies the path to the public key file used for encryption.
    #>

    param (
        [string]$value,
        [string]$publicKeyPath
    )

    try {
        $inputBytes = [System.Text.Encoding]::UTF8.GetBytes($value)

        # Capturing stdout from openssl fails
        # use a temp file to capture encrypted data
        # the temporary file is removed to reduced risk
        $tempOutputFile = (New-TemporaryFile).Fullname
        $inputBytes | openssl pkeyutl -encrypt -pubin -inkey $publicKeyPath -out $tempOutputFile 
        $encryptedBytes = [System.IO.File]::ReadAllBytes($tempOutputFile)

        return [Convert]::ToBase64String($encryptedBytes)
    }
    finally {
        Remove-Item -Path $tempOutputFile -ErrorAction SilentlyContinue
    }
}

function Add-KeyValue {
    <#
    .SYNOPSIS
        Adds or updates a key-value pair in the key vault configuration file.
    .DESCRIPTION
        Checks if the key already exists in the configuration file. If yes, prompts the user to overwrite or abort.
        If no, adds the new key-value pair to the configuration file.
    .PARAMETER key
        Specifies the key under which the value will be stored.
    .PARAMETER value
        Specifies the encrypted value to be stored.
    #>

    param (
        [string]$key,
        [string]$value
    )

    if (!(Test-Path $Script:ini_keyvault_db)) {
        New-Item -Path $Script:ini_keyvault_db -ItemType File -Force
    }

    $content = Get-Content $Script:ini_keyvault_db
    $keyExists = $content | Where-Object { $_ -match "^$key=" }

    if ($keyExists) {
        $overwrite = Read-Host "Key already exists. Overwrite? (yes/no)"
        while ($overwrite -notin @("yes", "no")) {
            $overwrite = Read-Host "Invalid input. Please enter yes or no"
        }

        if ($overwrite -eq "yes") {
            $content = $content -replace "^$key=.*", "$key=$value"
            $content | Set-Content $Script:ini_keyvault_db
        }
        else {
            Write-Host "Abort"
            exit 1
        }
    }
    else {
        Add-Content -Path $Script:ini_keyvault_db -Value "$key=$value"
    }
}

function Start-InteractiveMode {
    <#
    .SYNOPSIS
        Enters interactive mode to prompt the user for key vault configuration details.
    .DESCRIPTION
        Prompts the user to enter the key, value, key size, and other flags interactively.
    #>

    $key = Read-Host "Enter key"
    $value = Read-Host "Enter value for '$key'"
    $keySize = Read-Host "Enter key size (2048, 3072, 4096)"

    while ($keySize -notin @("2048", "3072", "4096")) {
        $keySize = Read-Host "Invalid key size. Please enter 2048, 3072, or 4096"
    }

    $flagProtected = Read-Host "Do you want to use password protected keys? (yes/no)"
    while ($flagProtected -notin @("yes", "no")) {
        $flagProtected = Read-Host "Invalid input. Please enter 'yes' or 'no'"
    }
    $flagProtected = ($flagProtected -eq "yes")

    $flagTotp = Read-Host "Is this used by One Time Password? (yes/no)"
    while ($flagTotp -notin @("yes", "no")) {
        $flagTotp = Read-Host "Invalid input. Please enter 'yes' or 'no'"
    }
    $flagTotp = ($flagTotp -eq "yes")

    return @{
        Key           = $key
        Value         = $value
        KeySize       = $keySize
        FlagProtected = $flagProtected
        FlagTotp      = $flagTotp
    }
}

# Main script

if ($interactive) {
    $params = Start-InteractiveMode
    $key = $params.Key
    $value = $params.Value
    $keySize = $params.KeySize
    $protected = $params.FlagProtected
    $totp = $params.FlagTotp
}
else {
    if ( (-not $key) -or (-not $value)) {
        Show-Usage
    }

}

Read-Ini $KEYVAULT_CONFIG

$secretType = if ($totp) { 1 } else { 0 }
$padding = $secretType * 2
if ($protected) { $padding++ }
$paddingChar = [string]$padding

switch ($keySize) {
    "2048" {
        $publicKeyPath = if ($protected) { $Script:ini_key2048_protected_public } else { $Script:ini_key2048_public }
    }
    "3072" {
        $publicKeyPath = if ($protected) { $Script:ini_key3072_protected_public } else { $Script:ini_key3072_public }
    }
    "4096" {
        $publicKeyPath = if ($protected) { $Script:ini_key4096_protected_public } else { $Script:ini_key4096_public }
    }
    default { Show-Usage }
}

# Ensure the path is in the correct format for OpenSSL
### $publicKeyPath = $publicKeyPath -replace '\\', '/'

$encryptedValue = "$(Encrypt-Value $value $publicKeyPath)$paddingChar"
Add-KeyValue $key $encryptedValue
