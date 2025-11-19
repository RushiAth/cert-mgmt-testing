#!/bin/bash
# ---------------------------------------------------------------
# Utility Functions for IoT Hub Management Scripts
# ---------------------------------------------------------------
# Shared helper functions for IoT Hub creation and management
# ---------------------------------------------------------------

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration for hub status checking
MAX_WAIT_ATTEMPTS=${MAX_WAIT_ATTEMPTS:-15}  # Maximum number of polling attempts for hub activation
WAIT_INTERVAL=${WAIT_INTERVAL:-15}          # Seconds between polling attempts

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

# Function to print section headers
# Usage: log_section_header "Section Title"
log_section_header() {
    local title="$1"
    local separator="========================================="
    echo ""
    log_info "$separator"
    log_info "$title"
    log_info "$separator"
}

# Function to run DhCmd command via PowerShell
# Usage: run_dhcmd "<dhcmd_path>" "<rp_uri>" "<command_with_args>"
# Example: run_dhcmd "$DHCMD_PATH" "$RP_URI" "GetIotHub myHub /ApiVersion:2025-08-01-preview"
run_dhcmd() {
    local dhcmd_path="$1"
    local rp_uri="$2"
    shift 2
    local command="$*"
    
    log_info "Running DhCmd: $command"
    pwsh -Command "& { & '$dhcmd_path' $command /RpUri:'$rp_uri' }"
    return $?
}

# Function to check if hub is active
# Usage: check_hub_status "<hub_name>" "<dhcmd_path>" "<rp_uri>" "[api_version]"
check_hub_status() {
    local hub_name="$1"
    local dhcmd_path="$2"
    local rp_uri="$3"
    local api_version="${4:-}"
    
    log_info "Checking status of hub: $hub_name"
    
    # Build command with optional API version
    local cmd="GetIotHub $hub_name /PaasV2:True"
    if [ -n "$api_version" ]; then
        cmd="$cmd /ApiVersion:$api_version"
    fi
    
    # Run GetIotHub and capture output
    local output
    output=$(pwsh -Command "& { & '$dhcmd_path' $cmd /RpUri:'$rp_uri' 2>&1 }")
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
        echo "$output" | grep "IotHub state:" || log_info "Current state not found in output"
        return 1
    fi
}

# Function to wait for hub activation
# Usage: wait_for_hub_activation "<hub_name>" "<dhcmd_path>" "<rp_uri>" "[api_version]"
wait_for_hub_activation() {
    local hub_name="$1"
    local dhcmd_path="$2"
    local rp_uri="$3"
    local api_version="${4:-}"
    local attempts=0
    
    log_info "Waiting for hub $hub_name to become Active..."
    log_info "Max attempts: $MAX_WAIT_ATTEMPTS, Interval: ${WAIT_INTERVAL}s"
    
    while [ $attempts -lt $MAX_WAIT_ATTEMPTS ]; do
        if check_hub_status "$hub_name" "$dhcmd_path" "$rp_uri" "$api_version"; then
            log_success "Hub $hub_name is now ACTIVE (took $((attempts * WAIT_INTERVAL)) seconds)"
            return 0
        fi
        
        attempts=$((attempts + 1))
        if [ $attempts -lt $MAX_WAIT_ATTEMPTS ]; then
            log_info "Attempt $attempts/$MAX_WAIT_ATTEMPTS - Waiting $WAIT_INTERVAL seconds before next check..."
            sleep $WAIT_INTERVAL
        fi
    done
    
    log_error "Hub $hub_name did not become Active after $((MAX_WAIT_ATTEMPTS * WAIT_INTERVAL)) seconds"
    return 1
}

# Function to validate PowerShell is installed
check_pwsh() {
    if ! command -v pwsh &> /dev/null; then
        log_error "PowerShell (pwsh) is not installed or not in PATH"
        log_error "Please install PowerShell: https://github.com/PowerShell/PowerShell"
        return 1
    fi
    log_success "PowerShell (pwsh) found: $(pwsh --version)"
    return 0
}

# Function to validate numeric input
# Usage: validate_numeric "<value>" "<name>"
validate_numeric() {
    local value="$1"
    local name="$2"
    
    if ! [[ "$value" =~ ^[0-9]+$ ]] || [ "$value" -le 0 ]; then
        log_error "$name must be a positive integer. Got: $value"
        return 1
    fi
    return 0
}

# Function to extract value from DhCmd output
# Usage: extract_value_from_output "<output>" "<pattern>"
# Example: extract_value_from_output "$output" "Verification Code:"
extract_value_from_output() {
    local output="$1"
    local pattern="$2"
    
    echo "$output" | grep "$pattern" | awk -F': ' '{print $2}' | tr -d '\r\n'
}

# Function to parse JSON field from output
# Usage: parse_json_field "<output>" "<field_name>"
# Example: parse_json_field "$output" "etag"
parse_json_field() {
    local output="$1"
    local field="$2"
    
    echo "$output" | grep -o "\"$field\":\"[^\"]*\"" | head -1 | sed "s/\"$field\":\"//;s/\"//"
}

# Export functions for use in other scripts
export -f log_info
export -f log_success
export -f log_warning
export -f log_error
export -f log_section_header
export -f run_dhcmd
export -f check_hub_status
export -f wait_for_hub_activation
export -f check_pwsh
export -f validate_numeric
export -f extract_value_from_output
export -f parse_json_field
