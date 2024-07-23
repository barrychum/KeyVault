param (
    [switch]$display
)

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
$KEYVAULT_CONFIG = "$env:LOCALAPPDATA\keyvault\config.ini"
$clipboard_duration = 30
Read-Ini $KEYVAULT_CONFIG

# Prepare the list with annotation
$fzf_list = Get-Content $Script:ini_keyvault_db | ForEach-Object {
    $key, $value = $_ -split '=', 2
    $last_char = $value[-1]
    $padding = ""
    $key_type = [int]$last_char / 2
    if (($last_char -eq "2") -or ($last_char -eq "3")) {
        $padding = " (TOTP)"
    }
    if ([int]$last_char % 2 -eq 1) {
        $padding += " (locked)"
    }
    "$key$padding"
}

# Use fzf to select the key
$selected_key = $fzf_list | & fzf.exe --prompt="Select a key: "

# Check if a key was selected
if ($selected_key) {
    # Remove annotation from the selected key
    $clean_key = $selected_key -replace ' \(locked\)$', '' -replace ' \(TOTP\)$', ''
    
    # Get the line corresponding to the selected key
    $value = Get-KeyValueInFile $clean_key $Script:ini_keyvault_db

    $script_path = $MyInvocation.MyCommand.Path
    $script_dir = Split-Path -Parent $script_path
    #$script_file = Split-Path -Leaf $script_path

    # Run the get-keyvalue.ps1 in the same directory to retrieve key
    $decrypted_value = & "$script_dir\get-keyvalue.ps1" $clean_key

    if ($display) {
        Write-Host "$clean_key : "
        Write-Host $decrypted_value
    }
    else {
        if ($decrypted_value) {
            # Copy the value to the clipboard
            Write-Host "$clean_key value available in clipboard for $clipboard_duration seconds"
            Set-Clipboard -Value $decrypted_value

            Get-Job -Name keyvault -ErrorAction SilentlyContinue | Stop-Job
            Get-Job -Name keyvault -ErrorAction SilentlyContinue  | Remove-Job

            #write-host "Starting background job..."
            $job = Start-Job -name "keyvault" -ScriptBlock {
                param($duration)
                Start-Sleep -Seconds $duration
                Set-Clipboard -Value ""
            } -ArgumentList $clipboard_duration
        }
    }
}
else {
    Write-Host "No key selected"
    exit 1
}
