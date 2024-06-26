
$KEYVAULT_CONFIG = "$env:LOCALAPPDATA\keyvault\config.ini"

function Read-Ini {
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
    Write-Host "Usage: $($MyInvocation.MyCommand.Name) <key> <value> [-Protected] [-KeySize <2048|3072|4096>]"
    Write-Host "   or"
    Write-Host "       $($MyInvocation.MyCommand.Name) [-Interactive]"
    exit 1
}

function Get-KeyValueInFile {
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
    param (
        [string]$value,
        [string]$publicKeyPath
    )

    $tempInputFile = [System.IO.Path]::GetTempFileName()
    $tempOutputFile = [System.IO.Path]::GetTempFileName()

    try {
        [System.IO.File]::WriteAllText($tempInputFile, $value)

        # Use OpenSSL for encryption
        $opensslOutput = & openssl pkeyutl -encrypt -pubin -inkey $publicKeyPath -in $tempInputFile -out $tempOutputFile 2>&1

        if ($LASTEXITCODE -ne 0) {
            throw "OpenSSL encryption failed: $opensslOutput"
        }

        $encryptedBytes = [System.IO.File]::ReadAllBytes($tempOutputFile)
        return [Convert]::ToBase64String($encryptedBytes)
    }
    finally {
        # Clean up temporary files
        Remove-Item -Path $tempInputFile -ErrorAction SilentlyContinue
        Remove-Item -Path $tempOutputFile -ErrorAction SilentlyContinue
    }
}

function Add-KeyValue {
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
        Key = $key
        Value = $value
        KeySize = $keySize
        FlagProtected = $flagProtected
        FlagTotp = $flagTotp
    }
}

# Main script
$keySize = "2048"
$flagProtected = $false
$flagInteractive = $false
$flagTotp = $false

if ($args -contains "-i" -or $args -contains "-Interactive") {
    $params = Start-InteractiveMode
    $key = $params.Key
    $value = $params.Value
    $keySize = $params.KeySize
    $flagProtected = $params.FlagProtected
    $flagTotp = $params.FlagTotp
}
else {
    if ($args.Count -lt 2) {
        Show-Usage
    }

    $key = $args[0]
    $value = $args[1]

    for ($i = 2; $i -lt $args.Count; $i++) {
        switch ($args[$i]) {
            "-Protected" { $flagProtected = $true }
            "-KeySize" { 
                $i++
                $keySize = $args[$i]
                if ($keySize -notin @("2048", "3072", "4096")) {
                    Show-Usage
                }
            }
            default { Show-Usage }
        }
    }
}

Read-Ini $KEYVAULT_CONFIG

$secretType = if ($flagTotp) { 1 } else { 0 }
$padding = $secretType * 2
if ($flagProtected) { $padding++ }
$paddingChar = [string]$padding

switch ($keySize) {
    "2048" {
        $publicKeyPath = if ($flagProtected) { $Script:ini_key2048_protected_public } else { $Script:ini_key2048_public }
    }
    "3072" {
        $publicKeyPath = if ($flagProtected) { $Script:ini_key3072_protected_public } else { $Script:ini_key3072_public }
    }
    "4096" {
        $publicKeyPath = if ($flagProtected) { $Script:ini_key4096_protected_public } else { $Script:ini_key4096_public }
    }
    default { Show-Usage }
}

# Ensure the path is in the correct format for OpenSSL
$publicKeyPath = $publicKeyPath -replace '\\', '/'

$encryptedValue = "$(Encrypt-Value $value $publicKeyPath)$paddingChar"
Add-KeyValue $key $encryptedValue