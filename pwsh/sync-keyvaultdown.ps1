
param (
    [string]$path,
    [switch]$foreground,
    [switch]$nobackup
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
    Write-Host "Usage: $($MyInvocation.MyCommand.Name) [-foreground] [-nobackup]"
    Write-Host "run in the foreground"
    Write-Host "do not backup db file"
    exit 1
}

#############

# Main Script Execution
$KEYVAULT_DIR = if ($path) { $path } else { Join-Path $env:LOCALAPPDATA "keyvault" }
$KEYVAULT_CONFIG = Join-Path $KEYVAULT_DIR "config.ini"

Read-Ini $KEYVAULT_CONFIG

if (-not $nobackup) {
    if (Test-Path $ini_keyvault_db) {
        $NOW = Get-Date -Format "yyyyMMdd-HHmmss"
        $backupFile = "$ini_keyvault_db.$NOW"
        Move-Item -Path $ini_keyvault_db -Destination $backupFile
        $logEntry = "$(Get-Date) [INFO] backup $backupFile"
        if ($foreground) {
            $logEntry | Tee-Object -FilePath $ini_sync_log -Append
        } else {
            $logEntry | Out-File -FilePath $ini_sync_log -Append
        }
    }
}

$folderpath = Split-Path -Path $ini_keyvault_db

if ($foreground) {
    "$(Get-Date) [INFO] download started" | Tee-Object -FilePath $ini_sync_log -Append
    rclone copy $ini_sync_rclone_remote $folderpath 2>&1 | Tee-Object -FilePath $ini_sync_log -Append
    if ($LASTEXITCODE -eq 0) {
        "$(Get-Date) [INFO] download successful" | Tee-Object -FilePath $ini_sync_log -Append
    } else {
        "$(Get-Date) [ERROR] download failed" | Tee-Object -FilePath $ini_sync_log -Append
    }
} else {
    $job = Start-Job -ScriptBlock {
        "$(Get-Date) [INFO] download started" | Out-File -FilePath $using:ini_sync_log -Append
        rclone copy $using:ini_sync_rclone_remote $using:folderpath 2>&1 | Out-File -FilePath $using:ini_sync_log -Append
        if ($LASTEXITCODE -eq 0) {
            "$(Get-Date) [INFO] download successful" | Out-File -FilePath $using:ini_sync_log -Append
        } else {
            "$(Get-Date) [ERROR] download failed" | Out-File -FilePath $using:ini_sync_log -Append
        }
    }
}

