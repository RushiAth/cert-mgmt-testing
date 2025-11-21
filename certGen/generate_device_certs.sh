#!/bin/bash

###############################################################################
# Script to generate multiple device certificates
# Usage: ./generate_device_certs.sh <number_of_devices> <target_directory> <device_name_prefix> <file_name_prefix>
###############################################################################

set -e  # Exit on error

# Check if arguments are provided
if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ] || [ -z "$4" ]; then
    echo "Usage: ./generate_device_certs.sh <number_of_devices> <target_directory> <device_name_prefix> <file_name_prefix>"
    echo ""
    echo "Arguments:"
    echo "  number_of_devices   : Number of device certificates to generate"
    echo "  target_directory    : Directory where certificates and keys will be moved"
    echo "  device_name_prefix  : Prefix for device names used in certificate CN (e.g., 'device', 'sensor', 'iot-device')"
    echo "  file_name_prefix    : Prefix for output file names (e.g., 'device', 'prod-sensor')"
    echo ""
    echo "Example: ./generate_device_certs.sh 10 ./output device sensor"
    echo "  This creates: device00000 (CN) -> sensor00000.crt, sensor00000.key"
    exit 1
fi

# Validate that first argument is a positive integer
if ! [[ "$1" =~ ^[0-9]+$ ]] || [ "$1" -le 0 ]; then
    echo "Error: First argument must be a positive integer"
    exit 1
fi

NUM_DEVICES=$1
TARGET_DIR=$2
DEVICE_PREFIX=$3
FILE_PREFIX=$4

# Create target directory if it doesn't exist
mkdir -p "$TARGET_DIR"
if [ ! -d "$TARGET_DIR" ]; then
    echo "Error: Could not create target directory: $TARGET_DIR"
    exit 1
fi

echo "Generating certificates for $NUM_DEVICES devices..."
echo "Device name prefix: $DEVICE_PREFIX"
echo "File name prefix: $FILE_PREFIX"
echo "Starting from ${DEVICE_PREFIX}00000 to ${DEVICE_PREFIX}$(printf "%05d" $((NUM_DEVICES - 1)))"
echo "Target directory: $TARGET_DIR"
echo ""

# Loop through each device
for i in $(seq 0 $((NUM_DEVICES - 1))); do
    # Format device number with leading zeros (5 digits)
    DEVICE_NUM=$(printf "%05d" $i)
    DEVICE_NAME="${DEVICE_PREFIX}${DEVICE_NUM}"
    FILE_NAME="${FILE_PREFIX}${DEVICE_NUM}"
    
    echo "=========================================="
    echo "Processing $DEVICE_NAME -> $FILE_NAME ($((i + 1))/$NUM_DEVICES)"
    echo "=========================================="
    
    # Step 1: Clean up any existing new-device files
    echo "Cleaning up previous new-device files..."
    rm -f certs/new-device*
    rm -f private/new-device*
    
    # Step 2: Generate device certificate
    echo "Generating certificate for $DEVICE_NAME..."
    ./certGen.sh create_device_certificate_from_intermediate $DEVICE_NAME
    
    # Step 3: Convert certificate to .crt format
    echo "Converting certificate to .crt format..."
    cd certs
    openssl x509 -in new-device.cert.pem -out ${FILE_NAME}.crt
    cd ..
    
    # Step 4: Rename the private key
    echo "Renaming private key..."
    cd private
    mv new-device.key.pem ${FILE_NAME}.key
    cd ..
    
    # Step 5: Move certificate and key to target directory
    echo "Moving files to target directory..."
    mv certs/${FILE_NAME}.crt "$TARGET_DIR/"
    mv private/${FILE_NAME}.key "$TARGET_DIR/"
    
    echo "✓ Certificate for $DEVICE_NAME created as ${FILE_NAME}.crt and ${FILE_NAME}.key"
    echo ""
done

cd ..

echo "=========================================="
echo "All done! Generated $NUM_DEVICES device certificates."
echo "=========================================="
echo ""
echo "All certificates and keys have been moved to: $TARGET_DIR"