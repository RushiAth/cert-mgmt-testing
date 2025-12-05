#!/usr/bin/env python3
"""
Simple MQTT Certificate Issuance Script

This script sends an issueCertificate request to Azure IoT Hub via MQTT
and waits for the response.

Usage:
    python mqtt_issue_cert.py --host <hub-host> --device <device-name> \
        --ca-cert <ca-cert-path> --device-cert <device-cert-path> --device-key <device-key-path>
"""
import paho.mqtt.client as mqtt
import time
import sys
import ssl
import random
import json
import argparse
import io

# Check paho-mqtt version for API compatibility
PAHO_MQTT_VERSION = getattr(mqtt, '__version__', '1.0.0')
try:
    major_version = int(PAHO_MQTT_VERSION.split('.')[0])
    USE_NEW_CALLBACK_API = major_version >= 2
except (ValueError, IndexError):
    USE_NEW_CALLBACK_API = False

# Global variables
response_received = False
response_data = None

def on_connect(client, userdata, flags, rc):
    """Callback for when the client connects to the broker."""
    if rc == 0:
        print(f"[OK] Connected successfully to {userdata['host']}")
        print(f"[OK] Subscribing to: {userdata['subscribe_topic']}")
        client.subscribe(userdata['subscribe_topic'], qos=1)
    else:
        print(f"[FAIL] Connection failed with code {rc}")
        # Connection error codes:
        # 1: Connection refused - incorrect protocol version
        # 2: Connection refused - invalid client identifier
        # 3: Connection refused - server unavailable
        # 4: Connection refused - bad username or password
        # 5: Connection refused - not authorized
        error_messages = {
            1: "Incorrect protocol version",
            2: "Invalid client identifier",
            3: "Server unavailable",
            4: "Bad username or password",
            5: "Not authorized"
        }
        if rc in error_messages:
            print(f"[FAIL] Reason: {error_messages[rc]}")
        sys.exit(1)

def on_subscribe(client, userdata, mid, granted_qos):
    """Callback for when subscription is acknowledged."""
    print(f"[OK] Subscribed successfully (QoS: {granted_qos[0]})")
    
    publish_topic = userdata['publish_topic']
    payload = userdata['payload']
    
    print(f"[OK] Publishing to: {publish_topic}")
    print(f"  Payload: {payload}")
    
    result = client.publish(publish_topic, payload=payload, qos=1)
    if result.rc == mqtt.MQTT_ERR_SUCCESS:
        print(f"[OK] Publish request sent (mid: {result.mid})")
    else:
        print(f"[FAIL] Publish failed with code {result.rc}")

def on_publish(client, userdata, mid):
    """Callback for when a message is published."""
    print(f"[OK] Publish acknowledged by broker (mid: {mid})")

def on_message(client, userdata, msg):
    """Callback for when a message is received."""
    global response_received, response_data
    
    print(f"\n{'='*70}")
    print(f"[OK] RESPONSE RECEIVED!")
    print(f"{'='*70}")
    print(f"Topic: {msg.topic}")
    print(f"QoS: {msg.qos}")
    print(f"Payload length: {len(msg.payload)} bytes")
    
    payload_str = ""
    if msg.payload:
        payload_str = msg.payload.decode('utf-8', errors='replace')
        print(f"Payload: {payload_str}")
    else:
        print(f"Payload: (empty)")
    
    # Extract status code from topic
    # Topic format: $iothub/credentials/res/202/?$rid=999888777&$version=1
    parts = msg.topic.split('/')
    status_code = None
    if len(parts) >= 4:
        status_code = parts[3]
        print(f"\nStatus Code: {status_code}")
    
    # Validate response
    if status_code == "202":
        print(f"\n[OK] SUCCESS: Received expected status code 202 - issueCertificate request accepted")
    else:
        print(f"\n[WARN] WARNING: Expected status code 202, got {status_code}")
    
    print(f"{'='*70}\n")
    
    response_data = {
        'topic': msg.topic,
        'payload': payload_str,
        'status_code': status_code
    }
    response_received = True
    client.disconnect()

def on_disconnect(client, userdata, rc):
    """Callback for when the client disconnects."""
    if rc == 0:
        print("[OK] Disconnected gracefully")
    else:
        print(f"[WARN] Unexpected disconnection (code: {rc})")

def main():
    global response_received
    
    parser = argparse.ArgumentParser(
        description='Simple MQTT Certificate Issuance Script',
        formatter_class=argparse.RawDescriptionHelpFormatter
    )
    
    parser.add_argument('--host', required=True, help='IoT Hub hostname (e.g., myhub.azure-devices-int.net)')
    parser.add_argument('--device', required=True, help='Device ID')
    parser.add_argument('--ca-cert', required=True, help='Path to CA certificate')
    parser.add_argument('--device-cert', required=True, help='Path to device certificate')
    parser.add_argument('--device-key', required=True, help='Path to device private key')
    parser.add_argument('--port', type=int, default=8883, help='MQTT port (default: 8883)')
    parser.add_argument('--timeout', type=int, default=30, help='Response timeout in seconds (default: 30)')
    parser.add_argument('--api-version', default='2025-08-01-preview', help='API version (default: 2025-08-01-preview)')
    parser.add_argument('--csr', default='TU9DSyBDU1I=', help='Base64 encoded CSR (default: mock CSR)')
    
    args = parser.parse_args()
    
    # Generate request ID
    request_id = random.randint(1, 99999999)
    
    # MQTT configuration
    subscribe_topic = "$iothub/credentials/res/#"
    publish_topic = f"$iothub/credentials/POST/issueCertificate/?$rid={request_id}"
    username = f"{args.host}/{args.device}/?api-version={args.api_version}"
    payload = json.dumps({"id": args.device, "csr": args.csr})
    
    # User data to pass to callbacks
    userdata = {
        'host': args.host,
        'subscribe_topic': subscribe_topic,
        'publish_topic': publish_topic,
        'payload': payload
    }
    
    print("\n" + "=" * 70)
    print("MQTT Certificate Issuance Request")
    print("=" * 70)
    print(f"Host: {args.host}")
    print(f"Port: {args.port}")
    print(f"Device: {args.device}")
    print(f"Request ID: {request_id}")
    print(f"CA Cert: {args.ca_cert}")
    print(f"Device Cert: {args.device_cert}")
    print(f"Device Key: {args.device_key}")
    print(f"Subscribe Topic: {subscribe_topic}")
    print(f"Publish Topic: {publish_topic}")
    print("=" * 70 + "\n")
    
    # Create MQTT client - handle both old (1.x) and new (2.x) paho-mqtt API
    print(f"Using paho-mqtt version: {PAHO_MQTT_VERSION}")
    
    try:
        if USE_NEW_CALLBACK_API:
            # paho-mqtt 2.0+ API
            client = mqtt.Client(
                callback_api_version=mqtt.CallbackAPIVersion.VERSION1,
                client_id=args.device,
                clean_session=True,
                protocol=mqtt.MQTTv311,
                userdata=userdata
            )
        else:
            # paho-mqtt 1.x API
            client = mqtt.Client(
                client_id=args.device,
                clean_session=True,
                protocol=mqtt.MQTTv311,
                userdata=userdata
            )
    except TypeError as e:
        # Fallback: try without callback_api_version
        print(f"[WARN] Client creation with callback_api_version failed, trying fallback: {e}")
        client = mqtt.Client(
            client_id=args.device,
            clean_session=True,
            protocol=mqtt.MQTTv311,
            userdata=userdata
        )
    
    # Set username
    client.username_pw_set(username=username)
    
    # Configure TLS with X.509 client certificate
    client.tls_set(
        ca_certs=args.ca_cert,
        certfile=args.device_cert,
        keyfile=args.device_key,
        cert_reqs=ssl.CERT_REQUIRED,
        tls_version=ssl.PROTOCOL_TLS
    )
    
    # Set callbacks
    client.on_connect = on_connect
    client.on_subscribe = on_subscribe
    client.on_publish = on_publish
    client.on_message = on_message
    client.on_disconnect = on_disconnect
    
    try:
        # Connect to broker
        print(f"Connecting to {args.host}:{args.port}...")
        client.connect(args.host, args.port, keepalive=60)
        
        # Start the loop
        client.loop_start()
        
        # Wait for response or timeout
        start_time = time.time()
        while not response_received and (time.time() - start_time) < args.timeout:
            time.sleep(0.1)
        
        if not response_received:
            print(f"\n[FAIL] Timeout: No response received after {args.timeout} seconds")
            client.disconnect()
            sys.exit(1)
        
        # Give a moment for disconnect to complete
        time.sleep(0.5)
        client.loop_stop()
        
        # Exit with appropriate code
        if response_data and response_data.get('status_code') == '202':
            sys.exit(0)
        else:
            sys.exit(1)
        
    except KeyboardInterrupt:
        print("\n[FAIL] Interrupted by user")
        client.disconnect()
        client.loop_stop()
        sys.exit(1)
    except Exception as e:
        print(f"\n[FAIL] Error: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)

if __name__ == "__main__":
    main()
