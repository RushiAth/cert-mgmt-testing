# ========================================
# PowerShell Utility Functions for Certificate Management Testing
# ========================================

# Import environment variables from .env file
function Import-EnvFile {
    param(
        [string]$Path = ".env"
    )
    
    if (-not (Test-Path $Path)) {
        Write-Warning "Environment file not found: $Path"
        return $false
    }
    
    Write-Host "[INFO] Loading environment variables from: $Path" -ForegroundColor White
    
    Get-Content $Path | ForEach-Object {
        $line = $_.Trim()
        
        # Skip empty lines and comments
        if ($line -match '^\s*$' -or $line -match '^\s*#') {
            return
        }
        
        # Remove 'export ' prefix if present (bash-style)
        if ($line -match '^export\s+(.+)$') {
            $line = $matches[1]
        }
        
        # Parse KEY=VALUE format
        if ($line -match '^([^=]+)=(.*)$') {
            $key = $matches[1].Trim()
            $value = $matches[2].Trim()
            
            # Remove surrounding quotes if present
            if ($value -match '^[''"](.*)[''""]$') {
                $value = $matches[1]
            }
            
            # Set environment variable
            [Environment]::SetEnvironmentVariable($key, $value, 'Process')
            Write-Host "[INFO]   Set $key" -ForegroundColor Gray
        }
    }
    
    Write-Host "[SUCCESS] Environment variables loaded" -ForegroundColor Green
    return $true
}

# Color output functions
function Write-SectionHeader {
    param([string]$Message)
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host $Message -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
}

function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor White
}

function Write-Success {
    param([string]$Message)
    Write-Host "[SUCCESS] $Message" -ForegroundColor Green
}

function Write-Warning {
    param([string]$Message)
    Write-Host "[WARNING] $Message" -ForegroundColor Yellow
}

function Write-Error {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

# Run DhCmd command
function Invoke-DhCmd {
    param(
        [string]$DhCmdPath,
        [string]$RpUri,
        [string]$Command
    )
    
    $fullCommand = "$DhCmdPath $Command /RpUri:$RpUri"
    Write-Info "Running: $fullCommand"
    
    try {
        $result = Invoke-Expression $fullCommand 2>&1
        return $result
    }
    catch {
        Write-Error "DhCmd command failed: $_"
        return $null
    }
}

# Wait for hub to become active
function Wait-ForHubActivation {
    param(
        [string]$HubName,
        [string]$DhCmdPath,
        [string]$RpUri,
        [string]$ApiVersion,
        [int]$MaxAttempts = 15,
        [int]$WaitInterval = 15
    )
    
    for ($i = 1; $i -le $MaxAttempts; $i++) {
        Write-Info "Checking hub status (attempt $i of $MaxAttempts)..."
        
        $result = Invoke-DhCmd -DhCmdPath $DhCmdPath -RpUri $RpUri -Command "GetIotHub $HubName /ApiVersion:$ApiVersion"
        
        if ($result -match "State.*Active" -or $result -match "IotHubConnectionString:") {
            Write-Success "Hub is now active!"
            return $true
        }
        
        if ($i -lt $MaxAttempts) {
            Write-Info "Hub not yet active. Waiting $WaitInterval seconds..."
            Start-Sleep -Seconds $WaitInterval
        }
    }
    
    Write-Error "Hub did not become active within the expected time."
    return $false
}

# Check if a file exists
function Test-FileExists {
    param([string]$Path)
    return Test-Path -Path $Path -PathType Leaf
}

# Get certificate thumbprint from LocalMachine\My store
function Get-CertificateThumbprint {
    param([string]$SubjectFilter)
    
    try {
        $cert = Get-ChildItem -Path Cert:\LocalMachine\My | Where-Object { $_.Subject -like "*$SubjectFilter*" } | Select-Object -First 1
        if ($cert) {
            return $cert.Thumbprint
        }
        return $null
    }
    catch {
        Write-Error "Failed to access certificate store: $_"
        return $null
    }
}

# Import PFX certificate to LocalMachine\My store
function Import-PfxToLocalMachine {
    param(
        [string]$PfxPath,
        [string]$Password
    )
    
    try {
        $securePassword = ConvertTo-SecureString -String $Password -Force -AsPlainText
        $cert = Import-PfxCertificate -FilePath $PfxPath -CertStoreLocation "Cert:\LocalMachine\My" -Password $securePassword
        return $cert.Thumbprint
    }
    catch {
        Write-Error "Failed to import certificate: $_"
        return $null
    }
}

# Convert PEM to PFX using OpenSSL
function Convert-PemToPfx {
    param(
        [string]$PemPath,
        [string]$KeyPath,
        [string]$PfxPath,
        [string]$Password
    )
    
    try {
        $opensslCmd = "openssl pkcs12 -export -out `"$PfxPath`" -inkey `"$KeyPath`" -in `"$PemPath`" -password pass:$Password"
        Invoke-Expression $opensslCmd
        
        if (Test-Path $PfxPath) {
            return $true
        }
        return $false
    }
    catch {
        Write-Error "Failed to convert PEM to PFX: $_"
        return $false
    }
}
