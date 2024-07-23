$KEYVAULT_CONFIG = "$env:LOCALAPPDATA\keyvault\config.ini"

$clipboard_duration = 30

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

# Main script
Read-Ini $KEYVAULT_CONFIG

# Prepare the list with annotation
$fzf_list = Get-Content $Script:ini_keyvault_db | ForEach-Object {
    $key, $value = $_ -split '=', 2
    $value_length = $value.Length
    $last_char = $value[-1]
    $padding = ""
    $key_type = [int]$last_char / 2

    #if ($key_type -eq 1) {
    if ((($value_length -eq 345) -or ($value_length -eq 513) -or ($value_length -eq 685)) `
            -and (($last_char -eq "2") -or ($last_char -eq "3"))) {
        "$key$padding"
    }
}

# Use fzf to select the key
$selected_key = $fzf_list | & fzf.exe --prompt="Select a key: "

# Check if a key was selected
if ($selected_key) {
    # Remove annotation from the selected key
    $clean_key = $selected_key -replace ' \(locked\)$', '' -replace ' \(TOTP\)$', ''
    
    # Get the line corresponding to the selected key
    $value = Get-KeyValueInFile $clean_key $Script:ini_keyvault_db
}
else {
    Write-Host "No key selected"
    exit 1
}

$script_path = $MyInvocation.MyCommand.Path
$script_dir = Split-Path -Parent $script_path
#$script_file = Split-Path -Leaf $script_path

# Run the get-keyvalue.ps1 in the same directory to retrieve key
$decrypted_value = & "$script_dir\get-keyvalue.ps1" $clean_key

$token = & "$script_dir\get-totp.ps1" $decrypted_value

Write-Host $token

Write-Host "Token in clipboard valid for $($((30 - (Get-Date).Second % 30))) seconds"
Set-Clipboard -Value $token

Get-Job -Name keyvault -ErrorAction SilentlyContinue | Stop-Job
Get-Job -Name keyvault -ErrorAction SilentlyContinue  | Remove-Job

