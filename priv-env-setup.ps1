#Requires -Version 5.1
<#
.SYNOPSIS
    Script to set up a private environment for IoT Hub development and testing.

.DESCRIPTION
    This PowerShell script automates the process of:
    1. Setting feature filter desired states
    2. Setting feature filters
    3. Creating an IoT Hub (GEN2)

.EXAMPLE
    .\priv-env-setup.ps1
#>

# Source utility functions
. "$PSScriptRoot\utils.ps1"

# Load environment variables from .env file if it exists
Import-EnvFile -Path "$PSScriptRoot\.env"

# ========================================
# CONFIGURATION - Set via environment variables or modify here
# ========================================
$script:Config = @{
    # Required Configuration
    RP_URI = $env:RP_URI
    DHCMD_PATH = if ($env:DHCMD_PATH) { $env:DHCMD_PATH } else { "./DhCmd.exe" }
    ALIAS = $env:ALIAS
    REGION = $env:REGION
    TENANT_ID = $env:TENANT_ID
    
    # Hub Configuration
    HUB_NAME = $env:HUB_NAME
    ADR_NAMESPACE_RESOURCE_ID = $env:ADR_NAMESPACE_RESOURCE_ID
    UAMI_RESOURCE_ID = $env:UAMI_RESOURCE_ID
    API_VERSION = "2025-08-01-preview"
    
    # Device Configuration
    DEVICE_NAME = $env:DEVICE_NAME
    
    # Feature Configuration
    CURRENT_DATE = (Get-Date).ToString("MM/dd/yyyy")
    
    # Hub activation configuration
    MAX_WAIT_ATTEMPTS = if ($env:MAX_WAIT_ATTEMPTS) { [int]$env:MAX_WAIT_ATTEMPTS } else { 15 }
    WAIT_INTERVAL = if ($env:WAIT_INTERVAL) { [int]$env:WAIT_INTERVAL } else { 15 }
}

# ========================================
# VALIDATION
# ========================================
function Test-RequiredVariables {
    $missingVars = @()
    
    if ([string]::IsNullOrEmpty($script:Config.RP_URI)) { $missingVars += "RP_URI" }
    if ([string]::IsNullOrEmpty($script:Config.ALIAS)) { $missingVars += "ALIAS" }
    if ([string]::IsNullOrEmpty($script:Config.REGION)) { $missingVars += "REGION" }
    if ([string]::IsNullOrEmpty($script:Config.TENANT_ID)) { $missingVars += "TENANT_ID" }
    if ([string]::IsNullOrEmpty($script:Config.ADR_NAMESPACE_RESOURCE_ID)) { $missingVars += "ADR_NAMESPACE_RESOURCE_ID" }
    if ([string]::IsNullOrEmpty($script:Config.UAMI_RESOURCE_ID)) { $missingVars += "UAMI_RESOURCE_ID" }
    
    if ($missingVars.Count -gt 0) {
        Write-Error "Missing required environment variables:"
        $missingVars | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
        Write-Host ""
        Write-Host "Usage example:"
        Write-Host '  $env:RP_URI = "your-rp-uri"'
        Write-Host '  $env:ALIAS = "your-alias"'
        Write-Host '  $env:REGION = "your-region"'
        Write-Host '  $env:TENANT_ID = "your-tenant-id"'
        Write-Host '  $env:ADR_NAMESPACE_RESOURCE_ID = "your-adr-namespace-resource-id"'
        Write-Host '  $env:UAMI_RESOURCE_ID = "your-uami-resource-id"'
        Write-Host '  .\priv-env-setup.ps1'
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
    Write-Info "Alias: $($script:Config.ALIAS)"
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
    # STEP 1: Set Feature Filter Desired State
    # ========================================
    Write-SectionHeader "Setting Feature Filter Desired State"
    
    $currentDate = $script:Config.CURRENT_DATE
    $alias = $script:Config.ALIAS
    
    Invoke-DhCmd -DhCmdPath $script:Config.DHCMD_PATH `
                 -RpUri $script:Config.RP_URI `
                 -Command "SetFeatureFilterDesiredState Gateway.EnableCertificateIssuance 2 $currentDate $alias /PaasV2:True"
    
    Invoke-DhCmd -DhCmdPath $script:Config.DHCMD_PATH `
                 -RpUri $script:Config.RP_URI `
                 -Command "SetFeatureFilterDesiredState Gateway.UseDcSessionVNext.Mqtt 0 $currentDate $alias /PaasV2:True"
    
    Invoke-DhCmd -DhCmdPath $script:Config.DHCMD_PATH `
                 -RpUri $script:Config.RP_URI `
                 -Command "SetFeatureFilterDesiredState Gateway.UseDcSessionVNext.LazyReauth.Amqp 0 $currentDate $alias /PaasV2:True"
    
    Invoke-DhCmd -DhCmdPath $script:Config.DHCMD_PATH `
                 -RpUri $script:Config.RP_URI `
                 -Command "SetFeatureFilterDesiredState Gateway.UseDcSessionVNext.LazyReauth.Mqtt 0 $currentDate $alias /PaasV2:True"
    
    Invoke-DhCmd -DhCmdPath $script:Config.DHCMD_PATH `
                 -RpUri $script:Config.RP_URI `
                 -Command "SetFeatureFilterDesiredState Gateway.UseDcSessionVNext.Amqp 0 $currentDate $alias /PaasV2:True"
    
    Invoke-DhCmd -DhCmdPath $script:Config.DHCMD_PATH `
                 -RpUri $script:Config.RP_URI `
                 -Command "SetFeatureFilterDesiredState DcDeviceSessionV2 0 $currentDate $alias /PaasV2:True"
    
    Invoke-DhCmd -DhCmdPath $script:Config.DHCMD_PATH `
                 -RpUri $script:Config.RP_URI `
                 -Command "SetFeatureFilterDesiredState DeviceAuthChangeNotification 0 $currentDate $alias /PaasV2:True"
    
    Invoke-DhCmd -DhCmdPath $script:Config.DHCMD_PATH `
                 -RpUri $script:Config.RP_URI `
                 -Command "SetFeatureFilterDesiredState UseMockHttpHandlerForCertificateManagementClient 0 $currentDate $alias /PaasV2:True"
    
    Write-Success "Feature filters desired state set successfully"
    
    # ========================================
    # STEP 2: Set Feature Filters
    # ========================================
    Write-SectionHeader "Setting Feature Filters"
    
    Invoke-DhCmd -DhCmdPath $script:Config.DHCMD_PATH `
                 -RpUri $script:Config.RP_URI `
                 -Command "SetFeatureFilter Gateway.EnableCertificateIssuance 1 /PaasV2:True"
    
    Invoke-DhCmd -DhCmdPath $script:Config.DHCMD_PATH `
                 -RpUri $script:Config.RP_URI `
                 -Command "SetFeatureFilter Gateway.UseDcSessionVNext.Mqtt 0 /PaasV2:True"
    
    Invoke-DhCmd -DhCmdPath $script:Config.DHCMD_PATH `
                 -RpUri $script:Config.RP_URI `
                 -Command "SetFeatureFilter Gateway.UseDcSessionVNext.LazyReauth.Amqp 0 /PaasV2:True"
    
    Invoke-DhCmd -DhCmdPath $script:Config.DHCMD_PATH `
                 -RpUri $script:Config.RP_URI `
                 -Command "SetFeatureFilter Gateway.UseDcSessionVNext.LazyReauth.Mqtt 0 /PaasV2:True"
    
    Invoke-DhCmd -DhCmdPath $script:Config.DHCMD_PATH `
                 -RpUri $script:Config.RP_URI `
                 -Command "SetFeatureFilter Gateway.UseDcSessionVNext.Amqp 0 /PaasV2:True"
    
    Invoke-DhCmd -DhCmdPath $script:Config.DHCMD_PATH `
                 -RpUri $script:Config.RP_URI `
                 -Command "SetFeatureFilter DcDeviceSessionV2 0 /PaasV2:True"
    
    Invoke-DhCmd -DhCmdPath $script:Config.DHCMD_PATH `
                 -RpUri $script:Config.RP_URI `
                 -Command "SetFeatureFilter DeviceAuthChangeNotification 0 /PaasV2:True"
    
    Invoke-DhCmd -DhCmdPath $script:Config.DHCMD_PATH `
                 -RpUri $script:Config.RP_URI `
                 -Command "SetFeatureFilter UseMockHttpHandlerForCertificateManagementClient 0 /PaasV2:True"
    
    Write-Success "Feature filters set successfully"
}

# Run main function
Main
