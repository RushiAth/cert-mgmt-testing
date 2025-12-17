# cert-mgmt-testing

A collection of scripts for IoT Hub certificate management testing, including hub creation, device provisioning, and certificate issuance via MQTT.

## Prerequisites

- PowerShell (pwsh) - Required for running DhCmd.exe commands
- OpenSSL - Required for certificate generation
- Python 3 with `paho-mqtt` - Required for MQTT scripts
- Bash shell - Required for shell scripts
- DhCmd.exe - IoT Hub management tool (path configured via `DHCMD_PATH` environment variable)

## Configuration

Copy `.env.example` to `.env` and configure the required environment variables:

```bash
cp .env.example .env
```

Key environment variables:
- `RP_URI` - RP Environment URI
- `DHCMD_PATH` - Path to DhCmd.exe
- `REGION` - Azure region
- `TENANT_ID` - Azure tenant ID
- `ADR_NAMESPACE_RESOURCE_ID` - ADR namespace resource ID
- `UAMI_RESOURCE_ID` - User-assigned managed identity resource ID
- `HUB_NAME` - IoT Hub name
- `DEVICE_NAME` - Device name
- `CERT_THUMBPRINT` - Certificate thumbprint (after installation)

## Scripts

### Main Scripts

#### `create_hubs_and_devices.sh` / `create_hubs_and_devices.ps1`
Creates multiple IoT Hubs with GEN2 capability and bulk adds devices to each hub.

**Features:**
- Creates specified number of IoT Hubs with GWv2 capability
- Waits for each hub to become Active
- Sets certificate with policy on each hub
- Bulk adds specified number of devices to each hub
- Generates device certificates for all devices
- Supports cleanup mode to delete created hubs

**Usage:**
```bash
# Bash
./create_hubs_and_devices.sh <NumHubs> <DevicesPerHub> [--cleanup]

# PowerShell
.\create_hubs_and_devices.ps1 -NumHubs 5 -DevicesPerHub 100
```

---

#### `cert_test.sh` / `cert_test.ps1`
End-to-end test script that creates an IoT Hub, device, and issues a certificate via MQTT.

**Features:**
1. Generates Root and Intermediate CA certificates
2. Installs certificates to LocalMachine\My store
3. Creates an IoT Hub (GEN2)
4. Sets the certificate on the hub
5. Creates a device certificate
6. Creates a device with certificate authentication
7. Issues a certificate via MQTT using `mqtt_issue_cert.py`

**Usage:**
```bash
# Bash
./cert_test.sh

# PowerShell
.\cert_test.ps1
```

---

#### `priv_env_setup.sh` / `priv_env_setup.ps1`
Sets up a private environment for IoT Hub development and testing by configuring feature filters.

**Features:**
- Sets feature filter desired states for certificate issuance
- Enables Gateway certificate issuance features for MQTT/AMQP
- Configures DcDeviceSessionV2 and related features

**Usage:**
```bash
# Bash
./priv_env_setup.sh

# PowerShell
.\priv_env_setup.ps1
```

---

#### `generate_certs.ps1`
Generates and installs CA certificates for testing.

**Features:**
- Generates Root and Intermediate CA certificates
- Converts certificates to PFX format
- Installs certificates to LocalMachine\My store
- Reports certificate thumbprint

**Usage:**
```powershell
.\generate_certs.ps1
```

---

### Python Scripts

#### `mqtt_issue_cert.py`
Sends an issueCertificate request to Azure IoT Hub via MQTT and waits for the response.

**Features:**
- Connects to IoT Hub using X.509 client certificate authentication
- Publishes certificate issuance request
- Waits for 202 (accepted) and 200 (success) responses
- Supports configurable timeout and API version

**Usage:**
```bash
python mqtt_issue_cert.py \
    --host <hub-host> \
    --device <device-name> \
    --ca-cert <ca-cert-path> \
    --device-cert <device-cert-path> \
    --device-key <device-key-path> \
    [--port 8883] \
    [--timeout 60]
```

---

#### `mqtt_credential_test.py`
Scenario-based MQTT credential management test script with multiple test scenarios.

**Scenarios:**
- `happy_path` - Issue a certificate with valid CSR (default)
- `disconnect_reconnect` - Disconnect after publishing, then reconnect to receive response

**Authentication Methods:**
- `--cert` - X.509 certificate authentication
- `--sas` - SAS token authentication

**Usage:**
```bash
python mqtt_credential_test.py happy_path --cert
python mqtt_credential_test.py disconnect_reconnect --sas
python mqtt_credential_test.py --list-scenarios
```

---

### Utility Scripts

#### `utils.sh`
Shared utility functions for Bash scripts.

**Functions:**
- `log_info`, `log_success`, `log_warning`, `log_error` - Colored logging
- `log_section_header` - Section header formatting
- `run_dhcmd` - Execute DhCmd commands via PowerShell
- `check_hub_status` - Check if hub is active
- `wait_for_hub_activation` - Poll until hub becomes active
- `check_pwsh` - Validate PowerShell installation
- `validate_numeric` - Validate numeric input
- `extract_value_from_output` - Parse DhCmd output
- `parse_json_field` - Extract JSON field values

---

#### `utils.ps1`
Shared utility functions for PowerShell scripts.

**Functions:**
- `Import-EnvFile` - Load environment variables from .env file
- `Write-SectionHeader`, `Write-Info`, `Write-Success`, `Write-Warning`, `Write-Error` - Formatted output
- `Invoke-DhCmd` - Execute DhCmd commands
- `Wait-ForHubActivation` - Poll until hub becomes active
- `Test-FileExists` - Check file existence
- `Get-CertificateThumbprint` - Get certificate thumbprint from store
- `Import-PfxToLocalMachine` - Import PFX certificate
- `Convert-PemToPfx` - Convert PEM to PFX format

---

### Certificate Generation Scripts (certGen/)

#### `certGen/certGen.sh`
Core certificate generation script for creating X.509 certificates for Azure IoT Hub CA cert deployment.

**Commands:**
- `create_root_and_intermediate` - Creates new root and intermediate CA certificates
- `create_verification_certificate <subjectName>` - Creates a verification certificate
- `create_device_certificate <subjectName>` - Creates a device certificate signed by root CA
- `create_device_certificate_from_intermediate <subjectName>` - Creates a device certificate signed by intermediate CA
- `create_edge_device_certificate <subjectName>` - Creates an edge device certificate

**Usage:**
```bash
cd certGen
./certGen.sh create_root_and_intermediate
./certGen.sh create_device_certificate_from_intermediate mydevice
```

> ⚠️ **Warning:** These certificates are for testing/prototyping only and MUST NOT be used in production.

---

#### `certGen/generate_device_certs.sh`
Batch generates multiple device certificates.

**Usage:**
```bash
./generate_device_certs.sh <number_of_devices> <target_directory> <device_name_prefix> <file_name_prefix>

# Example: Generate 10 certificates
./generate_device_certs.sh 10 ./output device sensor
# Creates: device00000 (CN) -> sensor00000.crt, sensor00000.key
```

---

## File Structure

```
├── .env.example                            # Environment variable template
├── .env                                    # Environment configuration (not tracked)
├── cert_test.sh/.ps1                       # End-to-end certificate test
├── create_hubs_and_devices.sh/.ps1         # Bulk hub and device creation
├── generate_certs.ps1                      # Certificate generation and installation
├── priv_env_setup.sh/.ps1                  # Private environment setup
├── mqtt_issue_cert.py                      # MQTT certificate issuance
├── mqtt_credential_test.py                 # MQTT credential testing scenarios
├── utils.sh/.ps1                           # Utility functions
├── IoTHubRootCA.crt.pem                    # IoT Hub Root CA certificate
├── certGen/                                # Certificate generation tools
│   ├── certGen.sh                          # Core cert generation script
│   ├── generate_device_certs.sh            # Batch device cert generation
│   ├── openssl_root_ca.cnf                 # OpenSSL config for root CA
│   └── openssl_device_intermediate_ca.cnf  # OpenSSL config for intermediate CA
├── requirements.txt                        # Python dependencies
└── pyproject.toml                          # Python project configuration
```

## Quick Start for Using Hubkick

1. **Set up environment variables from `.env.example`**

2. **Set up private environment (feature flags):**
   ```powershell
   .\priv_env_setup.ps1
   ```

3. **Make Root and Intermediate CA for Testing**
   ```powershell
   .\generate_certs.ps1
   # Add the certificate thumbprint to .env
   ```

4. **Create Hubs and Devices**
    ```powershell
   .\create_hubs_and_devices.ps1 -NumHubs 5 -DevicesPerHub 100
   ```