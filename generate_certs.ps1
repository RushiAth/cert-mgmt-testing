#Requires -Version 5.1
<#
.SYNOPSIS
    Script to generate and install CA certificates.

.DESCRIPTION
    This PowerShell script automates the process of:
    1a. Generating Root and Intermediate CA certificates
    1b. Installing certificates to LocalMachine\My store

.EXAMPLE
    .\generate_certs.ps1
#>

# Stop script on any error
$ErrorActionPreference = "Stop"

# Source utility functions
. "$PSScriptRoot\utils.ps1"

# Load environment variables from .env file if it exists
Import-EnvFile -Path "$PSScriptRoot\.env"

# ========================================
# CONFIGURATION
# ========================================
$script:Config = @{
    CERT_THUMBPRINT = $env:CERT_THUMBPRINT
    
    # Certificate settings
    CERT_PASSWORD = "1234"
    
    # Certificate paths
    ROOT_CERT_PATH = "./certGen/certs/azure-iot-test-only.root.ca.cert.pem"
    INTERMEDIATE_CERT_PATH = "./certGen/certs/azure-iot-test-only.intermediate.cert.pem"
    CERT_PEM_PATH = "./certGen/certs/azure-iot-test-only.intermediate.cert.pem"
    CERT_PFX_PATH = "./certGen/certs/azure-iot-test-only.intermediate.cert.pfx"
    CERT_KEY_PATH = "./certGen/private/azure-iot-test-only.intermediate.key.pem"
}

# ========================================
# MAIN EXECUTION
# ========================================
function Main {
    Write-SectionHeader "Certificate Generation and Installation"
    
    # ========================================
    # STEP 1a: Generate CA Certificates
    # ========================================
    Write-SectionHeader "Step 1a: Generating CA Certificates"
    
    # Check if Root and Intermediate CA certificates already exist
    if ((Test-FileExists $script:Config.ROOT_CERT_PATH) -and (Test-FileExists $script:Config.INTERMEDIATE_CERT_PATH)) {
        Write-Warning "Root and Intermediate CA certificates already exist. Skipping generation."
        Write-Info "  Root CA: $($script:Config.ROOT_CERT_PATH)"
        Write-Info "  Intermediate CA: $($script:Config.INTERMEDIATE_CERT_PATH)"
    }
    else {
        Write-Info "Generating Root and Intermediate CA certificates..."
        Push-Location "certGen"
        try {
            & bash ./certGen.sh create_root_and_intermediate
            Write-Success "Root and Intermediate CA certificates generated successfully"
        }
        finally {
            Pop-Location
        }
    }
    
    # Check if certificate file exists after generation
    if (-not (Test-FileExists $script:Config.CERT_PEM_PATH)) {
        Write-Error "Certificate file not found: $($script:Config.CERT_PEM_PATH)"
        Write-Error "Please ensure CA certificates were generated successfully."
        exit 1
    }
    
    # Convert Intermediate CA certificate to PFX format
    Write-Info "Checking if PFX file exists..."
    if (Test-FileExists $script:Config.CERT_PFX_PATH) {
        Write-Warning "PFX file already exists: $($script:Config.CERT_PFX_PATH)"
    }
    else {
        Write-Info "Converting Intermediate CA certificate to PFX format..."
        $converted = Convert-PemToPfx -PemPath $script:Config.CERT_PEM_PATH `
                                       -KeyPath $script:Config.CERT_KEY_PATH `
                                       -PfxPath $script:Config.CERT_PFX_PATH `
                                       -Password $script:Config.CERT_PASSWORD
        
        if ($converted) {
            Write-Success "PFX file created: $($script:Config.CERT_PFX_PATH)"
        }
        else {
            Write-Error "Failed to convert certificate to PFX format"
            exit 1
        }
    }
    
    # ========================================
    # Step 1b: Check Local Certificate Installation
    # ========================================
    Write-SectionHeader "Step 1b: Checking Local Certificate Installation"
    Write-Info "Checking if certificate is already installed in LocalMachine\My store..."
    
    # Check if thumbprint is provided or get it from store
    if (-not [string]::IsNullOrEmpty($script:Config.CERT_THUMBPRINT)) {
        Write-Success "Certificate thumbprint provided: $($script:Config.CERT_THUMBPRINT)"
    }
    else {
        # Try to get thumbprint from store
        $thumbprint = Get-CertificateThumbprint -SubjectFilter "azure-iot-test-only"
        
        if ($thumbprint) {
            $script:Config.CERT_THUMBPRINT = $thumbprint
            Write-Success "Certificate found in LocalMachine\My store."
            Write-Info "Certificate thumbprint: $thumbprint"
        }
        else {
            Write-Warning "Certificate is NOT installed in LocalMachine\My store."
            Write-Info "Attempting to install certificate..."
            
            # Check if PFX file exists
            if (-not (Test-FileExists $script:Config.CERT_PFX_PATH)) {
                Write-Error "PFX file not found: $($script:Config.CERT_PFX_PATH)"
                exit 1
            }
            
            # Import the certificate
            try {
                $securePassword = ConvertTo-SecureString -String $script:Config.CERT_PASSWORD -Force -AsPlainText
                $cert = Import-PfxCertificate -FilePath $script:Config.CERT_PFX_PATH -CertStoreLocation "Cert:\LocalMachine\My" -Password $securePassword
                
                if ($cert) {
                    $script:Config.CERT_THUMBPRINT = $cert.Thumbprint
                    Write-Success "Certificate installed successfully to LocalMachine\My store."
                    Write-Info "Certificate thumbprint: $($cert.Thumbprint)"
                }
                else {
                    Write-Error "Failed to import certificate - no certificate returned"
                    exit 1
                }
            }
            catch {
                Write-Error "Failed to import certificate: $_"
                Write-Host ""
                Write-Host "======================================================================" -ForegroundColor Yellow
                Write-Host "NOTE: Installing to LocalMachine store requires Administrator privileges." -ForegroundColor Yellow
                Write-Host "Please run this script as Administrator or manually install the certificate:" -ForegroundColor Yellow
                Write-Host ""
                Write-Host '  $password = ConvertTo-SecureString -String "' + $script:Config.CERT_PASSWORD + '" -Force -AsPlainText' -ForegroundColor Cyan
                Write-Host '  Import-PfxCertificate -FilePath "' + $script:Config.CERT_PFX_PATH + '" -CertStoreLocation "Cert:\LocalMachine\My" -Password $password' -ForegroundColor Cyan
                Write-Host "======================================================================" -ForegroundColor Yellow
                exit 1
            }
        }
    }
    
    Write-SectionHeader "Certificate Setup Complete"
    Write-Success "Certificate thumbprint: $($script:Config.CERT_THUMBPRINT)"
}

# Run main function
Main
