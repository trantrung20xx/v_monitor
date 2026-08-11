import json
import time
import random
from datetime import datetime
import paho.mqtt.client as mqtt

BROKER = "broker.emqx.io"
PORT = 1883
TOPIC = "v_monitor/telemetry/2c258afc-9f0f-48ed-bb9a-dc3c84d80a13"

def on_connect(client, userdata, flags, rc):
    print(f"Connected to MQTT broker with result code {rc}")
    
    lat = 21.028511
    lng = 105.804817
    
    for i in range(5):
        lat += random.uniform(-0.0001, 0.0001)
        lng += random.uniform(-0.0001, 0.0001)
        
        payload = {
            "latitude": lat,
            "longitude": lng,
            "altitude_m": random.uniform(10, 50),
            "speed_mps": random.uniform(0, 15),
            "heading_deg": random.uniform(0, 360),
            "measured_at": datetime.utcnow().isoformat() + "Z"
        }
        
        print(f"Publishing to {TOPIC}: {payload}")
        client.publish(TOPIC, json.dumps(payload))
        time.sleep(1)
        
    client.disconnect()

client = mqtt.Client(client_id="v_monitor_test_publisher")
client.on_connect = on_connect

print(f"Connecting to {BROKER}:{PORT}...")
try:
    client.connect(BROKER, PORT, 60)
    client.loop_forever()
except Exception as e:
    print(f"Error connecting to MQTT: {e}")
