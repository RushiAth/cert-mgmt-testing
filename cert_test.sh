#!/bin/bash

# ---------------------------------------------------------------
# Script to create an IoT Hub and device using DhCmd and then send issueCertificate request
# ---------------------------------------------------------------

# Source utility functions
source "$(dirname "$0")/utils.sh"

# ========================================
# CONFIGURATION - Hardcode values here if desired
# ========================================
# If these are set, they will be used instead of command-line arguments
# Leave empty ("") to require command-line arguments
RP_URI="${RP_URI:-}"
DHCMD_PATH="${DHCMD_PATH:-}"

HUB_NAME="${HUB_NAME:-}"
DEVICE_NAME="${DEVICE_NAME:-}"

REGION="${REGION:-}"
TENANT_ID="${TENANT_ID:-}"
ADR_NAMESPACE_RESOURCE_ID="${ADR_NAMESPACE_RESOURCE_ID:-}"
DEVICE_RESOURCE_ID="${ADR_NAMESPACE_RESOURCE_ID}/devices/${DEVICE_NAME}"
POLICY_RESOURCE_ID="${ADR_NAMESPACE_RESOURCE_ID}/credentials/default/policies/default"
UAMI_RESOURCE_ID="${UAMI_RESOURCE_ID:-}"

CERT_NAME="iothub-gen2-intermediate-ca-test"
CERT_THUMBPRINT="${CERT_THUMBPRINT:-}"

API_VERSION="2025-08-01-preview"
CURRENT_DATE=$(date +%m/%d/%Y)

MAX_WAIT_ATTEMPTS="${MAX_WAIT_ATTEMPTS:-15}"
WAIT_INTERVAL="${WAIT_INTERVAL:-15}"

# Certificate paths (defined early for use throughout script)
ROOT_CERT_PATH="./certGen/certs/azure-iot-test-only.root.ca.cert.pem"
INTERMEDIATE_CERT_PATH="./certGen/certs/azure-iot-test-only.intermediate.cert.pem"
CERT_PEM_PATH="./certGen/certs/azure-iot-test-only.intermediate.cert.pem"
CERT_PFX_PATH="./certGen/certs/azure-iot-test-only.intermediate.cert.pfx"
CERT_KEY_PATH="./certGen/private/azure-iot-test-only.intermediate.key.pem"
CERT_PASSWORD="1234"

# ========================================
# VALIDATION
# ========================================
validate_required_vars() {
    local missing_vars=()
    
    if [ -z "$RP_URI" ]; then
        missing_vars+=("RP_URI")
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

# ========================================
# STEP 1: Generate and Install CA Certificates
# ========================================

# Generate Root and Intermediate CA Certificates
log_section_header "Step 1a: Generating CA Certificates"

# Check if Root and Intermediate CA certificates already exist
if [ -f "$ROOT_CERT_PATH" ] && [ -f "$INTERMEDIATE_CERT_PATH" ]; then
    log_warning "Root and Intermediate CA certificates already exist. Skipping generation."
    log_info "  Root CA: $ROOT_CERT_PATH"
    log_info "  Intermediate CA: $INTERMEDIATE_CERT_PATH"
else
    log_info "Generating Root and Intermediate CA certificates..."
    chmod +x ./certGen/certGen.sh
    cd certGen && ./certGen.sh create_root_and_intermediate
    cd ..
    log_success "Root and Intermediate CA certificates generated successfully"
fi

# Check if certificate file exists after generation
if [ ! -f "$CERT_PEM_PATH" ]; then
    log_error "Certificate file not found: $CERT_PEM_PATH"
    log_error "Please ensure CA certificates were generated successfully."
    exit 1
fi

# Convert Intermediate CA certificate to PFX format
log_info "Checking if PFX file exists..."
if [ -f "$CERT_PFX_PATH" ]; then
    log_warning "PFX file already exists: $CERT_PFX_PATH"
else
    log_info "Converting Intermediate CA certificate to PFX format..."
    openssl pkcs12 -export \
        -out "$CERT_PFX_PATH" \
        -inkey "$CERT_KEY_PATH" \
        -in "$CERT_PEM_PATH" \
        -password pass:$CERT_PASSWORD
    
    if [ $? -eq 0 ]; then
        log_success "PFX file created: $CERT_PFX_PATH"
    else
        log_error "Failed to convert certificate to PFX format"
        exit 1
    fi
fi

# Install Certificate on Local Machine
log_section_header "Step 1b: Checking Local Certificate Installation"

# Check if certificate is already installed in LocalMachine\My store
log_info "Checking if certificate is already installed in LocalMachine\\My store..."

if [[ -n "$CERT_THUMBPRINT" ]]; then
    log_success "Certificate is already installed in LocalMachine\\My store."
    log_info "Certificate thumbprint: $CERT_THUMBPRINT"
else
    log_warning "Certificate '$CERT_NAME' is NOT installed in LocalMachine\\My store."
    log_info ""
    log_info "======================================================================"
    log_info "MANUAL STEP REQUIRED: Install the Intermediate CA Certificate"
    log_info "======================================================================"
    log_info ""
    log_info "Please install the certificate to LocalMachine\\My store using one of the following methods:"
    log_info ""
    log_info "Using PowerShell (Run as Administrator on Windows):"
    log_info "  \$password = ConvertTo-SecureString -String '$CERT_PASSWORD' -Force -AsPlainText"
    log_info "  Import-PfxCertificate -FilePath '$CERT_PFX_PATH' -CertStoreLocation 'Cert:\\LocalMachine\\My' -Password \$password"
    log_info ""
    log_info "NOTE: Installing to LocalMachine store requires Administrator/root privileges."
    log_info "======================================================================"
    log_info ""
    log_error "Please install the certificate manually, set the thumbprint env variable, and re-run this script."
    exit 1
fi

# ========================================
# STEP 2: IoT Hub Setup
# ========================================

# Check if IoT Hub already exists
log_section_header "Step 2: Checking IoT Hub Existence"
log_info "Checking if IoT Hub '$HUB_NAME' already exists..."

HUB_EXISTS=$(run_dhcmd "$DHCMD_PATH" "$RP_URI" "GetIotHub $HUB_NAME /ApiVersion:$API_VERSION" 2>&1)
if echo "$HUB_EXISTS" | grep -q "IotHubConnectionString:" || echo "$HUB_EXISTS" | grep -q "Name.*$HUB_NAME"; then
    log_warning "IoT Hub '$HUB_NAME' already exists. Skipping creation."
    SKIP_HUB_CREATION=true
else
    log_info "IoT Hub '$HUB_NAME' does not exist. Proceeding with creation."
    SKIP_HUB_CREATION=false
fi

# Create IoT Hub (if not exists)
if [ "$SKIP_HUB_CREATION" = false ]; then
    log_section_header "Creating IoT Hub"
    log_info "Hub Name: $HUB_NAME"
    log_info "Hub Type: GEN2"
    log_info "Region: $REGION"
    run_dhcmd "$DHCMD_PATH" "$RP_URI" "CreateIotHubPremiumOrGen2 $HUB_NAME 'GEN2' '$ADR_NAMESPACE_RESOURCE_ID' '$UAMI_RESOURCE_ID' '$REGION' '$TENANT_ID' /ApiVersion:$API_VERSION"
    log_success "IoT Hub creation initiated successfully"

    # Wait for hub to become active
    log_section_header "Waiting for Hub Activation"
    log_info "This may take several minutes..."
    if ! wait_for_hub_activation "$HUB_NAME" "$DHCMD_PATH" "$RP_URI" "$API_VERSION"; then
        log_error "Hub failed to activate. Exiting."
        exit 1
    fi
else
    log_section_header "Skipping Hub Creation"
    log_info "Using existing IoT Hub: $HUB_NAME"
fi

# ========================================
# STEP 3: Obtain Connection String
# ========================================

# Obtain IoT Hub Connection String
log_section_header "Step 3: Obtaining Hub Connection String"
IOTHUB_CONNECTION_STRING=$(run_dhcmd "$DHCMD_PATH" "$RP_URI" "GetIotHub $HUB_NAME /ApiVersion:$API_VERSION" | grep 'IotHubConnectionString:' | awk -F': ' '{print $2}')
log_success "Connection string obtained successfully"
log_info "Connection String: $IOTHUB_CONNECTION_STRING"

# ========================================
# STEP 4: Set Certificate with IoT Hub
# ========================================

# Set Certificate
log_section_header "Step 4: Setting Intermediate CA Certificate"

# Check if certificate is already set on the hub
log_info "Checking if certificate is already set on IoT Hub..."
CERT_SET_RESULT=$(run_dhcmd "$DHCMD_PATH" "$RP_URI" "GetCertificate $HUB_NAME $CERT_NAME /ApiVersion:$API_VERSION" 2>&1)
if echo "$CERT_SET_RESULT" | grep -q "$CERT_THUMBPRINT"; then
    log_warning "Certificate '$CERT_NAME' is already set on IoT Hub. Skipping."
else
    log_info "Setting certificate with IoT Hub..."
    run_dhcmd "$DHCMD_PATH" "$RP_URI" "SetCertificateWithPolicy $HUB_NAME $CERT_NAME $CERT_THUMBPRINT My LocalMachine $POLICY_RESOURCE_ID /ApiVersion:$API_VERSION"
    log_success "Certificate set successfully"
fi

# ========================================
# STEP 5: Create Device Certificate
# ========================================

# Create Device Certificate
log_section_header "Step 5: Creating Device Certificate"

DEVICE_CERT_PATH="./certGen/certs/${DEVICE_NAME}.crt"
DEVICE_KEY_PATH="./certGen/private/${DEVICE_NAME}.key"

# Check if device certificate already exists
if [ -f "$DEVICE_CERT_PATH" ] && [ -f "$DEVICE_KEY_PATH" ]; then
    log_warning "Device certificate already exists. Skipping generation."
    log_info "  Device Cert: $DEVICE_CERT_PATH"
    log_info "  Device Key: $DEVICE_KEY_PATH"
else
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
fi

# ========================================
# STEP 6: Create Device
# ========================================

# Create Device
log_section_header "Step 6: Creating Device"

if [ -z "$DEVICE_NAME" ] || [ -z "$IOTHUB_CONNECTION_STRING" ] || [ -z "$DEVICE_RESOURCE_ID" ] || [ -z "$POLICY_RESOURCE_ID" ]; then
    log_error "DEVICE_NAME or IOTHUB_CONNECTION_STRING or ADR_NAMESPACE_RESOURCE_ID not provided"
    exit 1
fi

# Check if device already exists
log_info "Checking if device '$DEVICE_NAME' already exists..."
DEVICE_EXISTS_RESULT=$(pwsh -Command "$DHCMD_PATH GetDevice $DEVICE_NAME /ConnectionString:\"$IOTHUB_CONNECTION_STRING\" /ApiVersion:$API_VERSION" 2>&1)
if echo "$DEVICE_EXISTS_RESULT" | grep -q "DeviceId.*$DEVICE_NAME"; then
    log_warning "Device '$DEVICE_NAME' already exists. Skipping creation."
else
    log_info "Device Name: $DEVICE_NAME"
    log_info "Authentication: CA Certificate"
    run_dhcmd "$DHCMD_PATH" "$RP_URI" "CreateDeviceWithHttpAndCertAuth $HUB_NAME $DEVICE_NAME \"default\" /ApiVersion:$API_VERSION"
    log_success "Device created successfully: $DEVICE_NAME"
fi

# ========================================
# STEP 7: Issue Device Certificate via MQTT
# ========================================

# Make MQTT Call for issueCertificate
log_section_header "Step 7: Issuing Device Certificate via MQTT"
log_info "Sending issueCertificate request for device: $DEVICE_NAME"

# MQTT Configuration
MQTT_HOST="${HUB_NAME}.azure-devices-int.net"
MQTT_PORT=8883
MQTT_CA_CERT="./IoTHubRootCA.crt.pem"
MQTT_DEVICE_CERT="./certGen/certs/${DEVICE_NAME}.crt"
MQTT_DEVICE_KEY="./certGen/private/${DEVICE_NAME}.key"

log_info "MQTT Host: $MQTT_HOST"
log_info "MQTT Port: $MQTT_PORT"
log_info "Device: $DEVICE_NAME"
log_info "CA Cert: $MQTT_CA_CERT"
log_info "Device Cert: $MQTT_DEVICE_CERT"
log_info "Device Key: $MQTT_DEVICE_KEY"

# Run the Python MQTT script
log_info "Running MQTT certificate issuance script..."
python3 ./mqtt_issue_cert.py \
    --host "$MQTT_HOST" \
    --device "$DEVICE_NAME" \
    --ca-cert "$MQTT_CA_CERT" \
    --device-cert "$MQTT_DEVICE_CERT" \
    --device-key "$MQTT_DEVICE_KEY" \
    --port "$MQTT_PORT" \
    --timeout 90

MQTT_EXIT_CODE=$?

if [ $MQTT_EXIT_CODE -eq 0 ]; then
    log_success "Certificate issuance process completed successfully"
else
    log_error "Certificate issuance failed (exit code: $MQTT_EXIT_CODE)"
    exit 1
fi
