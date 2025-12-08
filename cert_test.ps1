#Requires -Version 5.1
<#
.SYNOPSIS
    Script to create an IoT Hub and device using DhCmd and then send issueCertificate request.

.DESCRIPTION
    This PowerShell script automates the process of:
    1. Generating Root and Intermediate CA certificates
    2. Installing certificates to LocalMachine\My store
    3. Creating an IoT Hub
    4. Setting the certificate on the hub
    5. Creating a device certificate
    6. Creating a device
    7. Issuing a certificate via MQTT

.EXAMPLE
    .\cert_test.ps1
#>

# Stop script on any error
$ErrorActionPreference = "Stop"

# Source utility functions
. "$PSScriptRoot\utils.ps1"

# Load environment variables from .env file if it exists
Import-EnvFile -Path "$PSScriptRoot\.env"

# ========================================
# CONFIGURATION - Set via environment variables or modify here
# ========================================
$script:Config = @{
    RP_URI = $env:RP_URI
    DHCMD_PATH = $env:DHCMD_PATH
    HUB_NAME = $env:HUB_NAME
    DEVICE_NAME = $env:DEVICE_NAME
    REGION = $env:REGION
    TENANT_ID = $env:TENANT_ID
    ADR_NAMESPACE_RESOURCE_ID = $env:ADR_NAMESPACE_RESOURCE_ID
    UAMI_RESOURCE_ID = $env:UAMI_RESOURCE_ID
    CERT_THUMBPRINT = $env:CERT_THUMBPRINT
    
    # Derived values
    API_VERSION = "2025-08-01-preview"
    CERT_NAME = "iothub-gen2-intermediate-ca-test"
    CERT_PASSWORD = "1234"
    MAX_WAIT_ATTEMPTS = 15
    WAIT_INTERVAL = 15
    
    # Certificate paths
    ROOT_CERT_PATH = "./certGen/certs/azure-iot-test-only.root.ca.cert.pem"
    INTERMEDIATE_CERT_PATH = "./certGen/certs/azure-iot-test-only.intermediate.cert.pem"
    CERT_PEM_PATH = "./certGen/certs/azure-iot-test-only.intermediate.cert.pem"
    CERT_PFX_PATH = "./certGen/certs/azure-iot-test-only.intermediate.cert.pfx"
    CERT_KEY_PATH = "./certGen/private/azure-iot-test-only.intermediate.key.pem"
}

# Compute derived resource IDs
$script:Config.DEVICE_RESOURCE_ID = "$($script:Config.ADR_NAMESPACE_RESOURCE_ID)/devices/$($script:Config.DEVICE_NAME)"
$script:Config.POLICY_RESOURCE_ID = "$($script:Config.ADR_NAMESPACE_RESOURCE_ID)/credentials/default/policies/default"
$script:Config.POLICY_NAME = ($script:Config.ADR_NAMESPACE_RESOURCE_ID -split '/')[-1]

# ========================================
# VALIDATION
# ========================================
function Test-RequiredVariables {
    $missingVars = @()
    
    if ([string]::IsNullOrEmpty($script:Config.RP_URI)) { $missingVars += "RP_URI" }
    if ([string]::IsNullOrEmpty($script:Config.REGION)) { $missingVars += "REGION" }
    if ([string]::IsNullOrEmpty($script:Config.TENANT_ID)) { $missingVars += "TENANT_ID" }
    if ([string]::IsNullOrEmpty($script:Config.ADR_NAMESPACE_RESOURCE_ID)) { $missingVars += "ADR_NAMESPACE_RESOURCE_ID" }
    if ([string]::IsNullOrEmpty($script:Config.UAMI_RESOURCE_ID)) { $missingVars += "UAMI_RESOURCE_ID" }
    if ([string]::IsNullOrEmpty($script:Config.HUB_NAME)) { $missingVars += "HUB_NAME" }
    if ([string]::IsNullOrEmpty($script:Config.DEVICE_NAME)) { $missingVars += "DEVICE_NAME" }
    
    if ($missingVars.Count -gt 0) {
        Write-Error "Missing required environment variables:"
        $missingVars | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
        Write-Host ""
        Write-Host "Usage example:"
        Write-Host '  $env:RP_URI = "your-rp-uri"'
        Write-Host '  $env:HUB_NAME = "your-hub-name"'
        Write-Host '  $env:DEVICE_NAME = "your-device-name"'
        Write-Host '  $env:REGION = "your-region"'
        Write-Host '  $env:TENANT_ID = "your-tenant-id"'
        Write-Host '  $env:ADR_NAMESPACE_RESOURCE_ID = "your-adr-namespace-resource-id"'
        Write-Host '  $env:UAMI_RESOURCE_ID = "your-uami-resource-id"'
        Write-Host '  .\cert_test.ps1'
        return $false
    }
    
    return $true
}

# ========================================
# MAIN EXECUTION
# ========================================
function Main {
    Write-SectionHeader "Private Environment Setup"
    Write-Info "RP URI: $($script:Config.RP_URI)"
    Write-Info "Region: $($script:Config.REGION)"
    Write-Info "Tenant ID: $($script:Config.TENANT_ID)"
    Write-Info "ADR Namespace Resource ID: $($script:Config.ADR_NAMESPACE_RESOURCE_ID)"
    Write-Info "UAMI Resource ID: $($script:Config.UAMI_RESOURCE_ID)"
    Write-Info "Hub Name: $($script:Config.HUB_NAME)"
    Write-Info "Device Name: $($script:Config.DEVICE_NAME)"
    
    # Validate required variables
    if (-not (Test-RequiredVariables)) {
        exit 1
    }
    
    # ========================================
    # STEP 1: Generate and Install CA Certificates
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
    
    # ========================================
    # STEP 2: IoT Hub Setup
    # ========================================
    Write-SectionHeader "Step 2: Checking IoT Hub Existence"
    Write-Info "Checking if IoT Hub '$($script:Config.HUB_NAME)' already exists..."
    
    $hubExists = Invoke-DhCmd -DhCmdPath $script:Config.DHCMD_PATH `
                              -RpUri $script:Config.RP_URI `
                              -Command "GetIotHub $($script:Config.HUB_NAME) /ApiVersion:$($script:Config.API_VERSION)"
    
    $skipHubCreation = $false
    if ($hubExists -match "IotHubConnectionString:" -or $hubExists -match "Name.*$($script:Config.HUB_NAME)") {
        Write-Warning "IoT Hub '$($script:Config.HUB_NAME)' already exists. Skipping creation."
        $skipHubCreation = $true
    }
    else {
        Write-Info "IoT Hub '$($script:Config.HUB_NAME)' does not exist. Proceeding with creation."
    }
    
    # Create IoT Hub (if not exists)
    if (-not $skipHubCreation) {
        Write-SectionHeader "Creating IoT Hub"
        Write-Info "Hub Name: $($script:Config.HUB_NAME)"
        Write-Info "Hub Type: GEN2"
        Write-Info "Region: $($script:Config.REGION)"
        
        Invoke-DhCmd -DhCmdPath $script:Config.DHCMD_PATH `
                     -RpUri $script:Config.RP_URI `
                     -Command "CreateIotHubPremiumOrGen2 $($script:Config.HUB_NAME) 'GEN2' '$($script:Config.ADR_NAMESPACE_RESOURCE_ID)' '$($script:Config.UAMI_RESOURCE_ID)' '$($script:Config.REGION)' '$($script:Config.TENANT_ID)' /ApiVersion:$($script:Config.API_VERSION)"
        
        Write-Success "IoT Hub creation initiated successfully"
        
        # Wait for hub to become active
        Write-SectionHeader "Waiting for Hub Activation"
        Write-Info "This may take several minutes..."
        
        $activated = Wait-ForHubActivation -HubName $script:Config.HUB_NAME `
                                           -DhCmdPath $script:Config.DHCMD_PATH `
                                           -RpUri $script:Config.RP_URI `
                                           -ApiVersion $script:Config.API_VERSION `
                                           -MaxAttempts $script:Config.MAX_WAIT_ATTEMPTS `
                                           -WaitInterval $script:Config.WAIT_INTERVAL
        
        if (-not $activated) {
            Write-Error "Hub failed to activate. Exiting."
            exit 1
        }
    }
    else {
        Write-SectionHeader "Skipping Hub Creation"
        Write-Info "Using existing IoT Hub: $($script:Config.HUB_NAME)"
    }
    
    # ========================================
    # STEP 3: Obtain Connection String
    # ========================================
    Write-SectionHeader "Step 3: Obtaining Hub Connection String"
    
    $hubInfo = Invoke-DhCmd -DhCmdPath $script:Config.DHCMD_PATH `
                            -RpUri $script:Config.RP_URI `
                            -Command "GetIotHub $($script:Config.HUB_NAME) /ApiVersion:$($script:Config.API_VERSION)"
    
    $connectionString = ($hubInfo | Select-String -Pattern "IotHubConnectionString:\s*(.+)" | ForEach-Object { $_.Matches.Groups[1].Value }).Trim()
    
    if ([string]::IsNullOrEmpty($connectionString)) {
        Write-Error "Failed to obtain connection string"
        exit 1
    }
    
    Write-Success "Connection string obtained successfully"
    Write-Info "Connection String: $connectionString"
    
    # ========================================
    # STEP 4: Set Certificate with IoT Hub
    # ========================================
    Write-SectionHeader "Step 4: Setting Intermediate CA Certificate"
    
    # Check if certificate is already set on the hub
    Write-Info "Checking if certificate is already set on IoT Hub..."
    $certSetResult = Invoke-DhCmd -DhCmdPath $script:Config.DHCMD_PATH `
                                  -RpUri $script:Config.RP_URI `
                                  -Command "GetCertificate $($script:Config.HUB_NAME) $($script:Config.CERT_NAME) /ApiVersion:$($script:Config.API_VERSION)"
    
    if ($certSetResult -match $script:Config.CERT_THUMBPRINT) {
        Write-Warning "Certificate '$($script:Config.CERT_NAME)' is already set on IoT Hub. Skipping."
    }
    else {
        Write-Info "Setting certificate with IoT Hub..."
        Invoke-DhCmd -DhCmdPath $script:Config.DHCMD_PATH `
                     -RpUri $script:Config.RP_URI `
                     -Command "SetCertificateWithPolicy $($script:Config.HUB_NAME) $($script:Config.CERT_NAME) $($script:Config.CERT_THUMBPRINT) My LocalMachine $($script:Config.POLICY_RESOURCE_ID) /ApiVersion:$($script:Config.API_VERSION)"
        Write-Success "Certificate set successfully"
    }
    
    # ========================================
    # STEP 5: Create Device Certificate
    # ========================================
    Write-SectionHeader "Step 5: Creating Device Certificate"
    
    $deviceCertPath = "./certGen/certs/$($script:Config.DEVICE_NAME).crt"
    $deviceKeyPath = "./certGen/private/$($script:Config.DEVICE_NAME).key"
    
    # Check if device certificate already exists
    if ((Test-FileExists $deviceCertPath) -and (Test-FileExists $deviceKeyPath)) {
        Write-Warning "Device certificate already exists. Skipping generation."
        Write-Info "  Device Cert: $deviceCertPath"
        Write-Info "  Device Key: $deviceKeyPath"
    }
    else {
        Write-Info "Generating device certificate for: $($script:Config.DEVICE_NAME)"
        
        Push-Location "certGen"
        try {
            & bash ./certGen.sh create_device_certificate_from_intermediate $($script:Config.DEVICE_NAME)
            
            Push-Location "certs"
            Write-Info "Converting certificate to CRT format..."
            & bash -c "openssl x509 -in new-device.cert.pem -out '$($script:Config.DEVICE_NAME).crt'"
            Pop-Location
            
            Push-Location "private"
            Write-Info "Renaming private key..."
            if (Test-Path "new-device.key.pem") {
                Move-Item -Path "new-device.key.pem" -Destination "$($script:Config.DEVICE_NAME).key" -Force
            }
            Pop-Location
            
            Write-Success "Device certificate created successfully"
        }
        finally {
            Pop-Location
        }
    }
    
    # ========================================
    # STEP 6: Create Device
    # ========================================
    Write-SectionHeader "Step 6: Creating Device"
    
    if ([string]::IsNullOrEmpty($script:Config.DEVICE_NAME) -or 
        [string]::IsNullOrEmpty($connectionString) -or 
        [string]::IsNullOrEmpty($script:Config.DEVICE_RESOURCE_ID) -or 
        [string]::IsNullOrEmpty($script:Config.POLICY_RESOURCE_ID)) {
        Write-Error "DEVICE_NAME or connection string or ADR_NAMESPACE_RESOURCE_ID not provided"
        exit 1
    }
    
    # Check if device already exists
    Write-Info "Checking if device '$($script:Config.DEVICE_NAME)' already exists..."
    $deviceExistsCmd = "$($script:Config.DHCMD_PATH) GetDevice $($script:Config.DEVICE_NAME) /ConnectionString:`"$connectionString`" /ApiVersion:$($script:Config.API_VERSION)"
    $deviceExistsResult = Invoke-Expression $deviceExistsCmd 2>&1
    
    if ($deviceExistsResult -match "DeviceId.*$($script:Config.DEVICE_NAME)") {
        Write-Warning "Device '$($script:Config.DEVICE_NAME)' already exists. Skipping creation."
    }
    else {
        Write-Info "Device Name: $($script:Config.DEVICE_NAME)"
        Write-Info "Authentication: CA Certificate"
        
        $createDeviceCmd = "$($script:Config.DHCMD_PATH) CreateDeviceWithHttpAndCertAuth $($script:Config.HUB_NAME) $($script:Config.DEVICE_NAME) $($script:Config.POLICY_NAME) /ConnectionString:`"$connectionString`" /ApiVersion:$($script:Config.API_VERSION) /RpUri:$($script:Config.RP_URI)"
        Invoke-Expression $createDeviceCmd
        
        Write-Success "Device created successfully: $($script:Config.DEVICE_NAME)"
    }
    
    # ========================================
    # STEP 7: Issue Device Certificate via MQTT
    # ========================================
    Write-SectionHeader "Step 7: Issuing Device Certificate via MQTT"
    Write-Info "Sending issueCertificate request for device: $($script:Config.DEVICE_NAME)"
    
    # MQTT Configuration
    $mqttHost = "$($script:Config.HUB_NAME).azure-devices-int.net"
    $mqttPort = 8883
    $mqttCaCert = "./IoTHubRootCA.crt.pem"
    $mqttDeviceCert = "./certGen/certs/$($script:Config.DEVICE_NAME).crt"
    $mqttDeviceKey = "./certGen/private/$($script:Config.DEVICE_NAME).key"
    
    Write-Info "MQTT Host: $mqttHost"
    Write-Info "MQTT Port: $mqttPort"
    Write-Info "Device: $($script:Config.DEVICE_NAME)"
    Write-Info "CA Cert: $mqttCaCert"
    Write-Info "Device Cert: $mqttDeviceCert"
    Write-Info "Device Key: $mqttDeviceKey"
    
    # Run the Python MQTT script
    Write-Info "Running MQTT certificate issuance script..."
    
    # Use python instead of python3 on Windows, and run directly with & to stream output
    # First check for venv python, then fall back to system python
    $pythonCmd = "python"
    if (Test-Path ".\venv\Scripts\python.exe") {
        $pythonCmd = ".\venv\Scripts\python.exe"
    }
    elseif (Get-Command "python3" -ErrorAction SilentlyContinue) {
        $pythonCmd = "python3"
    }
    
    Write-Info "Using Python command: $pythonCmd"
    
    # Run the Python script directly with & operator to stream output to console
    & $pythonCmd ./mqtt_issue_cert.py `
        --host "$mqttHost" `
        --device "$($script:Config.DEVICE_NAME)" `
        --ca-cert "$mqttCaCert" `
        --device-cert "$mqttDeviceCert" `
        --device-key "$mqttDeviceKey" `
        --port $mqttPort `
        --timeout 90
    
    $mqttExitCode = $LASTEXITCODE
    
    if ($mqttExitCode -eq 0) {
        Write-Success "Certificate issuance process completed successfully"
    }
    else {
        Write-Error "Certificate issuance failed (exit code: $mqttExitCode)"
        exit 1
    }
}

# Run main function
Main
