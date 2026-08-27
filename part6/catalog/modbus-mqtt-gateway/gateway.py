#!/usr/bin/env python3
"""
Modbus to MQTT Gateway

Reads gas sensor measurements from a Modbus device and publishes them to MQTT topics.

MQTT Topics:
  rtu/sensor/{device_id}/dp         - Differential Pressure (Pa)
  rtu/sensor/{device_id}/sp         - Static Pressure (Pa)
  rtu/sensor/{device_id}/temp       - Temperature (°C)
  rtu/sensor/{device_id}/flow       - Gas Flow (m³/h)
  rtu/sensor/{device_id}/timestamp  - Last reading timestamp
"""

import logging
import os
import time
import json
from datetime import datetime
import yaml
import paho.mqtt.client as mqtt
from pymodbus.client import AsyncModbusTcpClient
import asyncio

logging.basicConfig(
    level=os.environ.get('LOG_LEVEL', 'INFO').upper(),
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


class ModbusMQTTGateway:
    def __init__(self, config):
        self.config = config
        self.modbus_config = config.get('modbus', {})
        self.mqtt_config = config.get('mqtt', {})
        self.device_id = config.get('device_id', 'sensor-001')
        self.poll_interval = config.get('poll_interval', 5)
        
        # Initialize Modbus client
        self.modbus_client = AsyncModbusTcpClient(
            host=self.modbus_config.get('host', 'localhost'),
            port=self.modbus_config.get('port', 502)
        )
        
        # Initialize MQTT client
        self.mqtt_client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2)
        self.mqtt_client.on_connect = self.on_mqtt_connect
        self.mqtt_client.on_disconnect = self.on_mqtt_disconnect
        self.mqtt_client.on_publish = self.on_mqtt_publish
        
    def on_mqtt_connect(self, client, userdata, connect_flags, reason_code, properties):
        """MQTT connection callback."""
        if reason_code == 0:
            logger.info("Connected to MQTT broker successfully")
        else:
            logger.error(f"Failed to connect to MQTT broker: {reason_code}")
    
    def on_mqtt_disconnect(self, client, userdata, disconnect_flags, reason_code, properties):
        """MQTT disconnection callback."""
        logger.warning(f"Disconnected from MQTT broker: {reason_code}")
    
    def on_mqtt_publish(self, client, userdata, mid, reason_code, properties):
        """MQTT publish callback."""
        if reason_code != 0:
            logger.error(f"Failed to publish message: {reason_code}")
    
    async def connect_modbus(self):
        """Connect to Modbus device."""
        try:
            await self.modbus_client.connect()
            logger.info(f"Connected to Modbus device at {self.modbus_config.get('host')}:{self.modbus_config.get('port')}")
            return True
        except Exception as e:
            logger.error(f"Failed to connect to Modbus device: {e}")
            return False
    
    def connect_mqtt(self):
        """Connect to MQTT broker."""
        try:
            host = self.mqtt_config.get('host', 'localhost')
            port = self.mqtt_config.get('port', 1883)
            self.mqtt_client.connect(host, port, keepalive=60)
            self.mqtt_client.loop_start()
            logger.info(f"Connected to MQTT broker at {host}:{port}")
            return True
        except Exception as e:
            logger.error(f"Failed to connect to MQTT broker: {e}")
            return False
    
    async def read_modbus_registers(self):
        """Read sensor data from Modbus device."""
        try:
            slave_id = self.modbus_config.get('slave_id', 1)
            
            # Read holding registers 100-103
            result = await self.modbus_client.read_holding_registers(100, 4, slave_id=slave_id)
            
            if result.isError():
                logger.error(f"Modbus read error: {result}")
                return None
            
            registers = result.registers
            
            # Convert from fixed-point to float
            dp = registers[0] / 100.0  # Pa
            sp = registers[1] / 10.0   # Pa
            temp = registers[2] / 100.0  # °C
            flow = registers[3] / 100.0  # m³/h
            
            return {
                'dp': dp,
                'sp': sp,
                'temp': temp,
                'flow': flow,
                'timestamp': datetime.now().isoformat()
            }
            
        except Exception as e:
            logger.error(f"Error reading Modbus registers: {e}")
            return None
    
    def publish_to_mqtt(self, data):
        """Publish sensor data to MQTT topics."""
        if not data:
            return
        
        base_topic = f"rtu/sensor/{self.device_id}"
        
        messages = {
            f"{base_topic}/dp": f"{data['dp']:.2f}",
            f"{base_topic}/sp": f"{data['sp']:.2f}",
            f"{base_topic}/temp": f"{data['temp']:.2f}",
            f"{base_topic}/flow": f"{data['flow']:.4f}",
            f"{base_topic}/timestamp": data['timestamp'],
            f"{base_topic}/status": json.dumps({
                'dp': data['dp'],
                'sp': data['sp'],
                'temp': data['temp'],
                'flow': data['flow'],
                'timestamp': data['timestamp']
            })
        }
        
        for topic, value in messages.items():
            self.mqtt_client.publish(topic, value, qos=1, retain=False)
            logger.debug(f"Published to {topic}: {value}")
    
    async def run(self):
        """Main gateway loop."""
        if not await self.connect_modbus():
            logger.error("Failed to connect to Modbus device")
            return
        
        if not self.connect_mqtt():
            logger.error("Failed to connect to MQTT broker")
            return
        
        logger.info("Gateway started successfully")
        
        try:
            while True:
                # Read from Modbus
                data = await self.read_modbus_registers()
                
                # Publish to MQTT
                if data:
                    self.publish_to_mqtt(data)
                    logger.info(f"DP: {data['dp']:.2f} Pa | SP: {data['sp']:.2f} Pa | T: {data['temp']:.2f}°C | Flow: {data['flow']:.4f} m³/h")
                
                await asyncio.sleep(self.poll_interval)
                
        except KeyboardInterrupt:
            logger.info("Gateway shutting down...")
        except Exception as e:
            logger.error(f"Gateway error: {e}")
        finally:
            self.mqtt_client.loop_stop()
            await self.modbus_client.close()


def load_config():
    """Load configuration from config.yaml, with environment variable overrides."""
    with open('config.yaml', 'r') as f:
        config = yaml.safe_load(f) or {}

    modbus_cfg = config.setdefault('modbus', {})
    if 'MODBUS_HOST' in os.environ:
        modbus_cfg['host'] = os.environ['MODBUS_HOST']
    if 'MODBUS_PORT' in os.environ:
        modbus_cfg['port'] = int(os.environ['MODBUS_PORT'])

    mqtt_cfg = config.setdefault('mqtt', {})
    if 'MQTT_HOST' in os.environ:
        mqtt_cfg['host'] = os.environ['MQTT_HOST']
    if 'MQTT_PORT' in os.environ:
        mqtt_cfg['port'] = int(os.environ['MQTT_PORT'])

    if 'DEVICE_ID' in os.environ:
        config['device_id'] = os.environ['DEVICE_ID']
    if 'POLL_INTERVAL' in os.environ:
        config['poll_interval'] = int(os.environ['POLL_INTERVAL'])

    return config


async def main():
    config = load_config()
    gateway = ModbusMQTTGateway(config)
    await gateway.run()


if __name__ == "__main__":
    asyncio.run(main())
