<#
.SYNOPSIS
    Decrypts and retrieves a sensitive value stored in a key vault configuration file.
.DESCRIPTION
    This script decrypts encrypted values stored in an INI file-based key vault. It supports decryption of both protected and unprotected values.
.PARAMETER key
    Specifies the key whose value needs to be decrypted and retrieved from the key vault.
.PARAMETER path
    Specifies the directory path where the configuration files are stored. Defaults to $env:LOCALAPPDATA\keyvault.
.NOTES
    - Requires OpenSSL to be installed and accessible from the system's PATH environment variable.
    - Assumes INI files for key configurations are present and accessible.
.EXAMPLE
    Decrypts and displays a value from the key vault:
    PS C:\> .\Decrypt-SensitiveData.ps1 "myKey"
#>

param (
    [Parameter(Position = 0, Mandatory = $true)]
    [string]$key,
    [string]$path
)

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

    Write-Host "Usage: $($MyInvocation.MyCommand.Name) <key>"
    Write-Host "   or"
    Write-Host "       $($MyInvocation.MyCommand.Name) <key> [-display]"
    Write-Host "Use -display if password is not displayed properly"
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

function Read-SecurePassword {
    <#
    .SYNOPSIS
        Prompts the user to enter a password securely.
    .DESCRIPTION
        Reads and returns a secure string password input from the user.
    #>

    $securePassword = Read-Host "Enter a password:" -AsSecureString
    $password = ConvertFrom-SecureString $securePassword -AsPlainText
    return $password
}

function Get-Password {
    <#
    .SYNOPSIS
        Retrieves the private key password either from Credential Manager or prompts the user to enter it.
    .DESCRIPTION
        Tries to fetch the private key password from Credential Manager. If not found, prompts the user for input.
    #>

    # Try to get the password from Windows Credential Manager
    $credential = Get-StoredCredential -Target "$Script:ini_keychain_service" | Where-Object { $_.username -eq "$Script:ini_keychain_account" }
    if ($credential) {
        Write-Host "Private key password obtained from Credential Manager" -ForegroundColor Yellow
        return ConvertFrom-SecureString -SecureString $credential.password -AsPlainText
    }
    else {
        Write-Host "Private key password not in Credential Manager. Please enter private key password: " -ForegroundColor Yellow
        return Read-SecurePassword
    }
}

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

function Decrypt-Value {
    <#
    .SYNOPSIS
        Decrypts a value using OpenSSL.
    .DESCRIPTION
        Decrypts a base64-encoded encrypted value using OpenSSL and returns the plaintext result.
    .PARAMETER encryptedValue
        Specifies the base64-encoded value to be decrypted.
    .PARAMETER privateKey
        Specifies the path to the private key file used for decryption.
    #>

    param (
        [string]$encryptedValue,
        [string]$privateKey
    )

    $bytes = [Convert]::FromBase64String($encryptedValue)

    # Use PowerShell's pipeline to send data directly to openssl and capture the output
    $result = $bytes | openssl pkeyutl -decrypt -inkey $privateKey | Out-String

    return $result.Trim()
}

function Decrypt-ProtectedValue {
    <#
    .SYNOPSIS
        Decrypts a password-protected value using OpenSSL.
    .DESCRIPTION
        Decrypts a base64-encoded encrypted value that requires a password for decryption.
    .PARAMETER encryptedValue
        Specifies the base64-encoded value to be decrypted.
    .PARAMETER privateKey
        Specifies the path to the private key file used for decryption.
    .PARAMETER privateKeyPass
        Specifies the password required to decrypt the private key.
    #>

    param (
        [string]$encryptedValue,
        [string]$privateKey,
        [string]$privateKeyPass
    )

    $bytes = [Convert]::FromBase64String($encryptedValue)

    # Use PowerShell's pipeline to send data directly to openssl and capture the output
    $result = $bytes | openssl pkeyutl -decrypt -inkey $privateKey -passin "pass:$privateKeyPass" | Out-String

    return $result.Trim()
}

# Main Script Execution
$KEYVAULT_DIR = if ($path) { $path } else { Join-Path $env:LOCALAPPDATA "keyvault" }
$KEYVAULT_CONFIG = Join-Path $KEYVAULT_DIR "config.ini"

Read-Ini $KEYVAULT_CONFIG

if (-not $key) { Show-Usage }

if (Test-KeyExistsInFile $key $Script:ini_keyvault_db) {
    $value = Get-KeyValueInFile $key $Script:ini_keyvault_db
    $messageLength = $value.Length - 1
    $var1 = $value.Substring(0, $messageLength)
    $var2 = [int]$value[$messageLength]

    $isEncrypted = $var2 % 2

    switch ($messageLength) {
        { $_ -in 1..9 } { Write-Host "Input string is too short." }
        344 {
            if ($isEncrypted -eq 0) {
                $decrypted = Decrypt-Value $var1 $Script:ini_key2048_private
            }
            else {
                $privateKeyPassword = Get-Password
                $decrypted = Decrypt-ProtectedValue $var1 $Script:ini_key2048_protected_private $privateKeyPassword
            }
            $decrypted
        }
        512 {
            if ($isEncrypted -eq 0) {
                $decrypted = Decrypt-Value $var1 $Script:ini_key3072_private
            }
            else {
                $privateKeyPassword = Get-Password
                $decrypted = Decrypt-ProtectedValue $var1 $Script:ini_key3072_protected_private $privateKeyPassword
            }
            $decrypted
        }
        684 {
            if ($isEncrypted -eq 0) {
                $decrypted = Decrypt-Value $var1 $Script:ini_key4096_private
            }
            else {
                $privateKeyPassword = Get-Password
                $decrypted = Decrypt-ProtectedValue $var1 $Script:ini_key4096_protected_private $privateKeyPassword
            }
            $decrypted
        }
        default { Write-Host "Invalid length: $messageLength" }
    }
}
else {
    Write-Host -NoNewline ""
}
