const mqtt = require('mqtt');
// Kết nối tới EMQX Broker đang được cấu hình trong backend
const client = mqtt.connect('mqtt://broker.emqx.io:1883');

client.on('connect', () => {
    console.log('✅ Đã kết nối tới MQTT (broker.emqx.io). Bắt đầu gửi dữ liệu giả lập...');
    let lat = 21.0285;
    
    // Đẩy dữ liệu mỗi 2 giây
    setInterval(() => {
        lat += 0.0001; // Di chuyển dần lên hướng Bắc
        const payload = {
            latitude: lat,
            longitude: 105.8048,
            speed_mps: 12.5,
            heading_deg: 45.0,
            measured_at: new Date().toISOString()
        };
        
        const topic = 'v_monitor/telemetry/UAV-100';
        client.publish(topic, JSON.stringify(payload));
        
        console.log(`📤 Đã gửi lên [${topic}]:`, payload);
    }, 2000);
});

client.on('error', (err) => {
    console.error('Lỗi kết nối MQTT:', err);
});
