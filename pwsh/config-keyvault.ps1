param (
    [switch]$demo,
    [string]$path,
    [string]$rclone,
    [switch]$help
)

# Define the KeyVault environment variables
$KEYVAULT_DIR = if ($path) { $path } else { Join-Path $env:LOCALAPPDATA "keyvault" }
$RCLONE_REMOTE = $rclone
$KEYVAULT_CONFIG = Join-Path $KEYVAULT_DIR "config.ini"
$KEYVAULT_DB = Join-Path $KEYVAULT_DIR "keyvault.db"
$KEYVAULT_KEYS = Join-Path $KEYVAULT_DIR "keys"
$KEYVAULT_LOG = Join-Path $KEYVAULT_DIR "sync.log"

# Function to display usage information
function Usage {
    Write-Host "Usage : $($MyInvocation.MyCommand.Name) [--demo|-d] [--path|-p <path to installation>] [--rclone <rclone remote>] [--help|-h]"
    Write-Host "`nExample : $($MyInvocation.MyCommand.Name) -p $env:LOCALAPPDATA\test -d"
    exit 1
}

# Check if help is requested
if ($help) {
    Usage
}

# Function to prompt for password protection
function Prompt-PasswordProtection {
    Write-Host "Do you want the private key to be password protected? (strongly recommended):"
    $password_protected = Read-Host "(yes/no)"

    while ($password_protected -ne "yes" -and $password_protected -ne "no") {
        $password_protected = Read-Host "Invalid input. Please enter yes or no"
    }

    if ($password_protected -eq "yes") {
        $password1 = Read-Host "Enter a password for the private key" -AsSecureString
        $password2 = Read-Host "Confirm the password for the private key" -AsSecureString
        
        while (-not (CompareSecureString $password1 $password2)) {
            Write-Host "Passwords do not match. Please try again."
            $password1 = Read-Host "Enter a password for the private key" -AsSecureString
            $password2 = Read-Host "Confirm the password for the private key" -AsSecureString
        }
    }
    else {
        $password1 = $null
    }

    return $password_protected, $password1
}

# Function to compare two SecureString objects
function CompareSecureString([System.Security.SecureString]$ss1, [System.Security.SecureString]$ss2) {
    return (ConvertFrom-SecureString $ss1 -AsPlainText) -eq (ConvertFrom-SecureString $ss2 -AsPlainText)
}

# Function to create the KeyVault directories
function Setup-Directories {
    New-Item -ItemType Directory -Path $KEYVAULT_DIR -Force | Out-Null
    New-Item -ItemType Directory -Path $KEYVAULT_KEYS -Force | Out-Null
    $acl = Get-Acl $KEYVAULT_KEYS
    $acl.SetAccessRuleProtection($true, $false)
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule($env:USERNAME, "FullControl", "Allow")
    $acl.SetAccessRule($rule)
    Set-Acl $KEYVAULT_KEYS $acl
}

# Function to generate the key pair
function Generate-Keys {
    param(
        [int]$key_length,
        [string]$password_protected,
        [string]$key_location,
        [System.Security.SecureString]$password
    )

    if ($password_protected -eq "yes") {
        $private_key_filename = "KeyVault_${key_length}_protected_private.pem"
        $public_key_filename = "KeyVault_${key_length}_protected_public.pem"
    }
    else {
        $private_key_filename = "KeyVault_${key_length}_private.pem"
        $public_key_filename = "KeyVault_${key_length}_public.pem"
    }

    $private_key_path = Join-Path $key_location $private_key_filename
    $public_key_path = Join-Path $key_location $public_key_filename

    if ((Test-Path $private_key_path) -or (Test-Path $public_key_path)) {
        Write-Host "Error: One or both target files already exist. Please choose a different name or location." -ForegroundColor Red
        exit 1
    }

    if ($password_protected -eq "yes") {
        Write-Host "Generating $key_length-bit password protected keys ..."
        $passwordPlain = ConvertFrom-SecureString $password -AsPlainText
        & openssl genpkey -algorithm RSA -out $private_key_path -aes256 -pass pass:$passwordPlain -pkeyopt rsa_keygen_bits:$key_length 2>$null
        & openssl rsa -pubout -in $private_key_path -out $public_key_path -passin pass:$passwordPlain 2>$null
        $passwordPlain = $null
    }
    else {
        Write-Host "Generating $key_length-bit keys ..."
        & openssl genpkey -algorithm RSA -out $private_key_path -pkeyopt rsa_keygen_bits:$key_length 2>$null
        & openssl rsa -pubout -in $private_key_path -out $public_key_path 2>$null
    }
}

# Function to create the configuration file
function Setup-ConfigFile {
    if (Test-Path $KEYVAULT_CONFIG) {
        $overwrite = Read-Host "The configuration file $KEYVAULT_CONFIG already exists. Do you want to overwrite it? (yes/no)"
        if ($overwrite -ne "yes") {
            Write-Host "Setup aborted."
            exit 1
        }
    }

    if (Test-Path $KEYVAULT_KEYS) {
        $pem_files = Get-ChildItem -Path $KEYVAULT_KEYS -Filter "*.pem"
        if ($pem_files.Count -gt 0) {
            Write-Host "Found .pem files in the key folder."
            Write-Host "Make sure you have your private keys backed up"
            Write-Host "Setup aborted."
            exit 1
        }
    }

    $configContent = @"
[keyvault]
db=$KEYVAULT_DB
keys=$KEYVAULT_KEYS
pass=$password_protected

[sync]
log=$KEYVAULT_LOG
rclone_remote=$RCLONE_REMOTE

[keychain]
service=KeyVault
account=private.key.password

[key2048]
private=$KEYVAULT_KEYS\KeyVault_2048_private.pem
public=$KEYVAULT_KEYS\KeyVault_2048_public.pem

[key3072]
private=$KEYVAULT_KEYS\KeyVault_3072_private.pem
public=$KEYVAULT_KEYS\KeyVault_3072_public.pem

[key4096]
private=$KEYVAULT_KEYS\KeyVault_4096_private.pem
public=$KEYVAULT_KEYS\KeyVault_4096_public.pem

[key2048_protected]
private=$KEYVAULT_KEYS\KeyVault_2048_protected_private.pem
public=$KEYVAULT_KEYS\KeyVault_2048_protected_public.pem

[key3072_protected]
private=$KEYVAULT_KEYS\KeyVault_3072_protected_private.pem
public=$KEYVAULT_KEYS\KeyVault_3072_protected_public.pem

[key4096_protected]
public=$KEYVAULT_KEYS\KeyVault_4096_protected_public.pem
private=$KEYVAULT_KEYS\KeyVault_4096_protected_private.pem
"@

    Set-Content -Path $KEYVAULT_CONFIG -Value $configContent
}

# Main script execution

if ($demo) {
    $password_protected = "yes"
    $password1 = ConvertTo-SecureString (New-Guid).Guid.Substring(0, 8) -AsPlainText -Force
}
else {
    $password_protected, $password1 = Prompt-PasswordProtection
}

Setup-Directories
Setup-ConfigFile

$key_location = $KEYVAULT_KEYS

# Generate keys of different lengths without password protection
Generate-Keys -key_length 2048 -password_protected "no" -key_location $key_location
Generate-Keys -key_length 3072 -password_protected "no" -key_location $key_location
Generate-Keys -key_length 4096 -password_protected "no" -key_location $key_location

# Generate keys with password protection if required
$password_required_ini = (Get-Content $KEYVAULT_CONFIG | Select-String -Pattern "^pass=").ToString().Split('=')[1].Trim()
if ($password_required_ini -eq "yes") {
    Generate-Keys -key_length 2048 -password_protected "yes" -key_location $key_location -password $password1
    Generate-Keys -key_length 3072 -password_protected "yes" -key_location $key_location -password $password1
    Generate-Keys -key_length 4096 -password_protected "yes" -key_location $key_location -password $password1
}

# Print setup confirmation and details
Write-Host "`nKeyVault environment setup complete."
Write-Host "Configuration directory: $KEYVAULT_DIR"
Write-Host "Configuration file     : $KEYVAULT_CONFIG"
Write-Host "Database file          : $KEYVAULT_DB"
Write-Host "Keys directory         : $KEYVAULT_KEYS"
Write-Host "Password protection key: $password_protected"

# Display demo password if demo flag is true
if ($demo) {
    $demoPassword = ConvertFrom-SecureString $password1 -AsPlainText
    Write-Host "`nDemo private key password: " -NoNewline
    Write-Host $demoPassword -ForegroundColor Red -BackgroundColor White -NoNewline
    Write-Host
    $demoPassword = $null
}

# Clean up sensitive variables
Remove-Variable -Name password1 -Force -ErrorAction SilentlyContinue
