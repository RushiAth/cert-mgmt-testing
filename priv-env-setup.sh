#!/bin/bash
# This script sets up a private environment for development 

set -e  # Exit on error
set -u  # Exit on undefined variable

# ========================================
# CONFIGURATION VARIABLES
# ========================================
# You can either hardcode these values here or pass them as environment variables

# Required Configuration
RP_URI="${RP_URI:-}"
DHCMD_PATH="${DHCMD_PATH:-./DhCmd.exe}"
ALIAS="${ALIAS:-}"
REGION="${REGION:-}"
TENANT_ID="${TENANT_ID:-}"

# Hub Configuration
HUB_NAME="${HUB_NAME:-}"
ADR_NAMESPACE_RESOURCE_ID="${ADR_NAMESPACE_RESOURCE_ID:-}"
UAMI_RESOURCE_ID="${UAMI_RESOURCE_ID:-}"
API_VERSION="2025-08-01-preview"

# Device Configuration
DEVICE_NAME="${DEVICE_NAME:-}"

# Feature Configuration
CURRENT_DATE=$(date +%m/%d/%Y)

# ========================================
# VALIDATION
# ========================================
validate_required_vars() {
    local missing_vars=()
    
    if [ -z "$RP_URI" ]; then
        missing_vars+=("RP_URI")
    fi
    if [ -z "$ALIAS" ]; then
        missing_vars+=("ALIAS")
    fi
    if [ -z "$REGION" ]; then
        missing_vars+=("REGION")
    fi
    if [ -z "$TENANT_ID" ]; then
        missing_vars+=("TENANT_ID")
    fi
    if [ -z "$ADR_NAMESPACE_RESOURCE_ID" ]; then
        missing_vars+=("ADR_NAMESPACE_RESOURCE_ID")
    fi
    if [ -z "$UAMI_RESOURCE_ID" ]; then
        missing_vars+=("UAMI_RESOURCE_ID")
    fi
    
    if [ ${#missing_vars[@]} -gt 0 ]; then
        echo "ERROR: Missing required environment variables:"
        printf '  - %s\n' "${missing_vars[@]}"
        echo ""
        echo "Usage example:"
        echo "  export RP_URI='your-rp-uri'"
        echo "  export ALIAS='your-alias'"
        echo "  export REGION='your-region'"
        echo "  export TENANT_ID='your-tenant-id'"
        echo "  export ADR_NAMESPACE_RESOURCE_ID='your-adr-namespace-resource-id'"
        echo "  export UAMI_RESOURCE_ID='your-uami-resource-id'"
        echo "  ./priv-env-setup.sh"
        exit 1
    fi
}

# ========================================
# MAIN EXECUTION
# ========================================
echo "========================================="
echo "Private Environment Setup"
echo "========================================="
echo "RP URI: $RP_URI"
echo "Alias: $ALIAS"
echo "Region: $REGION"
echo "Tenant ID: $TENANT_ID"
echo "ADR Namespace Resource ID: $ADR_NAMESPACE_RESOURCE_ID"
echo "UAMI Resource ID: $UAMI_RESOURCE_ID"
echo "Hub Name: $HUB_NAME"
echo "Device Name: $DEVICE_NAME"
echo "========================================="
echo ""

validate_required_vars

# Set feature filter desired state
echo "Setting feature filter desired state..."
pwsh -Command "$DHCMD_PATH SetFeatureFilterDesiredState Gateway.EnableCertificateIssuance 2 $CURRENT_DATE $ALIAS /RpUri:'$RP_URI' /PaasV2:True"
pwsh -Command "$DHCMD_PATH SetFeatureFilterDesiredState UseMockHttpHandlerForCertificateManagementClient 2 $CURRENT_DATE $ALIAS /RpUri:'$RP_URI' /PaasV2:True"

# Set feature filter
echo "Setting feature filter..."
pwsh -Command "$DHCMD_PATH SetFeatureFilter Gateway.EnableCertificateIssuance 1 /RpUri:'$RP_URI' /PaasV2:True"
pwsh -Command "$DHCMD_PATH SetFeatureFilter UseMockHttpHandlerForCertificateManagementClient 1 /RpUri:'$RP_URI' /PaasV2:True"

# Create IoT Hub
echo "Creating IoT Hub..."
pwsh -Command "$DHCMD_PATH CreateIotHubPremiumOrGen2 $HUB_NAME 'GEN2' '$ADR_NAMESPACE_RESOURCE_ID' '$UAMI_RESOURCE_ID' '$REGION' '$TENANT_ID' /RpUri:'$RP_URI' /PaasV2:True /ApiVersion:$API_VERSION"

# Obtain IoT Hub Connection String
echo "Obtaining IoT Hub connection string..."
IOTHUB_CONNECTION_STRING=$(pwsh -Command "$DHCMD_PATH GetIotHub $HUB_NAME /RpUri:'$RP_URI' /PaasV2:True /ApiVersion:$API_VERSION" | grep 'IotHubConnectionString:' | awk -F': ' '{print $2}')
echo "IoT Hub Connection String: $IOTHUB_CONNECTION_STRING"

# Create Device (optional - only if DEVICE_NAME and CONNECTION_STRING are provided)
if [ -n "$DEVICE_NAME" ] && [ -n "$IOTHUB_CONNECTION_STRING" ]; then
    echo "Creating device..."
    pwsh -Command "$DHCMD_PATH CreateDeviceWithCACert $DEVICE_NAME /ConnectionString:'$IOTHUB_CONNECTION_STRING'"
else
    echo "Skipping device creation (DEVICE_NAME or IOTHUB_CONNECTION_STRING not provided)"
fi 

echo ""
echo "========================================="
echo "Setup completed successfully!"
echo "========================================="
