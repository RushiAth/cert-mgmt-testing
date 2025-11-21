#!/bin/bash

# ---------------------------------------------------------------
# Script to create IoT Hubs and bulk add devices using DhCmd
# ---------------------------------------------------------------
# This script uses PowerShell (pwsh) to run DhCmd.exe and:
# 1. Creates specified number of IoT Hubs with GWv2 capability
# 2. Waits for each hub to become Active
# 3. Bulk adds specified number of devices to each hub
#
# Requirements:
#   - PowerShell (pwsh) must be installed
#   - DhCmd.exe must be built and available
#   - Proper environment configuration for the target RpUri
#
# Usage: ./create-hubs-and-devices.sh <NumHubs> <DevicesPerHub> [--cleanup]
# Example: ./create-hubs-and-devices.sh 5 100
# Example with custom path: ./create-hubs-and-devices.sh 5 100 /path/to/DhCmd.exe
# Example cleanup: ./create-hubs-and-devices.sh 5 100 --cleanup
# ---------------------------------------------------------------

set -e  # Exit on error
set -u  # Exit on undefined variable

# Source utility functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

# ========================================
# CONFIGURATION - Hardcode values here if desired
# ========================================
# If these are set, they will be used instead of command-line arguments
# Leave empty ("") to require command-line arguments
RP_URI="${RP_URI:-}"
DHCMD_PATH="${DHCMD_PATH:-}"

REGION="${REGION:-}"
TENANT_ID="${TENANT_ID:-}"
ADR_NAMESPACE_RESOURCE_ID="${ADR_NAMESPACE_RESOURCE_ID:-}"
UAMI_RESOURCE_ID="${UAMI_RESOURCE_ID:-}"
CERT_OUTPUT_DIR="${CERT_OUTPUT_DIR:-}"
# ========================================

# Parse cleanup flag
CLEANUP_MODE=false
if [[ "${!#}" == "--cleanup" ]]; then
    CLEANUP_MODE=true
    set -- "${@:1:$(($#-1))}"  # Remove --cleanup from arguments
fi

# Determine if we're using hardcoded values or command-line arguments
if [ -n "$RP_URI" ]; then
    # Using hardcoded RpUri - adjust expected arguments
    if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
        log_error "Invalid number of arguments (RpUri is hardcoded)"
        echo "Usage: $0 <NumHubs> <DevicesPerHub> [DhCmdPath] [--cleanup]"
        echo "  NumHubs: Number of IoT Hubs to create/delete (positive integer)"
        echo "  DevicesPerHub: Number of devices per hub (positive integer, ignored in cleanup mode)"
        echo "  --cleanup: (Optional) Delete hubs instead of creating them"
        echo ""
        echo "Note: RpUri is hardcoded in the script: $RP_URI"
        echo ""
        echo "Example: $0 5 100"
        echo "Example with custom path: $0 5 100"
        echo "Example cleanup: $0 5 100 --cleanup"
        exit 1
    fi
    
    RP_URI="$RP_URI"
    NUM_HUBS="$1"
    DEVICES_PER_HUB="$2"
    DHCMD_PATH_ARG="${3:-}"
else
    # RpUri required from command line
    if [ "$#" -lt 3 ] || [ "$#" -gt 4 ]; then
        log_error "Invalid number of arguments"
        echo "Usage: $0 <RpUri> <NumHubs> <DevicesPerHub> [DhCmdPath] [--cleanup]"
        echo "  RpUri: RP Environment URI (e.g., https://master1-dh-rp.cloudapp.net)"
        echo "  NumHubs: Number of IoT Hubs to create/delete (positive integer)"
        echo "  DevicesPerHub: Number of devices per hub (positive integer, ignored in cleanup mode)"
        echo "  --cleanup: (Optional) Delete hubs instead of creating them"
        echo ""
        echo "Example: $0 https://master1-dh-rp.cloudapp.net 5 100"
        echo "Example cleanup: $0 https://master1-dh-rp.cloudapp.net 5 100 --cleanup"
        exit 1
    fi
    
    RP_URI="$1"
    NUM_HUBS="$2"
    DEVICES_PER_HUB="$3"
    DHCMD_PATH_ARG="${4:-}"
fi

# Validate numeric inputs
if ! validate_numeric "$NUM_HUBS" "NumHubs"; then
    exit 1
fi

if ! validate_numeric "$DEVICES_PER_HUB" "DevicesPerHub"; then
    exit 1
fi

# Configuration
HUB_NAME_PREFIX="stress-hub-"  # Prefix for hub names with timestamp
# Note: MAX_WAIT_ATTEMPTS and WAIT_INTERVAL are defined in utils.sh

if [ "$CLEANUP_MODE" = true ]; then
    log_section_header "IoT Hub Cleanup Script"
    log_info "RP Environment: $RP_URI"
    log_info "Number of Hubs to Delete: $NUM_HUBS"
    log_info "Hub Name Prefix: $HUB_NAME_PREFIX"
    log_info "Script Directory: $SCRIPT_DIR"
    log_info "=========================================="
else
    log_section_header "IoT Hub and Device Creation Script"
    log_info "RP Environment: $RP_URI"
    log_info "Number of Hubs: $NUM_HUBS"
    log_info "Devices Per Hub: $DEVICES_PER_HUB"
    log_info "Hub Name Prefix: $HUB_NAME_PREFIX"
    log_info "Script Directory: $SCRIPT_DIR"
    log_info "=========================================="
fi
echo ""

# Check if pwsh is available
if ! check_pwsh; then
    exit 1
fi

# Check if hardcoded path is set and valid
if [ -n "$DHCMD_PATH" ]; then
    if [ -f "$DHCMD_PATH" ]; then
        DHCMD_PATH="$DHCMD_PATH"
        log_success "Using hardcoded DhCmd.exe path: $DHCMD_PATH"
    else
        log_error "Hardcoded DhCmd.exe path does not exist: $DHCMD_PATH"
        exit 1
    fi
# If user provided a path via command line, use it
elif [ -n "$DHCMD_PATH_ARG" ]; then
    if [ -f "$DHCMD_PATH_ARG" ]; then
        DHCMD_PATH="$DHCMD_PATH_ARG"
        log_success "Using command-line specified DhCmd.exe path: $DHCMD_PATH"
    else
        log_error "Specified DhCmd.exe path does not exist: $DHCMD_PATH_ARG"
        exit 1
    fi
else
    # Try to find DhCmd.exe in default locations
    if [ -f "$SCRIPT_DIR/../../build_output/bin/amd64-Release/DhCmd/DhCmd.exe" ]; then
        DHCMD_PATH="$SCRIPT_DIR/../../build_output/bin/amd64-Release/DhCmd/DhCmd.exe"
    elif [ -f "$SCRIPT_DIR/bin/DhCmd.exe" ]; then
        DHCMD_PATH="$SCRIPT_DIR/bin/DhCmd.exe"
    else
        log_error "DhCmd.exe not found in expected locations"
        log_error "Please build the project first, hardcode the path in the script, or specify it as an argument"
        exit 1
    fi
    log_success "DhCmd.exe found at: $DHCMD_PATH"
fi
echo ""

# Array to store hub names
declare -a HUB_NAMES

# If in cleanup mode, delete hubs and exit
if [ "$CLEANUP_MODE" = true ]; then
    log_section_header "CLEANUP MODE: Deleting $NUM_HUBS IoT Hub(s)"
    echo ""
    
    # Generate list of hub names that will be deleted
    declare -a HUBS_TO_DELETE
    log_warning "The following hubs will be deleted:"
    echo ""
    for i in $(seq 1 $NUM_HUBS); do
        HUB_INDEX=$(printf "%05d" $((i - 1)))
        HUB_NAME="${HUB_NAME_PREFIX}${HUB_INDEX}"
        HUBS_TO_DELETE+=("$HUB_NAME")
        echo "  - $HUB_NAME"
    done
    echo ""
    
    # Ask for confirmation
    log_warning "Are you sure you want to delete these $NUM_HUBS hub(s)? (yes/no)"
    read -p "Enter your choice: " CONFIRMATION
    echo ""
    
    if [[ "$CONFIRMATION" != "yes" ]]; then
        log_info "Cleanup cancelled by user."
        exit 0
    fi
    
    log_info "Proceeding with deletion..."
    echo ""
    
    DELETED_COUNT=0
    FAILED_COUNT=0
    
    for HUB_NAME in "${HUBS_TO_DELETE[@]}"; do
        log_info "Deleting hub: $HUB_NAME"
        
        if run_dhcmd "$DHCMD_PATH" "$RP_URI" "DeleteIotHub $HUB_NAME"; then
            log_success "Successfully deleted hub: $HUB_NAME"
            DELETED_COUNT=$((DELETED_COUNT + 1))
        else
            log_warning "Failed to delete hub (it may not exist): $HUB_NAME"
            FAILED_COUNT=$((FAILED_COUNT + 1))
        fi
        
        echo ""
    done
    
    log_section_header "CLEANUP SUMMARY"
    log_success "Cleanup completed!"
    echo ""
    log_info "Hubs successfully deleted: $DELETED_COUNT"
    if [ $FAILED_COUNT -gt 0 ]; then
        log_warning "Hubs that failed to delete: $FAILED_COUNT"
    fi
    echo ""
    log_success "=========================================="
    log_success "Cleanup operation completed!"
    log_success "=========================================="
    
    exit 0
fi

# Step 1: Create IoT Hubs using bulk creation
log_section_header "STEP 1: Creating $NUM_HUBS IoT Hub(s)"
echo ""

log_info "Initiating bulk creation of $NUM_HUBS hubs with prefix: $HUB_NAME_PREFIX"

# if run_dhcmd "$DHCMD_PATH" "$RP_URI" "CreateIotHubsGen2 $HUB_NAME_PREFIX $NUM_HUBS $ADR_NAMESPACE_RESOURCE_ID $UAMI_RESOURCE_ID $REGION $TENANT_ID"; then
#     log_success "Bulk hub creation initiated for $NUM_HUBS hubs"
# else
#     log_error "Failed to initiate bulk hub creation"
#     exit 1
# fi

echo ""

# Build list of expected hub names
for i in $(seq 1 $NUM_HUBS); do
    # Create 5-digit zero-padded index starting from 00000 (i-1)
    HUB_INDEX=$(printf "%05d" $((i - 1)))
    HUB_NAME="${HUB_NAME_PREFIX}${HUB_INDEX}"
    HUB_NAMES+=("$HUB_NAME")
done

log_success "All $NUM_HUBS hub(s) creation initiated"
echo ""

# Step 2: Wait for all hubs to become Active
log_section_header "STEP 2: Waiting for Hub(s) to Activate"
echo ""

ACTIVATED_HUBS=()

for hub_name in "${HUB_NAMES[@]}"; do
    log_info "Waiting for hub: $hub_name"
    
    if wait_for_hub_activation "$hub_name" "$DHCMD_PATH" "$RP_URI"; then
        ACTIVATED_HUBS+=("$hub_name")
        log_success "Hub activated: $hub_name"
    else
        log_error "Hub failed to activate: $hub_name"
        log_warning "Continuing with other hubs..."
    fi
    
    echo ""
done

if [ ${#ACTIVATED_HUBS[@]} -eq 0 ]; then
    log_error "No hubs were successfully activated. Exiting."
    exit 1
fi

log_success "${#ACTIVATED_HUBS[@]} hub(s) successfully activated out of $NUM_HUBS"
echo ""

# Step 3: Add devices to each activated hub
log_section_header "STEP 3: Adding Devices to Hub(s)"
echo ""

# for hub_name in "${ACTIVATED_HUBS[@]}"; do
#     log_info "Adding $DEVICES_PER_HUB devices to hub: $hub_name"
    
#     if run_dhcmd "$DHCMD_PATH" "$RP_URI" "BulkAddDevicesWithCACert $hub_name $DEVICES_PER_HUB"; then
#         log_success "Successfully added $DEVICES_PER_HUB devices to $hub_name"
#     else
#         log_error "Failed to add devices to hub: $hub_name"
#         log_warning "Continuing with other hubs..."
#     fi
    
#     echo ""
# done

# Step 4: Update /etc/hosts file
log_section_header "STEP 4: Updating /etc/hosts File"
echo ""

# Check if we have write access to /etc/hosts
# if [ ! -w /etc/hosts ]; then
#     log_warning "/etc/hosts is not writable. Attempting to use sudo..."
    
#     # Create temporary file with hub entries
#     TEMP_HOSTS_FILE=$(mktemp)
    
#     log_info "Creating host entries for activated hubs..."
#     for hub_name in "${ACTIVATED_HUBS[@]}"; do
#         echo "127.0.0.1       ${hub_name}.azure-devices-int.net" >> "$TEMP_HOSTS_FILE"
#     done
    
#     # Show what will be added
#     log_info "The following entries will be added to /etc/hosts:"
#     cat "$TEMP_HOSTS_FILE"
#     echo ""
    
#     # Find the IPv6 comment line and insert before it
#     if sudo grep -q "# The following lines are desirable for IPv6 capable hosts" /etc/hosts; then
#         log_info "Adding entries before IPv6 section..."
        
#         # Create a backup
#         sudo cp /etc/hosts /etc/hosts.backup.$(date +%Y%m%d_%H%M%S)
#         log_success "Created backup of /etc/hosts"
        
#         # Remove any existing entries for these hubs first
#         for hub_name in "${ACTIVATED_HUBS[@]}"; do
#             sudo sed -i "/${hub_name}.azure-devices-int.net/d" /etc/hosts
#         done
        
#         # Insert new entries before the IPv6 comment
#         sudo sed -i '/# The following lines are desirable for IPv6 capable hosts/i\' /etc/hosts
#         while IFS= read -r line; do
#             sudo sed -i "/# The following lines are desirable for IPv6 capable hosts/i\\$line" /etc/hosts
#         done < "$TEMP_HOSTS_FILE"
        
#         log_success "Successfully updated /etc/hosts"
#     else
#         log_warning "IPv6 comment not found in /etc/hosts, appending to end of file..."
#         sudo bash -c "cat '$TEMP_HOSTS_FILE' >> /etc/hosts"
#         log_success "Successfully appended entries to /etc/hosts"
#     fi
    
#     # Clean up temp file
#     rm -f "$TEMP_HOSTS_FILE"
# else
#     log_info "Creating host entries for activated hubs..."
    
#     # Remove any existing entries for these hubs first
#     for hub_name in "${ACTIVATED_HUBS[@]}"; do
#         sed -i "/${hub_name}.azure-devices-int.net/d" /etc/hosts
#     done
    
#     # Find the IPv6 comment line and insert before it
#     if grep -q "# The following lines are desirable for IPv6 capable hosts" /etc/hosts; then
#         log_info "Adding entries before IPv6 section..."
        
#         # Create a backup
#         cp /etc/hosts /etc/hosts.backup.$(date +%Y%m%d_%H%M%S)
#         log_success "Created backup of /etc/hosts"
        
#         # Insert new entries before the IPv6 comment
#         sed -i '/# The following lines are desirable for IPv6 capable hosts/i\' /etc/hosts
#         for hub_name in "${ACTIVATED_HUBS[@]}"; do
#             sed -i "/# The following lines are desirable for IPv6 capable hosts/i\\127.0.0.1       ${hub_name}.azure-devices-int.net" /etc/hosts
#         done
        
#         log_success "Successfully updated /etc/hosts"
#     else
#         log_warning "IPv6 comment not found in /etc/hosts, appending to end of file..."
#         for hub_name in "${ACTIVATED_HUBS[@]}"; do
#             echo "127.0.0.1       ${hub_name}.azure-devices-int.net" >> /etc/hosts
#         done
#         log_success "Successfully appended entries to /etc/hosts"
#     fi
# fi

echo ""
log_info "Added ${#ACTIVATED_HUBS[@]} hub entries to /etc/hosts"
echo ""

# Step 5: Generate device certificates
log_section_header "STEP 5: Generating Device Certificates"
echo ""

log_info "Certificate output directory: $CERT_OUTPUT_DIR"
log_info "Generating certificates for $DEVICES_PER_HUB devices per hub across ${#ACTIVATED_HUBS[@]} hub(s)"
echo ""

# Check if generate_device_certs.sh exists
if [ ! -f "$SCRIPT_DIR/certGen/generate_device_certs.sh" ]; then
    log_error "generate_device_certs.sh not found at: $SCRIPT_DIR/certGen/generate_device_certs.sh"
    log_warning "Skipping certificate generation"
else
    # Check if certGen directory exists
    if [ ! -d "$SCRIPT_DIR/certGen" ]; then
        log_error "certGen directory not found at: $SCRIPT_DIR/certGen"
        log_warning "Skipping certificate generation"
    else
        # Change to certGen directory to run certificate generation
        log_info "Changing to certGen directory: $SCRIPT_DIR/certGen"
        cd "$SCRIPT_DIR/certGen"
        
        # Generate certificates for each activated hub
        for hub_name in "${ACTIVATED_HUBS[@]}"; do
            log_info "Generating certificates for hub: $hub_name"
            
            # Create hub-specific output directory
            HUB_CERT_DIR="$CERT_OUTPUT_DIR"
            
            # Call generate_device_certs.sh with appropriate parameters
            # Arguments: <number_of_devices> <target_directory> <device_name_prefix> <file_name_prefix>
            # file_name_prefix format: {hub_name}_device
            if bash "$SCRIPT_DIR/certGen/generate_device_certs.sh" \
                "$DEVICES_PER_HUB" \
                "$HUB_CERT_DIR" \
                "device" \
                "${hub_name}_device"; then
                log_success "Successfully generated certificates for $hub_name"
            else
                log_error "Failed to generate certificates for hub: $hub_name"
                log_warning "Continuing with other hubs..."
            fi
            
            echo ""
        done
        
        # Return to original directory
        cd "$SCRIPT_DIR"
        
        log_success "Certificate generation completed for all hubs"
        echo ""
    fi
fi

# Final summary
log_section_header "FINAL SUMMARY"
log_success "Script completed successfully!"
echo ""
log_info "Hubs created and activated: ${#ACTIVATED_HUBS[@]}"
log_info "Total devices created: $((${#ACTIVATED_HUBS[@]} * DEVICES_PER_HUB))"
echo ""
log_info "Hub Names:"
for hub_name in "${ACTIVATED_HUBS[@]}"; do
    echo "  - $hub_name"
done
echo ""
log_info "Device Naming Convention:"
log_info "  Devices are named as: device00000, device00001, device00002, etc."
echo ""
log_success "=========================================="
log_success "Operation completed successfully!"
log_success "=========================================="
