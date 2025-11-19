#!/usr/bin/env python3
"""
MQTT Credential Management Test Script - Scenario Based
This script supports multiple test scenarios for MQTT credential management operations.

Scenarios:
    happy_path           - Issue a certificate with valid CSR (default scenario)
    disconnect_reconnect - Disconnect after publishing, then reconnect to receive response
    
Authentication Methods:
    --cert - Use X.509 certificate authentication
    --sas  - Use SAS token authentication

Usage:
    python mqtt_credential_test.py happy_path --cert
    python mqtt_credential_test.py happy_path --sas
    python mqtt_credential_test.py disconnect_reconnect --cert
"""
import paho.mqtt.client as mqtt
import time
import sys
import ssl
import random
import json
import argparse
import hmac
import hashlib
import base64
import os
from urllib.parse import quote_plus

# Connection Constants - Read from environment variables
HUB_NAME = os.getenv("HUB_NAME", "ruath-iothub-004")
DEVICE_NAME = os.getenv("DEVICE_NAME", "ruath-device-001")
HOST = f"{HUB_NAME}.azure-devices-int.net"
PORT = 8883
CLIENT_ID = DEVICE_NAME
USERNAME = f"{HOST}/{CLIENT_ID}/?api-version=2025-08-01-preview"
CA_CERT = "../IoTHubRootCA.crt.pem"

# X.509 Certificate Authentication - Use device name from environment
DEVICE_CERT = f"./certGen/certs/{DEVICE_NAME}.crt"
DEVICE_KEY = f"./certGen/private/{DEVICE_NAME}.key"

# SAS Token Authentication
HUB_SAS_KEY = "<Your Hub SAS Key Here>"
HUB_SAS_POLICY = "iothubowner"

MOCK_CSR = "TU9DSyBDU1I="

# Global flag to track if response was received
response_received = False

class MQTTTestScenario:
    """Base class for MQTT test scenarios."""
    
    def __init__(self, name, description):
        self.name = name
        self.description = description
        self.request_id = random.randint(1, 99999999)
        self.subscribe_topic = "$iothub/credentials/res/#"
        self.publish_topic = None
        self.payload = None
        self.disconnect_after_publish = False
        self.reconnect_delay = 0
    
    def get_publish_topic(self):
        """Return the topic to publish to."""
        return self.publish_topic
    
    def get_payload(self):
        """Return the payload to publish."""
        return self.payload
    
    def validate_response(self, topic, payload):
        """
        Validate the response from the server.
        Returns (success: bool, message: str)
        """
        return True, "Response received"

class HappyPathScenario(MQTTTestScenario):
    """Scenario: Issue certificate with valid CSR (happy path)."""
    
    def __init__(self):
        super().__init__(
            name="happy_path",
            description="Issue a certificate with valid CSR"
        )
        self.publish_topic = f"$iothub/credentials/POST/issueCertificate/?$rid={self.request_id}"
        self.payload = {
            "id": CLIENT_ID,
            "csr": MOCK_CSR
        }
    
    def validate_response(self, topic, payload):
        """Validate the response for happy path scenario."""
        # Extract status code from topic
        # Topic format: $iothub/credentials/res/202/?$rid=999888777&$version=1
        parts = topic.split('/')
        if len(parts) >= 4:
            status_code = parts[3]
            if status_code == "202":
                return True, f"✓ SUCCESS: Received expected status code 202"
            else:
                return False, f"✗ FAILURE: Expected status code 202, got {status_code}"
        return False, "✗ FAILURE: Could not parse status code from topic"

class DisconnectReconnectScenario(MQTTTestScenario):
    """Scenario: Disconnect after publishing request, then reconnect to receive response."""
    
    def __init__(self):
        super().__init__(
            name="disconnect_reconnect",
            description="Disconnect after publish, reconnect later to receive response"
        )
        self.publish_topic = f"$iothub/credentials/POST/issueCertificate/?$rid={self.request_id}"
        self.payload = {
            "id": CLIENT_ID,
            "csr": MOCK_CSR
        }
        self.disconnect_after_publish = True
        self.reconnect_delay = 3  # seconds to wait before reconnecting
    
    def validate_response(self, topic, payload):
        """Validate the response for disconnect/reconnect scenario."""
        parts = topic.split('/')
        if len(parts) >= 4:
            status_code = parts[3]
            if status_code == "202":
                return True, f"✓ SUCCESS: Received response after reconnection (status code 202)"
            else:
                return False, f"✗ FAILURE: Expected status code 202, got {status_code}"
        return False, "✗ FAILURE: Could not parse status code from topic"

# Registry of available scenarios
SCENARIOS = {
    "happy_path": HappyPathScenario,
    "disconnect_reconnect": DisconnectReconnectScenario,
}

def generate_sas_token(uri, key, policy_name=None, expiry=3600):
    """
    Generate a SAS token for Azure IoT Hub authentication.
    
    Args:
        uri: The resource URI (e.g., 'myhub.azure-devices.net/devices/mydevice')
        key: The primary or secondary key (base64 encoded)
        policy_name: The policy name (None for device-level authentication)
        expiry: Token expiration time in seconds from now (default: 1 hour)
    
    Returns:
        The generated SAS token string
    """
    ttl = int(time.time() + expiry)
    sign_key = f"{uri}\n{ttl}"
    
    # Decode the key from base64
    try:
        decoded_key = base64.b64decode(key)
    except Exception as e:
        print(f"✗ Error decoding key: {e}")
        sys.exit(1)
    
    # Create signature
    signature = hmac.new(
        decoded_key,
        sign_key.encode('utf-8'),
        hashlib.sha256
    ).digest()
    
    # Encode signature to base64 and URL-encode it
    signature_b64 = base64.b64encode(signature).decode('utf-8')
    signature_encoded = quote_plus(signature_b64)
    
    # Build SAS token
    if policy_name:
        token = f"SharedAccessSignature sr={uri}&sig={signature_encoded}&se={ttl}&skn={policy_name}"
    else:
        token = f"SharedAccessSignature sr={uri}&sig={signature_encoded}&se={ttl}"
    
    return token

def setup_certificate_auth(client):
    """Configure MQTT client for X.509 certificate authentication."""
    print("Using X.509 Certificate Authentication")
    print(f"Certificate: {DEVICE_CERT}")
    print(f"Private Key: {DEVICE_KEY}\n")
    
    # Set username for X.509 authentication (no password needed)
    client.username_pw_set(username=USERNAME)
    
    # Configure TLS with X.509 client certificate
    client.tls_set(
        ca_certs=CA_CERT,
        certfile=DEVICE_CERT,
        keyfile=DEVICE_KEY,
        cert_reqs=ssl.CERT_REQUIRED,
        tls_version=ssl.PROTOCOL_TLS
    )

def setup_sas_auth(client):
    """Configure MQTT client for SAS token authentication using IoT Hub policy."""
    print("Using SAS Token Authentication (Hub Policy)")
    
    # Generate SAS token using hub-level policy
    resource_uri = HOST
    print(f"Generating SAS token for hub: {resource_uri}")
    print(f"Using policy: {HUB_SAS_POLICY}")
    
    sas_token = generate_sas_token(
        uri=resource_uri,
        key=HUB_SAS_KEY,
        policy_name=HUB_SAS_POLICY,
        expiry=3600  # 1 hour expiration
    )
    
    print(f"✓ SAS token generated (expires in 3600 seconds)")
    print(f"Token preview: {sas_token[:80]}...\n")
    
    # Set username and password (SAS token)
    client.username_pw_set(username=USERNAME, password=sas_token)
    
    # Configure TLS (without client certificate)
    client.tls_set(
        ca_certs=CA_CERT,
        cert_reqs=ssl.CERT_REQUIRED,
        tls_version=ssl.PROTOCOL_TLS
    )

def create_callbacks(scenario):
    """Create callback functions for the MQTT client."""
    global response_received
    
    def on_connect(client, userdata, flags, rc):
        """Callback for when the client connects to the broker."""
        if rc == 0:
            print(f"✓ Connected successfully to {HOST}")
            print(f"✓ Subscribing to: {scenario.subscribe_topic}")
            client.subscribe(scenario.subscribe_topic, qos=1)
        else:
            print(f"✗ Connection failed with code {rc}")
            sys.exit(1)
    
    def on_subscribe(client, userdata, mid, granted_qos):
        """Callback for when subscription is acknowledged."""
        print(f"✓ Subscribed successfully (QoS: {granted_qos})")
        
        publish_topic = scenario.get_publish_topic()
        payload = scenario.get_payload()
        
        print(f"✓ Publishing to: {publish_topic}")
        
        # Serialize payload to JSON if it's a dict
        if isinstance(payload, dict):
            payload_json = json.dumps(payload)
        else:
            payload_json = payload if payload else ""
        
        print(f"  Payload: {payload_json}")
        
        # Now publish the request
        result = client.publish(publish_topic, payload=payload_json, qos=1)
        if result.rc == mqtt.MQTT_ERR_SUCCESS:
            print(f"✓ Publish request sent (mid: {result.mid})")
        else:
            print(f"✗ Publish failed with code {result.rc}")
    
    def on_publish(client, userdata, mid):
        """Callback for when a message is published."""
        print(f"✓ Publish acknowledged by broker (mid: {mid})")
        
        # If scenario requires disconnect after publish, unsubscribe and disconnect immediately
        if scenario.disconnect_after_publish:
            print(f"✓ Unsubscribing from: {scenario.subscribe_topic}")
            client.unsubscribe(scenario.subscribe_topic)
            print(f"\n{'='*70}")
            print("DISCONNECTING after publish (as per scenario)")
            print(f"{'='*70}\n")
            # Disconnect immediately without waiting
            client.disconnect()
    
    def on_message(client, userdata, msg):
        """Callback for when a message is received."""
        global response_received
        print(f"\n{'='*70}")
        print(f"✓ RESPONSE RECEIVED!")
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
        parts = msg.topic.split('/')
        if len(parts) >= 4:
            status_code = parts[3]
            print(f"\nStatus Code: {status_code}")
        
        # Validate response using scenario-specific validation
        success, message = scenario.validate_response(msg.topic, payload_str)
        print(f"\n{message}")
        
        print(f"{'='*70}\n")
        
        response_received = True
        client.disconnect()
    
    def on_disconnect(client, userdata, rc):
        """Callback for when the client disconnects."""
        if rc == 0:
            print("✓ Disconnected gracefully")
        else:
            print(f"✗ Unexpected disconnection (code: {rc})")
    
    def on_log(client, userdata, level, buf):
        """Callback for logging."""
        print(f"[LOG] {buf}")
    
    return on_connect, on_subscribe, on_publish, on_message, on_disconnect, on_log

def run_scenario(scenario_class, use_cert_auth):
    """Run a specific test scenario."""
    global response_received
    response_received = False
    
    # Instantiate the scenario
    scenario = scenario_class()
    
    print("\n" + "=" * 70)
    print(f"MQTT Credential Management Test - {scenario.name}")
    print(f"Description: {scenario.description}")
    print("=" * 70)
    
    # Create MQTT client
    # For disconnect/reconnect scenarios, use clean_session=False to preserve subscriptions
    # clean_session = not scenario.disconnect_after_publish
    client = mqtt.Client(client_id=CLIENT_ID, clean_session=True, protocol=mqtt.MQTTv311)
    
    # Configure authentication
    if use_cert_auth:
        setup_certificate_auth(client)
    else:
        setup_sas_auth(client)
    
    # Set callbacks
    on_connect, on_subscribe, on_publish, on_message, on_disconnect, on_log = create_callbacks(scenario)
    client.on_connect = on_connect
    client.on_subscribe = on_subscribe
    client.on_publish = on_publish
    client.on_message = on_message
    client.on_disconnect = on_disconnect
    # Uncomment for verbose logging:
    # client.on_log = on_log
    
    try:
        # Connect to broker
        print(f"\nConnecting to {HOST}:{PORT}...")
        client.connect(HOST, PORT, keepalive=60)
        
        # Start the loop
        client.loop_start()
        
        # Wait for response or timeout (or for disconnect in disconnect scenarios)
        timeout = 15  # seconds
        start_time = time.time()
        
        # For disconnect/reconnect scenarios, wait for disconnect first
        if scenario.disconnect_after_publish:
            print(f"Waiting for disconnect after publish...")
            while client.is_connected() and (time.time() - start_time) < timeout:
                time.sleep(0.1)
            
            if not client.is_connected():
                print(f"\n✓ Client disconnected as expected")
                print(f"Waiting {scenario.reconnect_delay} seconds before reconnecting...")
                time.sleep(scenario.reconnect_delay)
                
                # Reconnect
                print(f"\n{'='*70}")
                print("RECONNECTING to check for pending response")
                print(f"{'='*70}\n")
                print(f"Connecting to {HOST}:{PORT}...")
                client.connect(HOST, PORT, keepalive=60)
                
                # Reset timeout for second connection
                start_time = time.time()
        
        # Wait for response
        while not response_received and (time.time() - start_time) < timeout:
            time.sleep(0.1)
        
        if not response_received:
            print(f"\n✗ Timeout: No response received after {timeout} seconds")
            client.disconnect()
        
        # Give a moment for disconnect to complete
        time.sleep(0.5)
        client.loop_stop()
        
    except KeyboardInterrupt:
        print("\n✗ Interrupted by user")
        client.disconnect()
        client.loop_stop()
    except Exception as e:
        print(f"\n✗ Error: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)

def list_scenarios():
    """Print available scenarios."""
    print("\nAvailable Scenarios:")
    print("-" * 70)
    for name, scenario_class in SCENARIOS.items():
        scenario = scenario_class()
        print(f"  {name:20} - {scenario.description}")
    print("-" * 70)

def main():
    # Parse command-line arguments
    parser = argparse.ArgumentParser(
        description='MQTT Credential Management Test Script - Scenario Based',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Scenarios:
  happy_path            Issue a certificate with valid CSR
  disconnect_reconnect  Disconnect after publish, reconnect to receive response
  
Authentication Methods:
  --cert    Use X.509 certificate authentication
  --sas     Use SAS token authentication (token will be generated)
  
Examples:
  python mqtt_credential_test.py happy_path --cert
  python mqtt_credential_test.py happy_path --sas
  python mqtt_credential_test.py disconnect_reconnect --cert
  python mqtt_credential_test.py --list-scenarios
        """
    )
    
    parser.add_argument('scenario', nargs='?', default='happy_path',
                       help='Scenario to run (default: happy_path)')
    parser.add_argument('--list-scenarios', action='store_true',
                       help='List all available scenarios')
    
    auth_group = parser.add_mutually_exclusive_group(required=False)
    auth_group.add_argument('--cert', action='store_true',
                           help='Use X.509 certificate authentication')
    auth_group.add_argument('--sas', action='store_true',
                           help='Use SAS token authentication')
    
    args = parser.parse_args()
    
    # List scenarios if requested
    if args.list_scenarios:
        list_scenarios()
        return
    
    # Validate authentication method is specified
    if not args.cert and not args.sas:
        parser.error("Authentication method required: use --cert or --sas")
    
    # Validate scenario exists
    if args.scenario not in SCENARIOS:
        print(f"✗ Error: Unknown scenario '{args.scenario}'")
        list_scenarios()
        sys.exit(1)
    
    # Run the scenario
    scenario_class = SCENARIOS[args.scenario]
    run_scenario(scenario_class, use_cert_auth=args.cert)

if __name__ == "__main__":
    main()
