import json
import logging
import asyncio
from datetime import datetime, timezone
import paho.mqtt.client as mqtt
from app.core.config import settings
from app.core.database import AsyncSessionLocal
from app.schemas.tracking import LocationSampleCreate
from app.services.tracking_service import TrackingService

logger = logging.getLogger(__name__)

class MQTTService:
    def __init__(self):
        self.client = mqtt.Client(client_id="v_monitor_backend")
        self.client.on_connect = self.on_connect
        self.client.on_message = self.on_message
        self.client.on_disconnect = self.on_disconnect
        
        # Save the asyncio event loop to dispatch async tasks from the MQTT thread
        self.loop = None

    def on_connect(self, client, userdata, flags, rc):
        if rc == 0:
            logger.info("Connected to MQTT broker")
            client.subscribe("v_monitor/telemetry/#", qos=1)
        else:
            logger.error(f"Failed to connect to MQTT broker, return code {rc}")

    def on_message(self, client, userdata, msg):
        payload_str = msg.payload.decode('utf-8')
        logger.info(f"Received message on {msg.topic}: {payload_str}")
        
        # Dispatch to asyncio loop
        if self.loop and self.loop.is_running():
            asyncio.run_coroutine_threadsafe(self.process_message(msg.topic, payload_str), self.loop)

    def on_disconnect(self, client, userdata, rc):
        logger.info("Disconnected from MQTT broker")

    async def process_message(self, topic: str, payload_str: str):
        try:
            data = json.loads(payload_str)
            # topic format: v_monitor/telemetry/{device_id}
            parts = topic.split('/')
            if len(parts) >= 3:
                device_id = parts[2]
                
                # Check if it's a location message
                if 'latitude' in data and 'longitude' in data:
                    location_data = LocationSampleCreate(
                        device_id=device_id,
                        measured_at=datetime.fromisoformat(data.get('measured_at').replace('Z', '+00:00')) if data.get('measured_at') else datetime.now(timezone.utc),
                        latitude=data['latitude'],
                        longitude=data['longitude'],
                        altitude_m=data.get('altitude_m'),
                        speed_mps=data.get('speed_mps'),
                        heading_deg=data.get('heading_deg'),
                        source="mqtt"
                    )
                    
                    async with AsyncSessionLocal() as db:
                        await TrackingService.add_location(db, location_data)
                        logger.info(f"Successfully processed location from {device_id}")
                        
        except Exception as e:
            logger.error(f"Error processing MQTT message: {e}", exc_info=True)

    async def start(self):
        self.loop = asyncio.get_running_loop()
        logger.info(f"Starting MQTT client to connect to {settings.MQTT_HOST}:{settings.MQTT_PORT}")
        
        if getattr(settings, 'MQTT_USERNAME', None):
            self.client.username_pw_set(settings.MQTT_USERNAME, settings.MQTT_PASSWORD)
            
        self.client.connect_async(
            settings.MQTT_HOST, 
            port=settings.MQTT_PORT
        )
        self.client.loop_start()

    async def stop(self):
        self.client.loop_stop()
        self.client.disconnect()

mqtt_service = MQTTService()
