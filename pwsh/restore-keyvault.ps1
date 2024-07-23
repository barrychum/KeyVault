# Function to check if a file exists in the directory
function Test-ConfigIniExists {
    param (
        [string] $path
    )

    if (-not ($path -match '\S')) {
        return $false
    }

    $configIniPath = Join-Path $path "config.ini"
    Test-Path $configIniPath -PathType Leaf
}

# Function to get paths from all key-value pairs in config.ini
function Get-PathsInConfigIni {
    param (
        [string] $path
    )

    $configIniPath = Join-Path $path "config.ini"
    $content = Get-Content -Path $configIniPath

    $paths = @{}
    $section = ""

    foreach ($line in $content) {
        if ($line -match '^\[(\w+)\]$') {
            $section = $Matches[1]
            $paths[$section] = @{}
        }
        elseif ($line -match '^\s*(\w+)\s*=\s*(.*)$') {
            $key = $Matches[1]
            $value = $Matches[2].Trim()
            $paths[$section][$key] = $value
        }

        foreach ($key in $paths[$section].Keys) {
            Write-Host $key
        }

    }


    return $paths
}

# Function to prompt user for replacing paths in config.ini
function Prompt-ReplacePathsInConfig {
    param (
        [string] $currentPath,
        [string] $iniPath
    )

    Write-Host "Current path of 'config.ini': $iniPath"
    Write-Host "Path found in 'config.ini': $currentPath"
    $response = Read-Host "Paths in config.ini do not match the current directory. Do you want to replace them with the current directory? (yes/no)"
    if ($response -eq "yes") {
        return $true
    }
    else {
        return $false
    }
}

# Prompt for KeyVault path initially
$keyVaultPath = ""

# Prompt user until valid path with 'config.ini' is provided
while (-not (Test-ConfigIniExists $keyVaultPath)) {
    $keyVaultPath = Read-Host "Enter KeyVault path containing 'config.ini' (default: `$env:LOCALAPPDATA\keyvault)"

    if (-not ($keyVaultPath -match '\S')) {
        $keyVaultPath = "$env:LOCALAPPDATA\keyvault"
    }

    if (-not (Test-ConfigIniExists $keyVaultPath)) {
        Write-Host "File 'config.ini' not found in the provided path. Please try again."
    }
}

# Get paths from all key-value pairs in config.ini
$pathsInConfig = Get-PathsInConfigIni $keyVaultPath

# Get current directory of config.ini
$currentDirectory = Split-Path -Path $keyVaultPath -Parent

$configIniPath = Join-Path $keyVaultPath "config.ini"

# Check and update paths if they differ
$updatedContent = @()
foreach ($section in $pathsInConfig.Keys) {
    Write-Host "Section :$section"

    foreach ($key in $pathsInConfig[$section].Keys) {
        $iniPath = $pathsInConfig[$section][$key]
        
        #if ($iniPath -and (Split-Path $iniPath -Parent) -ne $currentDirectory) {
        if ($true -and $iniPath) {
            Write-Host "iniPath :$iniPath"

            $parentPath = Split-Path $iniPath -Parent

            if ($parentPath -ne "") {
                $parentPath = $parentPath -replace '\\', '/'
                Write-Host "parent  :$parentPath"
                Write-Host "current :$currentDirectory"
    
                $newPath = $($iniPath -replace $parentPath, $currentDirectory) -replace '\\', '/'
                $newPath = $newPath -replace '/', '\\'
                Write-Host "new     :$newPath"
    
                sed -i "s|$iniPath|$newPath|g" "$configIniPath"
            }
            Write-Host 
            pause
        }
    }
}



# Update config.ini with new paths
#$configIniPath = Join-Path $keyVaultPath "config.ini"
# $updatedContent | Set-Content -Path $configIniPath -Force

# Output the selected KeyVault path
Write-Output "Selected KeyVault path: $keyVaultPath"
