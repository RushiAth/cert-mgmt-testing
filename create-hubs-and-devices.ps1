#Requires -Version 5.1
<#
.SYNOPSIS
    Script to create IoT Hubs and bulk add devices using DhCmd.

.DESCRIPTION
    This PowerShell script uses DhCmd.exe to:
    1. Creates specified number of IoT Hubs with GEN2 capability
    2. Waits for each hub to become Active
    3. Sets certificate with policy on each hub
    4. Bulk adds specified number of devices to each hub
    5. Generates device certificates

.PARAMETER NumHubs
    Number of IoT Hubs to create (positive integer)

.PARAMETER DevicesPerHub
    Number of devices per hub (positive integer)

.EXAMPLE
    .\create-hubs-and-devices.ps1 -NumHubs 5 -DevicesPerHub 100
#>

param(
    [Parameter(Mandatory = $true)]
    [ValidateRange(1, [int]::MaxValue)]
    [int]$NumHubs,
    
    [Parameter(Mandatory = $true)]
    [ValidateRange(1, [int]::MaxValue)]
    [int]$DevicesPerHub
)

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
    REGION = $env:REGION
    TENANT_ID = $env:TENANT_ID
    ADR_NAMESPACE_RESOURCE_ID = $env:ADR_NAMESPACE_RESOURCE_ID
    UAMI_RESOURCE_ID = $env:UAMI_RESOURCE_ID
    CERT_THUMBPRINT = $env:CERT_THUMBPRINT
    CERT_OUTPUT_DIR = $env:CERT_OUTPUT_DIR
    
    # Derived values
    API_VERSION = "2025-08-01-preview"
    CERT_NAME = "iothub-gen2-intermediate-ca-test"
    HUB_NAME_PREFIX = "stress-hub-"
    DEVICE_POLICY_NAME = "default"
    MAX_WAIT_ATTEMPTS = 15
    WAIT_INTERVAL = 15
}

# Compute derived resource IDs
$script:Config.POLICY_RESOURCE_ID = "$($script:Config.ADR_NAMESPACE_RESOURCE_ID)/credentials/default/policies/default"

# ========================================
# VALIDATION
# ========================================
function Test-RequiredVariables {
    $missingVars = @()
    
    if ([string]::IsNullOrEmpty($script:Config.RP_URI)) { $missingVars += "RP_URI" }
    if ([string]::IsNullOrEmpty($script:Config.DHCMD_PATH)) { $missingVars += "DHCMD_PATH" }
    if ([string]::IsNullOrEmpty($script:Config.REGION)) { $missingVars += "REGION" }
    if ([string]::IsNullOrEmpty($script:Config.TENANT_ID)) { $missingVars += "TENANT_ID" }
    if ([string]::IsNullOrEmpty($script:Config.ADR_NAMESPACE_RESOURCE_ID)) { $missingVars += "ADR_NAMESPACE_RESOURCE_ID" }
    if ([string]::IsNullOrEmpty($script:Config.UAMI_RESOURCE_ID)) { $missingVars += "UAMI_RESOURCE_ID" }
    if ([string]::IsNullOrEmpty($script:Config.CERT_THUMBPRINT)) { $missingVars += "CERT_THUMBPRINT" }
    
    if ($missingVars.Count -gt 0) {
        Write-Error "Missing required environment variables:"
        $missingVars | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
        return $false
    }
    
    # Validate DhCmd.exe path exists
    if (-not (Test-Path $script:Config.DHCMD_PATH)) {
        Write-Error "DhCmd.exe not found at: $($script:Config.DHCMD_PATH)"
        return $false
    }
    
    return $true
}

# ========================================
# HELPER FUNCTIONS
# ========================================
function Get-HubName {
    param([int]$Index)
    $hubIndex = "{0:D5}" -f $Index
    return "$($script:Config.HUB_NAME_PREFIX)$hubIndex"
}

# ========================================
# MAIN EXECUTION
# ========================================
function Main {
    Write-SectionHeader "IoT Hub and Device Creation Script"
    Write-Info "RP Environment: $($script:Config.RP_URI)"
    Write-Info "Number of Hubs: $NumHubs"
    Write-Info "Devices Per Hub: $DevicesPerHub"
    Write-Info "Hub Name Prefix: $($script:Config.HUB_NAME_PREFIX)"
    Write-Info "Script Directory: $PSScriptRoot"
    Write-Host ""
    
    # Validate required variables
    if (-not (Test-RequiredVariables)) {
        exit 1
    }
    
    Write-Success "Using DhCmd.exe path: $($script:Config.DHCMD_PATH)"
    Write-Host ""
    
    # Array to store hub names
    $hubNames = @()
    
    # ========================================
    # STEP 1: Create IoT Hubs using bulk creation
    # ========================================
    Write-SectionHeader "STEP 1: Creating $NumHubs IoT Hub(s)"
    Write-Host ""
    
    Write-Info "Initiating bulk creation of $NumHubs hubs with prefix: $($script:Config.HUB_NAME_PREFIX)"
    
    $createResult = Invoke-DhCmd -DhCmdPath $script:Config.DHCMD_PATH `
                                 -RpUri $script:Config.RP_URI `
                                 -Command "CreateIotHubsGen2 $($script:Config.HUB_NAME_PREFIX) $NumHubs $($script:Config.ADR_NAMESPACE_RESOURCE_ID) $($script:Config.UAMI_RESOURCE_ID) $($script:Config.REGION) $($script:Config.TENANT_ID) /ApiVersion:$($script:Config.API_VERSION)"
    
    if ($createResult) {
        Write-Success "Bulk hub creation initiated for $NumHubs hubs"
    }
    else {
        Write-Error "Failed to initiate bulk hub creation"
        exit 1
    }
    
    # Build list of expected hub names
    for ($i = 0; $i -lt $NumHubs; $i++) {
        $hubName = Get-HubName -Index $i
        $hubNames += $hubName
    }
    
    Write-Success "All $NumHubs hub(s) creation initiated"
    Write-Host ""
    
    # ========================================
    # STEP 2: Wait for all hubs to become Active
    # ========================================
    Write-SectionHeader "STEP 2: Waiting for Hub(s) to Activate"
    Write-Host ""
    
    $activatedHubs = @()
    
    foreach ($hubName in $hubNames) {
        Write-Info "Waiting for hub: $hubName"
        
        $activated = Wait-ForHubActivation -HubName $hubName `
                                           -DhCmdPath $script:Config.DHCMD_PATH `
                                           -RpUri $script:Config.RP_URI `
                                           -ApiVersion $script:Config.API_VERSION `
                                           -MaxAttempts $script:Config.MAX_WAIT_ATTEMPTS `
                                           -WaitInterval $script:Config.WAIT_INTERVAL
        
        if ($activated) {
            $activatedHubs += $hubName
            Write-Success "Hub activated: $hubName"
        }
        else {
            Write-Error "Hub failed to activate: $hubName"
            Write-Warning "Continuing with other hubs..."
        }
        
        Write-Host ""
    }
    
    if ($activatedHubs.Count -eq 0) {
        Write-Error "No hubs were successfully activated. Exiting."
        exit 1
    }
    
    Write-Success "$($activatedHubs.Count) hub(s) successfully activated out of $NumHubs"
    Write-Host ""
    
    # ========================================
    # STEP 3: Set Certificate with Policy on each activated hub
    # ========================================
    Write-SectionHeader "STEP 3: Setting Certificate with Policy on Hub(s)"
    Write-Host ""
    
    foreach ($hubName in $activatedHubs) {
        Write-Info "Setting certificate with policy on hub: $hubName"
        
        $setCertResult = Invoke-DhCmd -DhCmdPath $script:Config.DHCMD_PATH `
                                      -RpUri $script:Config.RP_URI `
                                      -Command "SetCertificateWithPolicy $hubName $($script:Config.CERT_NAME) $($script:Config.CERT_THUMBPRINT) My LocalMachine $($script:Config.POLICY_RESOURCE_ID) /ApiVersion:$($script:Config.API_VERSION)"
        
        if ($setCertResult) {
            Write-Success "Successfully set certificate with policy on hub: $hubName"
        }
        else {
            Write-Warning "Failed to set certificate with policy on hub: $hubName"
        }
        
        Write-Host ""
    }
    
    # Sleep for a short duration to ensure settings propagate
    Write-Info "Waiting for 30 seconds to allow settings to propagate..."
    Start-Sleep -Seconds 30
    Write-Host ""
    
    # ========================================
    # STEP 4: Add devices to each activated hub
    # ========================================
    Write-SectionHeader "STEP 4: Adding Devices to Hub(s)"
    Write-Host ""
    
    foreach ($hubName in $activatedHubs) {
        Write-Info "Adding $DevicesPerHub devices to hub: $hubName"
        
        $devicesAdded = 0
        $devicesFailed = 0
        
        for ($i = 0; $i -lt $DevicesPerHub; $i++) {
            # Create 5-digit zero-padded device ID
            $deviceId = "device{0:D5}" -f $i
            
            $createDeviceResult = Invoke-DhCmd -DhCmdPath $script:Config.DHCMD_PATH `
                                               -RpUri $script:Config.RP_URI `
                                               -Command "CreateDeviceWithHttpAndCertAuth $hubName $deviceId $($script:Config.DEVICE_POLICY_NAME) /ApiVersion:$($script:Config.API_VERSION)"
            
            if ($createDeviceResult) {
                $devicesAdded++
            }
            else {
                Write-Warning "Failed to add device $deviceId to hub: $hubName"
                $devicesFailed++
            }
        }
        
        if ($devicesFailed -eq 0) {
            Write-Success "Successfully added $devicesAdded devices to $hubName"
        }
        else {
            Write-Warning "Added $devicesAdded devices to $hubName ($devicesFailed failed)"
        }
        
        Write-Host ""
    }
    
    # ========================================
    # STEP 5: Generate device certificates
    # ========================================
    Write-SectionHeader "STEP 5: Generating Device Certificates"
    Write-Host ""
    
    $certGenScript = Join-Path $PSScriptRoot "certGen\generate_device_certs.sh"
    $certGenDir = Join-Path $PSScriptRoot "certGen"
    
    if ([string]::IsNullOrEmpty($script:Config.CERT_OUTPUT_DIR)) {
        Write-Warning "CERT_OUTPUT_DIR not set. Skipping certificate generation."
    }
    elseif (-not (Test-Path $certGenScript)) {
        Write-Error "generate_device_certs.sh not found at: $certGenScript"
        Write-Warning "Skipping certificate generation"
    }
    elseif (-not (Test-Path $certGenDir)) {
        Write-Error "certGen directory not found at: $certGenDir"
        Write-Warning "Skipping certificate generation"
    }
    else {
        Write-Info "Certificate output directory: $($script:Config.CERT_OUTPUT_DIR)"
        Write-Info "Generating certificates for $DevicesPerHub devices per hub across $($activatedHubs.Count) hub(s)"
        Write-Host ""
        
        # Change to certGen directory to run certificate generation
        Write-Info "Changing to certGen directory: $certGenDir"
        Push-Location $certGenDir
        
        try {
            foreach ($hubName in $activatedHubs) {
                Write-Info "Generating certificates for hub: $hubName"
                
                # Create hub-specific output directory
                $hubCertDir = $script:Config.CERT_OUTPUT_DIR
                
                # Call generate_device_certs.sh with appropriate parameters
                # Arguments: <number_of_devices> <target_directory> <device_name_prefix> <file_name_prefix>
                # file_name_prefix format: {hub_name}_device
                $generateCmd = "bash `"$certGenScript`" $DevicesPerHub `"$hubCertDir`" `"device`" `"${hubName}_device`""
                
                try {
                    Invoke-Expression $generateCmd
                    Write-Success "Successfully generated certificates for $hubName"
                }
                catch {
                    Write-Error "Failed to generate certificates for hub: $hubName"
                    Write-Warning "Continuing with other hubs..."
                }
                
                Write-Host ""
            }
            
            Write-Success "Certificate generation completed for all hubs"
        }
        finally {
            Pop-Location
        }
        
        Write-Host ""
    }
    
    # ========================================
    # FINAL SUMMARY
    # ========================================
    Write-SectionHeader "FINAL SUMMARY"
    Write-Success "Script completed successfully!"
    Write-Host ""
    Write-Info "Hubs created and activated: $($activatedHubs.Count)"
    Write-Info "Total devices created: $($activatedHubs.Count * $DevicesPerHub)"
    Write-Host ""
    Write-Info "Hub Names:"
    foreach ($hubName in $activatedHubs) {
        Write-Host "  - $hubName"
    }
    Write-Host ""
    Write-Info "Device Naming Convention:"
    Write-Info "  Devices are named as: device00000, device00001, device00002, etc."
    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Green
    Write-Host "Operation completed successfully!" -ForegroundColor Green
    Write-Host "==========================================" -ForegroundColor Green
}

# Run main function
Main
