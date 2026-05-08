# RTU IIoT Catalog

Flightctl catalog items for industrial IoT gas flow measurement and monitoring using Modbus and MQTT protocols.

## Overview

This repository contains three complementary applications that work together to create a complete industrial IoT solution for gas flow measurement:

1. **Modbus Gas Sensor Simulator**: Simulates an RS485/Modbus gas flow sensor
2. **Modbus-MQTT Gateway**: Bridges Modbus devices to MQTT
3. **Mosquitto MQTT Broker**: Message broker for data collection

## Architecture

```
┌─────────────────────────────┐
│  Modbus Gas Sensor          │
│  (Port 502/TCP)             │
│  - Differential Pressure    │
│  - Static Pressure          │
│  - Temperature              │
│  - Calculated Flow Rate     │
└──────────┬──────────────────┘
           │ Modbus TCP
           │
┌──────────▼──────────────────┐
│  Modbus-MQTT Gateway        │
│  (Translator)               │
│  - Reads Modbus registers   │
│  - Converts to MQTT topics  │
│  - Handles reconnection     │
└──────────┬──────────────────┘
           │ MQTT (Port 1883)
           │
┌──────────▼──────────────────┐
│  Mosquitto MQTT Broker      │
│  - Publishes messages       │
│  - WebSocket interface      │
│  - Data persistence         │
│  - Multi-client support     │
└─────────────────────────────┘
```

## Catalog Structure

```
catalog/
├── catalog.yaml                           # Catalog definition
├── modbus-gas-sensor/                     # Sensor simulator
│   ├── Dockerfile                         # Container build
│   ├── sensor.py                          # Main application
│   └── config.yaml                        # Configuration
├── modbus-gas-sensor-catalogitem.yaml     # Flightctl catalog item
├── modbus-mqtt-gateway/                   # Gateway application
│   ├── Dockerfile                         # Container build
│   ├── gateway.py                         # Main application
│   └── config.yaml                        # Configuration
├── modbus-mqtt-gateway-catalogitem.yaml   # Flightctl catalog item
├── mosquitto-broker/                      # MQTT broker
│   ├── Dockerfile                         # Container build
│   └── mosquitto.conf                     # Configuration
└── mosquitto-broker-catalogitem.yaml      # Flightctl catalog item
```

## Application Details

### 1. Modbus Gas Sensor Simulator

**Purpose**: Simulates an industrial gas flow sensor connected via Modbus TCP protocol.

**Key Features**:
- Simulates differential pressure (DP) across orifice plates
- Measures static pressure (SP) for volume correction
- Measures temperature (T) for gas density correction
- Calculates gas flow using ISO 5167 formula
- Provides realistic variations in sensor data

**Modbus Registers**:
| Register | Parameter | Unit | Range |
|----------|-----------|------|-------|
| 100 | Differential Pressure | Pa | 0-1000 |
| 101 | Static Pressure | Pa | 95000-110000 |
| 102 | Temperature | °C | -10 to 60 |
| 103 | Gas Flow | m³/h | Calculated |

**Flow Calculation Formula**:
```
Q = C × A × √(2 × DP / ρ)

where:
  Q = Flow rate (m³/h)
  C = Discharge coefficient (0.61 for sharp-edged orifice)
  A = Orifice area (π × r²)
  DP = Differential pressure (Pa)
  ρ = Gas density, calculated from SP and T using ideal gas law
```

**Configuration** (`config.yaml`):
```yaml
server:
  host: "0.0.0.0"
  port: 502

sensor:
  initial_dp: 50.0
  initial_sp: 101325.0
  initial_temp: 20.0
  orifice_diameter: 0.05
  discharge_coefficient: 0.61
```

**Container Image**: `quay.io/luferrar/rtu-modbus-gas-sensor:1.0.0`

**Ports**:
- 502/TCP: Modbus TCP interface

### 2. Modbus-MQTT Gateway

**Purpose**: Bridges industrial Modbus devices to MQTT for cloud-native data collection.

**Key Features**:
- Continuous polling of Modbus registers
- Automatic data type conversion (fixed-point to decimal)
- Structured MQTT topic hierarchy
- Configurable polling interval
- Robust error handling and reconnection logic
- Timestamp tracking for each measurement

**MQTT Topic Structure**:
```
rtu/sensor/{device_id}/dp          # Differential Pressure (Pa)
rtu/sensor/{device_id}/sp          # Static Pressure (Pa)
rtu/sensor/{device_id}/temp        # Temperature (°C)
rtu/sensor/{device_id}/flow        # Gas Flow (m³/h)
rtu/sensor/{device_id}/timestamp   # ISO 8601 timestamp
rtu/sensor/{device_id}/status      # Complete status JSON
```

**Configuration** (`config.yaml`):
```yaml
device_id: "sensor-001"
poll_interval: 5

modbus:
  host: "modbus-gas-sensor"
  port: 502
  slave_id: 1

mqtt:
  host: "mosquitto-broker"
  port: 1883
```

**Container Image**: `quay.io/luferrar/rtu-modbus-mqtt-gateway:1.0.0`

**Service Dependencies**:
- Modbus Gas Sensor (must be running)
- Mosquitto MQTT Broker (must be running)

### 3. Mosquitto MQTT Broker

**Purpose**: Lightweight, open-source MQTT message broker for IoT communications.

**Key Features**:
- Full MQTT 3.1.1 and 5.0 support
- Minimal resource footprint
- Multiple protocol support (TCP, TLS, WebSocket)
- Optional message persistence
- Scalable for edge deployments
- Anonymous and authenticated modes

**Listening Ports**:
- 1883/TCP: Standard MQTT
- 8883/TCP: MQTT over TLS/SSL
- 9001/TCP: MQTT over WebSocket

**Configuration** (`mosquitto.conf`):
```
listener 1883
protocol mqtt

listener 9001
protocol websockets

persistence true
persistence_location /mosquitto/data/

allow_anonymous true
max_connections -1
max_queued_messages 1000
```

**Container Image**: `docker.io/library/mosquitto:2.0.18`

**Volumes**:
- `/mosquitto/data/`: Persistent message storage
- `/mosquitto/log/`: Log files
- `/mosquitto/config/`: Configuration

## Using with Flightctl

### Creating the Catalog

First, apply the Catalog definition:
```bash
flightctl apply -f catalog/catalog.yaml
```

Verify the catalog was created:
```bash
flightctl get catalogs
```

### Creating Catalog Items

Apply each CatalogItem definition:
```bash
flightctl apply -f catalog/modbus-gas-sensor-catalogitem.yaml
flightctl apply -f catalog/modbus-mqtt-gateway-catalogitem.yaml
flightctl apply -f catalog/mosquitto-broker-catalogitem.yaml
```

Verify the items were created:
```bash
flightctl get catalogitems --catalog rtu-iiot
```

### Deploying Applications

Create a Fleet resource to deploy the applications:

```yaml
apiVersion: flightctl.io/v1alpha1
kind: Fleet
metadata:
  name: rtu-sensors
spec:
  selector:
    matchLabels:
      location: field-site-001
  template:
    spec:
      applications:
        - name: mosquitto
          catalog: rtu-iiot
          catalogItem: mosquitto-broker
          version: "2.0.18"
        
        - name: modbus-sensor
          catalog: rtu-iiot
          catalogItem: modbus-gas-sensor
          version: "1.0.0"
        
        - name: mqtt-gateway
          catalog: rtu-iiot
          catalogItem: modbus-mqtt-gateway
          version: "1.0.0"
          config:
            device_id: "field-site-001-sensor-01"
            poll_interval: 5
```

## Building Container Images

### Build all images
```bash
# Modbus Gas Sensor
podman build -t quay.io/luferrar/rtu-modbus-gas-sensor:1.0.0 \
  catalog/modbus-gas-sensor/

# Modbus-MQTT Gateway
podman build -t quay.io/luferrar/rtu-modbus-mqtt-gateway:1.0.0 \
  catalog/modbus-mqtt-gateway/

# Mosquitto (using official base image)
podman build -t quay.io/luferrar/rtu-mosquitto-broker:2.0.18 \
  catalog/mosquitto-broker/
```

### Push to registry
```bash
podman push quay.io/luferrar/rtu-modbus-gas-sensor:1.0.0
podman push quay.io/luferrar/rtu-modbus-mqtt-gateway:1.0.0
podman push quay.io/luferrar/rtu-mosquitto-broker:2.0.18
```

## Running Locally with Docker Compose

Create a `docker-compose.yaml`:

```yaml
version: '3.8'

services:
  mosquitto:
    image: mosquitto:2.0.18
    ports:
      - "1883:1883"
      - "9001:9001"
    volumes:
      - ./catalog/mosquitto-broker/mosquitto.conf:/mosquitto/config/mosquitto.conf
      - mosquitto_data:/mosquitto/data
      - mosquitto_logs:/mosquitto/log
    networks:
      - rtu

  modbus-sensor:
    image: quay.io/luferrar/rtu-modbus-gas-sensor:1.0.0
    ports:
      - "502:502"
    volumes:
      - ./catalog/modbus-gas-sensor/config.yaml:/app/config.yaml
    networks:
      - rtu

  mqtt-gateway:
    image: quay.io/luferrar/rtu-modbus-mqtt-gateway:1.0.0
    depends_on:
      - modbus-sensor
      - mosquitto
    environment:
      MODBUS_HOST: modbus-sensor
      MQTT_HOST: mosquitto
    volumes:
      - ./catalog/modbus-mqtt-gateway/config.yaml:/app/config.yaml
    networks:
      - rtu

volumes:
  mosquitto_data:
  mosquitto_logs:

networks:
  rtu:
```

Start the stack:
```bash
docker-compose up -d
```

Monitor data:
```bash
mosquitto_sub -h localhost -t 'rtu/sensor/#' -v
```

## Testing

### Subscribe to all sensor data
```bash
mosquitto_sub -h localhost -t 'rtu/sensor/sensor-001/#' -v
```

### Test with MQTT client
```bash
# View all topics
mosquitto_sub -h localhost -t '#' -v

# Monitor just flow rate
mosquitto_sub -h localhost -t 'rtu/sensor/sensor-001/flow'
```

### Verify Modbus connectivity
```bash
# Using Python/pymodbus
python3 << 'EOF'
from pymodbus.client import ModbusTcpClient

client = ModbusTcpClient(host='localhost', port=502)
client.connect()

result = client.read_holding_registers(100, 4, slave_id=1)
print(f"Registers: {result.registers}")

dp = result.registers[0] / 100
sp = result.registers[1] / 10
temp = result.registers[2] / 100
flow = result.registers[3] / 100

print(f"DP: {dp} Pa | SP: {sp} Pa | Temp: {temp}°C | Flow: {flow} m³/h")
EOF
```

## Production Deployment

### Security Considerations
1. **Enable TLS/SSL**: Configure certificate paths in `mosquitto.conf`
2. **Authentication**: Enable username/password in Mosquitto
3. **Network Isolation**: Use network policies to restrict access
4. **Resource Limits**: Set appropriate memory and CPU limits
5. **Logging**: Enable comprehensive logging for audit trails

### Scalability
- Deploy multiple gateway instances for high-throughput scenarios
- Use MQTT broker clustering for redundancy
- Implement load balancing for gateway instances

### Monitoring
- Monitor MQTT topic throughput
- Track Modbus read errors and retry rates
- Alert on sensor value anomalies
- Log all state changes

## References

- [Flightctl Documentation](https://github.com/flightctl/flightctl/blob/main/docs/user/using/managing-catalogs.md)
- [ISO 5167: Measurement of Fluid Flow](https://en.wikipedia.org/wiki/Orifice_plate)
- [Modbus TCP Specification](https://modbus.org/)
- [MQTT Protocol](https://mqtt.org/)
- [Mosquitto Documentation](https://mosquitto.org/documentation/)
