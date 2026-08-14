import asyncio
import json
import os
import random
from datetime import datetime
import urllib.request
import websockets

API_URL = os.getenv("API_BASE_URL", "http://127.0.0.1:8000/api/v1")
WS_BASE_URL = os.getenv("WS_BASE_URL", "ws://127.0.0.1:8000")
WS_PATH = os.getenv("WS_PATH", "/api/v1/ws")
WS_URL = os.getenv(
    "WS_URL",
    f"{WS_BASE_URL.rstrip('/')}/{WS_PATH.lstrip('/')}",
)

def create_device():
    req = urllib.request.Request(
        f"{API_URL}/devices/",
        data=json.dumps({
            "device_code": "UAV-100",
            "name": "Flycam 100",
            "device_type": "UAV_CONTROLLER"
        }).encode('utf-8'),
        headers={'Content-Type': 'application/json'}
    )
    try:
        response = urllib.request.urlopen(req)
        return json.loads(response.read().decode('utf-8'))
    except Exception as e:
        print(f"Error creating device: {e}")
        return None

def send_location(device_id, lat, lng):
    req = urllib.request.Request(
        f"{API_URL}/tracking/",
        data=json.dumps({
            "device_id": device_id,
            "measured_at": datetime.utcnow().isoformat() + "Z",
            "latitude": lat,
            "longitude": lng,
            "speed_mps": random.uniform(0, 15),
            "heading_deg": random.uniform(0, 360)
        }).encode('utf-8'),
        headers={'Content-Type': 'application/json'}
    )
    try:
        response = urllib.request.urlopen(req)
        return json.loads(response.read().decode('utf-8'))
    except Exception as e:
        print(f"Error sending location: {e}")
        return None

async def listen_ws():
    async with websockets.connect(WS_URL) as ws:
        print("Connected to WebSocket")
        while True:
            msg = await ws.recv()
            print(f"[WS] Received: {msg}")

async def simulate(device_id):
    lat = 21.028511
    lng = 105.804817
    
    while True:
        lat += random.uniform(-0.0001, 0.0001)
        lng += random.uniform(-0.0001, 0.0001)
        print(f"Sending location for {device_id}: {lat}, {lng}")
        send_location(device_id, lat, lng)
        await asyncio.sleep(2)

async def main():
    print("Creating device...")
    device = create_device()
    if not device:
        # try to get the first device
        req = urllib.request.Request(f"{API_URL}/devices/")
        response = urllib.request.urlopen(req)
        devices = json.loads(response.read().decode('utf-8'))
        if devices:
            device = devices[0]
        else:
            print("No device found or created. Exiting.")
            return

    device_id = device['id']
    print(f"Device ready: {device_id}")

    # Run websocket listener and simulation concurrently
    await asyncio.gather(
        listen_ws(),
        simulate(device_id)
    )

if __name__ == "__main__":
    asyncio.run(main())
