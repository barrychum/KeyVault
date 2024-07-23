
param (
    [string]$path,
    [switch]$foreground
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

# Function to display usage information
function Usage {
    Write-Host "Usage: $($MyInvocation.MyCommand.Name) [-foreground]"
    Write-Host "run in the foreground"
    exit 1
}

#############

# Main Script Execution
$KEYVAULT_DIR = if ($path) { $path } else { Join-Path $env:LOCALAPPDATA "keyvault" }
$KEYVAULT_CONFIG = Join-Path $KEYVAULT_DIR "config.ini"

Read-Ini $KEYVAULT_CONFIG

if ($foreground) {
    "$(Get-Date) [INFO] upload started" | Tee-Object -FilePath $ini_sync_log -Append
    rclone copy $ini_keyvault_db $ini_sync_rclone_remote 2>&1 | Tee-Object -FilePath $ini_sync_log -Append
    if ($LASTEXITCODE -eq 0) {
        "$(Get-Date) [INFO] upload successful" | Tee-Object -FilePath $ini_sync_log -Append
    } else {
        "$(Get-Date) [ERROR] upload failed" | Tee-Object -FilePath $ini_sync_log -Append
    }
} else {
    $job = Start-Job -ScriptBlock {
        "$(Get-Date) [INFO] upload started" | Out-File -FilePath $using:ini_sync_log -Append
        rclone copy $using:ini_keyvault_db $using:ini_sync_rclone_remote 2>&1 | Out-File -FilePath $using:ini_sync_log -Append
        if ($LASTEXITCODE -eq 0) {
            "$(Get-Date) [INFO] upload successful" | Out-File -FilePath $using:ini_sync_log -Append
        } else {
            "$(Get-Date) [ERROR] upload failed" | Out-File -FilePath $using:ini_sync_log -Append
        }
    }
}
