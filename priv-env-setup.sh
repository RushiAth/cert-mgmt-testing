#!/bin/bash
# This script sets up a private environment for development 

set -e  # Exit on error
set -u  # Exit on undefined variable

# Load utility functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

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

# Hub activation configuration
MAX_WAIT_ATTEMPTS="${MAX_WAIT_ATTEMPTS:-15}"
WAIT_INTERVAL="${WAIT_INTERVAL:-15}"

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
        log_error "Missing required environment variables:"
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
log_section_header "Private Environment Setup"
log_info "RP URI: $RP_URI"
log_info "Alias: $ALIAS"
log_info "Region: $REGION"
log_info "Tenant ID: $TENANT_ID"
log_info "ADR Namespace Resource ID: $ADR_NAMESPACE_RESOURCE_ID"
log_info "UAMI Resource ID: $UAMI_RESOURCE_ID"
log_info "Hub Name: $HUB_NAME"
log_info "Device Name: $DEVICE_NAME"

validate_required_vars

# Check PowerShell availability
log_section_header "Prerequisites Check"
if ! check_pwsh; then
    exit 1
fi

# Set feature filter desired state
log_section_header "Setting Feature Filter Desired State"
run_dhcmd "$DHCMD_PATH" "$RP_URI" "SetFeatureFilterDesiredState Gateway.EnableCertificateIssuance 2 $CURRENT_DATE $ALIAS /PaasV2:True" > /dev/null 2>&1
run_dhcmd "$DHCMD_PATH" "$RP_URI" "SetFeatureFilterDesiredState Gateway.UseDcSessionVNext.Mqtt 2 $CURRENT_DATE $ALIAS /PaasV2:True" > /dev/null 2>&1
run_dhcmd "$DHCMD_PATH" "$RP_URI" "SetFeatureFilterDesiredState Gateway.UseDcSessionVNext.LazyReauth.Amqp 2 $CURRENT_DATE $ALIAS /PaasV2:True" > /dev/null 2>&1
run_dhcmd "$DHCMD_PATH" "$RP_URI" "SetFeatureFilterDesiredState Gateway.UseDcSessionVNext.LazyReauth.Mqtt 2 $CURRENT_DATE $ALIAS /PaasV2:True" > /dev/null 2>&1
run_dhcmd "$DHCMD_PATH" "$RP_URI" "SetFeatureFilterDesiredState Gateway.UseDcSessionVNext.Amqp 2 $CURRENT_DATE $ALIAS /PaasV2:True" > /dev/null 2>&1
run_dhcmd "$DHCMD_PATH" "$RP_URI" "SetFeatureFilterDesiredState DcDeviceSessionV2 2 $CURRENT_DATE $ALIAS /PaasV2:True" > /dev/null 2>&1
run_dhcmd "$DHCMD_PATH" "$RP_URI" "SetFeatureFilterDesiredState DeviceAuthChangeNotification 2 $CURRENT_DATE $ALIAS /PaasV2:True" > /dev/null 2>&1
run_dhcmd "$DHCMD_PATH" "$RP_URI" "SetFeatureFilterDesiredState UseMockHttpHandlerForCertificateManagementClient 2 $CURRENT_DATE $ALIAS /PaasV2:True" > /dev/null 2>&1
log_success "Feature filters desired state set successfully"

# Set feature filter
log_section_header "Setting Feature Filters"
run_dhcmd "$DHCMD_PATH" "$RP_URI" "SetFeatureFilter Gateway.EnableCertificateIssuance 1 /PaasV2:True" > /dev/null 2>&1
run_dhcmd "$DHCMD_PATH" "$RP_URI" "SetFeatureFilter Gateway.UseDcSessionVNext.Mqtt 1 /PaasV2:True" > /dev/null 2>&1
run_dhcmd "$DHCMD_PATH" "$RP_URI" "SetFeatureFilter Gateway.UseDcSessionVNext.LazyReauth.Amqp 1 /PaasV2:True" > /dev/null 2>&1
run_dhcmd "$DHCMD_PATH" "$RP_URI" "SetFeatureFilter Gateway.UseDcSessionVNext.LazyReauth.Mqtt 1 /PaasV2:True" > /dev/null 2>&1
run_dhcmd "$DHCMD_PATH" "$RP_URI" "SetFeatureFilter Gateway.UseDcSessionVNext.Amqp 1 /PaasV2:True" > /dev/null 2>&1
run_dhcmd "$DHCMD_PATH" "$RP_URI" "SetFeatureFilter DcDeviceSessionV2 1 /PaasV2:True" > /dev/null 2>&1
run_dhcmd "$DHCMD_PATH" "$RP_URI" "SetFeatureFilter DeviceAuthChangeNotification 1 /PaasV2:True" > /dev/null 2>&1
run_dhcmd "$DHCMD_PATH" "$RP_URI" "SetFeatureFilter UseMockHttpHandlerForCertificateManagementClient 1 /PaasV2:True" > /dev/null 2>&1
log_success "Feature filters set successfully"

# Create IoT Hub
log_section_header "Creating IoT Hub"
log_info "Hub Name: $HUB_NAME"
log_info "Hub Type: GEN2"
log_info "Region: $REGION"
run_dhcmd "$DHCMD_PATH" "$RP_URI" "CreateIotHubPremiumOrGen2 $HUB_NAME 'GEN2' '$ADR_NAMESPACE_RESOURCE_ID' '$UAMI_RESOURCE_ID' '$REGION' '$TENANT_ID' /PaasV2:True /ApiVersion:$API_VERSION"
log_success "IoT Hub creation initiated successfully"

# Wait for hub to become active
log_section_header "Waiting for Hub Activation"
log_info "This may take several minutes..."
if ! wait_for_hub_activation "$HUB_NAME" "$DHCMD_PATH" "$RP_URI" "$API_VERSION"; then
    log_error "Hub failed to activate. Exiting."
    exit 1
fi

# Obtain IoT Hub Connection String
log_section_header "Obtaining Hub Connection String"
IOTHUB_CONNECTION_STRING=$(run_dhcmd "$DHCMD_PATH" "$RP_URI" "GetIotHub $HUB_NAME /PaasV2:True /ApiVersion:$API_VERSION" | grep 'IotHubConnectionString:' | awk -F': ' '{print $2}')
log_success "Connection string obtained successfully"
log_info "Connection String: $IOTHUB_CONNECTION_STRING"

# Create Device (optional - only if DEVICE_NAME and CONNECTION_STRING are provided)
if [ -n "$DEVICE_NAME" ] && [ -n "$IOTHUB_CONNECTION_STRING" ]; then
    log_section_header "Creating Device"
    log_info "Device Name: $DEVICE_NAME"
    log_info "Authentication: CA Certificate"
    pwsh -Command "$DHCMD_PATH CreateDeviceWithCACert $DEVICE_NAME /ConnectionString:\"$IOTHUB_CONNECTION_STRING\""
    log_success "Device created successfully: $DEVICE_NAME"
else
    log_section_header "Device Creation"
    log_warning "Skipping device creation (DEVICE_NAME or IOTHUB_CONNECTION_STRING not provided)"
fi 

# Generate Root and Intermediate CA Certificates
log_section_header "Generating CA Certificates"
log_info "Generating Root and Intermediate CA certificates..."
chmod +x ./certGen/certGen.sh
cd certGen && ./certGen.sh create_root_and_intermediate
cd ..
log_success "Root and Intermediate CA certificates generated successfully"

# Register Root CA and Capture Verification Code
log_section_header "Registering Intermediate CA Certificate"
log_info "Registering certificate with IoT Hub..."
INT_CA_OUTPUT=$(run_dhcmd "$DHCMD_PATH" "$RP_URI" "RegisterCACert $HUB_NAME './certGen/certs/azure-iot-test-only.intermediate.cert.pem' 'iothub-gen2-intermediate-ca-test' /ApiVersion:$API_VERSION")
echo "$INT_CA_OUTPUT"

VERIFICATION_CODE=$(extract_value_from_output "$INT_CA_OUTPUT" "Verification Code:")
log_success "Intermediate CA registered successfully"
log_info "Verification Code: $VERIFICATION_CODE"

# Verify Root CA
log_section_header "Creating Verification Certificate"
log_info "Generating verification certificate with code: $VERIFICATION_CODE"
cd certGen && ./certGen.sh create_verification_certificate "$VERIFICATION_CODE"
cd ..
log_success "Verification certificate created successfully"

# Get Certificates and Parse ETag
log_section_header "Retrieving Certificate Information"
log_info "Fetching certificate details from IoT Hub..."
GET_CERTS_OUTPUT=$(run_dhcmd "$DHCMD_PATH" "$RP_URI" "GetCertificates $HUB_NAME /ApiVersion:$API_VERSION")
echo "$GET_CERTS_OUTPUT"
echo ""

# Parse the ETag from the JSON output using utility function
CERTIFICATE_ETAG=$(parse_json_field "$GET_CERTS_OUTPUT" "etag")

if [ -z "$CERTIFICATE_ETAG" ]; then
    log_warning "Could not extract ETag from GetCertificates output"
    log_warning "You may need to manually retrieve the ETag value"
else
    log_success "Successfully extracted Certificate ETag"
    log_info "ETag: $CERTIFICATE_ETAG"
fi

# Verify CA Certificate
log_section_header "Verifying CA Certificate"
log_info "Submitting verification certificate to IoT Hub..."
run_dhcmd "$DHCMD_PATH" "$RP_URI" "VerifyCACert $HUB_NAME './certGen/certs/verification-code.cert.pem' 'iothub-gen2-intermediate-ca-test' '$CERTIFICATE_ETAG' /ApiVersion:$API_VERSION"
log_success "CA Certificate verified successfully"

# Create Device Certificate
log_section_header "Creating Device Certificate"
log_info "Generating device certificate for: $DEVICE_NAME"
cd certGen && ./certGen.sh create_device_certificate_from_intermediate "$DEVICE_NAME"
cd certs 

log_info "Converting certificate to CRT format..."
openssl x509 -in new-device.cert.pem -out $DEVICE_NAME.crt 

cd ../private

log_info "Renaming private key..."
mv new-device.key.pem $DEVICE_NAME.key

cd ../..

log_success "Device certificate created successfully"

# Final Summary
log_section_header "Setup Complete!"
log_success "Private environment setup completed successfully"
echo ""
log_info "Summary:"
log_info "  Hub Name: $HUB_NAME"
log_info "  Device Name: $DEVICE_NAME"
log_info "  Device Certificate: ./certGen/certs/$DEVICE_NAME.crt"
log_info "  Device Private Key: ./certGen/private/$DEVICE_NAME.key"
echo ""
log_info "If running locally, make sure to add the hub hostname to your /etc/hosts file"