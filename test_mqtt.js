const mqtt = require('mqtt');
const fs = require('fs');
const path = require('path');

loadBackendEnv();

const mqttHost = process.env.MQTT_HOST || 'broker.emqx.io';
const mqttPort = process.env.MQTT_PORT || '1883';
const mqttUseTls = String(process.env.MQTT_USE_TLS || 'false').toLowerCase() === 'true';
const mqttProtocol = mqttUseTls ? 'mqtts' : 'mqtt';
const mqttUrl = `${mqttProtocol}://${mqttHost}:${mqttPort}`;
const deviceCode = process.env.DEVICE_CODE || 'UAV-100';
const topic = process.env.MQTT_TOPIC || `v_monitor/telemetry/${deviceCode}`;
const publishIntervalMs = Number.parseInt(process.env.MQTT_INTERVAL_MS || '2000', 10);
const publishCount = Number.parseInt(process.env.MQTT_COUNT || '0', 10);

const client = mqtt.connect(mqttUrl, {
  username: process.env.MQTT_USERNAME || undefined,
  password: process.env.MQTT_PASSWORD || undefined,
  reconnectPeriod: 0,
  connectTimeout: 10000,
});

let timer = null;
let sent = 0;

client.on('connect', () => {
  console.log(`Connected to MQTT (${mqttUrl}). Sending simulated telemetry...`);
  let lat = 21.0285;
  let lng = 105.8048;

  const publishTelemetry = () => {
    sent += 1;
    lat += 0.0001;
    lng += 0.00008;
    const payload = {
      latitude: lat,
      longitude: lng,
      altitude_m: 36.5,
      speed_mps: 12.5,
      heading_deg: 45.0,
      measured_at: new Date().toISOString(),
    };

    client.publish(topic, JSON.stringify(payload), { qos: 1 }, (err) => {
      if (err) {
        console.error('Publish failed:', err.message);
        client.end(true);
        return;
      }

      console.log(`Published ${sent}${publishCount > 0 ? `/${publishCount}` : ''} to [${topic}]:`, payload);
      if (publishCount > 0 && sent >= publishCount) {
        clearInterval(timer);
        client.end(false, () => console.log('Simulation finished.'));
      }
    });
  };

  publishTelemetry();
  timer = setInterval(publishTelemetry, publishIntervalMs);
});

client.on('error', (err) => {
  console.error(`MQTT connection error for ${mqttUrl}:`, err.message);
  console.error('Check backend/.env or pass MQTT_HOST/MQTT_PORT/MQTT_USE_TLS before running this script.');
  client.end(true);
});

function loadBackendEnv() {
  const envPath = path.join(__dirname, 'backend', '.env');
  if (!fs.existsSync(envPath)) return;

  const lines = fs.readFileSync(envPath, 'utf8').split(/\r?\n/);
  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) continue;

    const equalsIndex = trimmed.indexOf('=');
    if (equalsIndex <= 0) continue;

    const key = trimmed.slice(0, equalsIndex).trim();
    let value = trimmed.slice(equalsIndex + 1).trim();
    if (
      (value.startsWith('"') && value.endsWith('"')) ||
      (value.startsWith("'") && value.endsWith("'"))
    ) {
      value = value.slice(1, -1);
    }

    if (!process.env[key]) {
      process.env[key] = value;
    }
  }
}
