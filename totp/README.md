## TOTP Generator

This repository provides a function for generating Time-based One-Time Passwords (TOTP) on Linux, macOS, and Windows. TOTP is a two-factor authentication (2FA) method that generates unique codes based on a secret key and the current time.  

**Features**

* Supports Linux and macOS using bash, and Windows using PowerShell.
* Generates TOTP codes based on a secret key and current time.


**Additional Notes**

* This is a basic implementation using sha1 (RFC 6238).
* For security reasons, never storing the secret key within the script itself. 

bash
```
get-otp.sh "secret" ["token length" ["token valid duration"] ]

# most systems use a token length of 6 characters
# set this to the length required by the login systm
# token duration cannot be longer than 30 seconds
# otherwise the generated token will not work

# e.g Don't care the spaces in token. 
# Just put it in quotation marks if contains spaces

totp.sh "test snem ofmq qqdo bukq uo2b fyax cwsd"

```

PowerShell
```
Get-totp -secret "secret"

# e.g.
Get-totp -secret "test snem ofmq qqdo bukq uo2b fyax cwsd"

```

**Acknowldgement**

- https://github.com/neutronscott/bash-totp
- https://gist.github.com/jonfriesen/234c7471c3e3199f97d5


