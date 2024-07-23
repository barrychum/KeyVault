# Define variables for service and account information
$service = 'KeyVault'
$account = 'private.key.password'

# Function to prompt user for a secure password and validate it
function Prompt-SecurePassword {
    # Prompt user to enter the first password securely
    $password1 = Read-Host "Enter a password :" -AsSecureString
    
    # Prompt user to re-enter the password securely for confirmation
    $password2 = Read-Host "Re-enter password:" -AsSecureString
    
    # Validate that both passwords match
    while ((ConvertFrom-SecureString $password1 -AsPlainText) -ne (ConvertFrom-SecureString $password2 -AsPlainText)) {
        Write-Host "Passwords do not match. Please enter the password again" -ForegroundColor Yellow
        
        # Prompt user to enter the password again if they don't match
        $password1 = Read-Host "Enter a password :" -AsSecureString
        $password2 = Read-Host "Re-enter password:" -AsSecureString
    }
    
    # Return the validated secure password
    return $password1
}

# Call the function to prompt for a secure password
$securePassword = Prompt-SecurePassword

# Create a new stored credential using the validated secure password
New-StoredCredential -Type Generic -Persist 'LocalMachine' `
    -Target $service `
    -UserName $account `
    -Password $(ConvertFrom-SecureString $securePassword -AsPlainText) | `
    # Output the properties of the newly created credential
    Format-List Persist, Type, TargetName, UserName, LastWritten
