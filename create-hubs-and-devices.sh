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

# ========================================
# CONFIGURATION - Hardcode values here if desired
# ========================================
# If these are set, they will be used instead of command-line arguments
# Leave empty ("") to require command-line arguments
HARDCODED_RP_URI=""
HARDCODED_DHCMD_PATH=""
# ========================================

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored log messages
log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Parse cleanup flag
CLEANUP_MODE=false
if [[ "${!#}" == "--cleanup" ]]; then
    CLEANUP_MODE=true
    set -- "${@:1:$(($#-1))}"  # Remove --cleanup from arguments
fi

# Determine if we're using hardcoded values or command-line arguments
if [ -n "$HARDCODED_RP_URI" ]; then
    # Using hardcoded RpUri - adjust expected arguments
    if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
        log_error "Invalid number of arguments (RpUri is hardcoded)"
        echo "Usage: $0 <NumHubs> <DevicesPerHub> [DhCmdPath] [--cleanup]"
        echo "  NumHubs: Number of IoT Hubs to create/delete (positive integer)"
        echo "  DevicesPerHub: Number of devices per hub (positive integer, ignored in cleanup mode)"
        echo "  DhCmdPath: (Optional) Path to DhCmd.exe (can be hardcoded in script)"
        echo "  --cleanup: (Optional) Delete hubs instead of creating them"
        echo ""
        echo "Note: RpUri is hardcoded in the script: $HARDCODED_RP_URI"
        echo ""
        echo "Example: $0 5 100"
        echo "Example with custom path: $0 5 100 /path/to/DhCmd.exe"
        echo "Example cleanup: $0 5 100 --cleanup"
        exit 1
    fi
    
    RP_URI="$HARDCODED_RP_URI"
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
        echo "  DhCmdPath: (Optional) Path to DhCmd.exe (can be hardcoded in script)"
        echo "  --cleanup: (Optional) Delete hubs instead of creating them"
        echo ""
        echo "Example: $0 https://master1-dh-rp.cloudapp.net 5 100"
        echo "Example with custom path: $0 https://master1-dh-rp.cloudapp.net 5 100 /path/to/DhCmd.exe"
        echo "Example cleanup: $0 https://master1-dh-rp.cloudapp.net 5 100 --cleanup"
        exit 1
    fi
    
    RP_URI="$1"
    NUM_HUBS="$2"
    DEVICES_PER_HUB="$3"
    DHCMD_PATH_ARG="${4:-}"
fi

# Validate numeric inputs
if ! [[ "$NUM_HUBS" =~ ^[0-9]+$ ]] || [ "$NUM_HUBS" -le 0 ]; then
    log_error "NumHubs must be a positive integer. Got: $NUM_HUBS"
    exit 1
fi

if ! [[ "$DEVICES_PER_HUB" =~ ^[0-9]+$ ]] || [ "$DEVICES_PER_HUB" -le 0 ]; then
    log_error "DevicesPerHub must be a positive integer. Got: $DEVICES_PER_HUB"
    exit 1
fi

# Device authentication key (hardcoded as used by DhCmd's BulkAddDevicesV2)
DEVICE_PRIMARY_KEY="YzE2ZTg1MzE5NGZjNDljOTg5YWY1YzlmMTVhYzEwMTc="

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAX_WAIT_ATTEMPTS=15  # Maximum number of polling attempts for hub activation
WAIT_INTERVAL=15      # Seconds between polling attempts
HUB_NAME_PREFIX="stress-hub-"  # Prefix for hub names with timestamp

if [ "$CLEANUP_MODE" = true ]; then
    log_info "=========================================="
    log_info "IoT Hub Cleanup Script"
    log_info "=========================================="
    log_info "RP Environment: $RP_URI"
    log_info "Number of Hubs to Delete: $NUM_HUBS"
    log_info "Hub Name Prefix: $HUB_NAME_PREFIX"
    log_info "Script Directory: $SCRIPT_DIR"
    log_info "=========================================="
else
    log_info "=========================================="
    log_info "IoT Hub and Device Creation Script"
    log_info "=========================================="
    log_info "RP Environment: $RP_URI"
    log_info "Number of Hubs: $NUM_HUBS"
    log_info "Devices Per Hub: $DEVICES_PER_HUB"
    log_info "Hub Name Prefix: $HUB_NAME_PREFIX"
    log_info "Script Directory: $SCRIPT_DIR"
    log_info "=========================================="
fi
echo ""

# Check if pwsh is available
if ! command -v pwsh &> /dev/null; then
    log_error "PowerShell (pwsh) is not installed or not in PATH"
    log_error "Please install PowerShell: https://github.com/PowerShell/PowerShell"
    exit 1
fi

log_success "PowerShell (pwsh) found: $(pwsh --version)"

# Find DhCmd.exe
DHCMD_PATH=""

# Check if hardcoded path is set and valid
if [ -n "$HARDCODED_DHCMD_PATH" ]; then
    if [ -f "$HARDCODED_DHCMD_PATH" ]; then
        DHCMD_PATH="$HARDCODED_DHCMD_PATH"
        log_success "Using hardcoded DhCmd.exe path: $DHCMD_PATH"
    else
        log_error "Hardcoded DhCmd.exe path does not exist: $HARDCODED_DHCMD_PATH"
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

# Function to run DhCmd command via PowerShell
run_dhcmd() {
    local command="$1"
    log_info "Running DhCmd: $command"
    pwsh -Command "& { & '$DHCMD_PATH' $command /RpUri:$RP_URI }"
    return $?
}

# If in cleanup mode, delete hubs and exit
if [ "$CLEANUP_MODE" = true ]; then
    log_info "=========================================="
    log_info "CLEANUP MODE: Deleting $NUM_HUBS IoT Hub(s)"
    log_info "=========================================="
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
        
        if run_dhcmd "DeleteIotHub $HUB_NAME"; then
            log_success "Successfully deleted hub: $HUB_NAME"
            DELETED_COUNT=$((DELETED_COUNT + 1))
        else
            log_warning "Failed to delete hub (it may not exist): $HUB_NAME"
            FAILED_COUNT=$((FAILED_COUNT + 1))
        fi
        
        echo ""
    done
    
    log_info "=========================================="
    log_info "CLEANUP SUMMARY"
    log_info "=========================================="
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

# Function to check if hub is active
check_hub_status() {
    local hub_name="$1"
    log_info "Checking status of hub: $hub_name"
    
    # Run GetIotHub and capture output
    local output
    output=$(pwsh -Command "& { & '$DHCMD_PATH' GetIotHub $hub_name /RpUri:$RP_URI 2>&1 }")
    local exit_code=$?
    
    if [ $exit_code -ne 0 ]; then
        log_warning "Failed to get hub status for $hub_name"
        echo "$output"
        return 1
    fi
    
    # Check if output contains "IotHub state: Active"
    if echo "$output" | grep -q "IotHub state: Active"; then
        log_success "Hub $hub_name is ACTIVE"
        return 0
    else
        log_info "Hub $hub_name is not yet active"
        return 1
    fi
}

# Function to wait for hub activation
wait_for_hub_activation() {
    local hub_name="$1"
    local attempts=0
    
    log_info "Waiting for hub $hub_name to become Active..."
    
    while [ $attempts -lt $MAX_WAIT_ATTEMPTS ]; do
        if check_hub_status "$hub_name"; then
            return 0
        fi
        
        attempts=$((attempts + 1))
        log_info "Attempt $attempts/$MAX_WAIT_ATTEMPTS - Waiting $WAIT_INTERVAL seconds before next check..."
        sleep $WAIT_INTERVAL
    done
    
    log_error "Hub $hub_name did not become Active after $((MAX_WAIT_ATTEMPTS * WAIT_INTERVAL)) seconds"
    return 1
}

# Step 1: Create IoT Hubs using bulk creation
log_info "=========================================="
log_info "STEP 1: Creating $NUM_HUBS IoT Hub(s)"
log_info "=========================================="
echo ""

log_info "Initiating bulk creation of $NUM_HUBS hubs with prefix: $HUB_NAME_PREFIX"

if run_dhcmd "CreateIotHubsWithGWv2Capability $HUB_NAME_PREFIX $NUM_HUBS"; then
    log_success "Bulk hub creation initiated for $NUM_HUBS hubs"
else
    log_error "Failed to initiate bulk hub creation"
    exit 1
fi

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
log_info "=========================================="
log_info "STEP 2: Waiting for Hub(s) to Activate"
log_info "=========================================="
echo ""

ACTIVATED_HUBS=()

for hub_name in "${HUB_NAMES[@]}"; do
    log_info "Waiting for hub: $hub_name"
    
    if wait_for_hub_activation "$hub_name"; then
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
log_info "=========================================="
log_info "STEP 3: Adding Devices to Hub(s)"
log_info "=========================================="
echo ""

for hub_name in "${ACTIVATED_HUBS[@]}"; do
    log_info "Adding $DEVICES_PER_HUB devices to hub: $hub_name"
    
    if run_dhcmd "BulkAddDevicesV2 $hub_name $DEVICES_PER_HUB"; then
        log_success "Successfully added $DEVICES_PER_HUB devices to $hub_name"
    else
        log_error "Failed to add devices to hub: $hub_name"
        log_warning "Continuing with other hubs..."
    fi
    
    echo ""
done

# Step 4: Update /etc/hosts file
log_info "=========================================="
log_info "STEP 4: Updating /etc/hosts File"
log_info "=========================================="
echo ""

# Check if we have write access to /etc/hosts
if [ ! -w /etc/hosts ]; then
    log_warning "/etc/hosts is not writable. Attempting to use sudo..."
    
    # Create temporary file with hub entries
    TEMP_HOSTS_FILE=$(mktemp)
    
    log_info "Creating host entries for activated hubs..."
    for hub_name in "${ACTIVATED_HUBS[@]}"; do
        echo "127.0.0.1       ${hub_name}.azure-devices-int.net" >> "$TEMP_HOSTS_FILE"
    done
    
    # Show what will be added
    log_info "The following entries will be added to /etc/hosts:"
    cat "$TEMP_HOSTS_FILE"
    echo ""
    
    # Find the IPv6 comment line and insert before it
    if sudo grep -q "# The following lines are desirable for IPv6 capable hosts" /etc/hosts; then
        log_info "Adding entries before IPv6 section..."
        
        # Create a backup
        sudo cp /etc/hosts /etc/hosts.backup.$(date +%Y%m%d_%H%M%S)
        log_success "Created backup of /etc/hosts"
        
        # Remove any existing entries for these hubs first
        for hub_name in "${ACTIVATED_HUBS[@]}"; do
            sudo sed -i "/${hub_name}.azure-devices-int.net/d" /etc/hosts
        done
        
        # Insert new entries before the IPv6 comment
        sudo sed -i '/# The following lines are desirable for IPv6 capable hosts/i\' /etc/hosts
        while IFS= read -r line; do
            sudo sed -i "/# The following lines are desirable for IPv6 capable hosts/i\\$line" /etc/hosts
        done < "$TEMP_HOSTS_FILE"
        
        log_success "Successfully updated /etc/hosts"
    else
        log_warning "IPv6 comment not found in /etc/hosts, appending to end of file..."
        sudo bash -c "cat '$TEMP_HOSTS_FILE' >> /etc/hosts"
        log_success "Successfully appended entries to /etc/hosts"
    fi
    
    # Clean up temp file
    rm -f "$TEMP_HOSTS_FILE"
else
    log_info "Creating host entries for activated hubs..."
    
    # Remove any existing entries for these hubs first
    for hub_name in "${ACTIVATED_HUBS[@]}"; do
        sed -i "/${hub_name}.azure-devices-int.net/d" /etc/hosts
    done
    
    # Find the IPv6 comment line and insert before it
    if grep -q "# The following lines are desirable for IPv6 capable hosts" /etc/hosts; then
        log_info "Adding entries before IPv6 section..."
        
        # Create a backup
        cp /etc/hosts /etc/hosts.backup.$(date +%Y%m%d_%H%M%S)
        log_success "Created backup of /etc/hosts"
        
        # Insert new entries before the IPv6 comment
        sed -i '/# The following lines are desirable for IPv6 capable hosts/i\' /etc/hosts
        for hub_name in "${ACTIVATED_HUBS[@]}"; do
            sed -i "/# The following lines are desirable for IPv6 capable hosts/i\\127.0.0.1       ${hub_name}.azure-devices-int.net" /etc/hosts
        done
        
        log_success "Successfully updated /etc/hosts"
    else
        log_warning "IPv6 comment not found in /etc/hosts, appending to end of file..."
        for hub_name in "${ACTIVATED_HUBS[@]}"; do
            echo "127.0.0.1       ${hub_name}.azure-devices-int.net" >> /etc/hosts
        done
        log_success "Successfully appended entries to /etc/hosts"
    fi
fi

echo ""
log_info "Added ${#ACTIVATED_HUBS[@]} hub entries to /etc/hosts"
echo ""

# Final summary
log_info "=========================================="
log_info "FINAL SUMMARY"
log_info "=========================================="
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
log_info "Device Authentication:"
log_info "  All devices use the same primary key for authentication"
log_info "  Device Primary Key: $DEVICE_PRIMARY_KEY"
echo ""
log_info "Device Naming Convention:"
log_info "  Devices are named as: device00000, device00001, device00002, etc."
echo ""
log_success "=========================================="
log_success "Operation completed successfully!"
log_success "=========================================="
