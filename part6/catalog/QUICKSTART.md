# Quick Start Guide

## One-Minute Overview

This catalog contains three complementary applications for industrial IoT gas flow measurement:

1. **Modbus Gas Sensor** - Simulates an RS485/Modbus gas sensor
2. **MQTT Gateway** - Bridges Modbus to MQTT 
3. **Mosquitto Broker** - MQTT message broker

They work together: Sensor → Gateway → MQTT Broker

## Prerequisites

- Flightctl CLI installed and configured
- Access to a Flightctl instance
- kubectl access (for Kubernetes-based Flightctl)

## Quick Setup (5 minutes)

### 1. Create the Catalog
```bash
flightctl apply -f catalog.yaml
```

### 2. Create the Catalog Items
```bash
flightctl apply -f modbus-gas-sensor-catalogitem.yaml
flightctl apply -f modbus-mqtt-gateway-catalogitem.yaml
flightctl apply -f mosquitto-broker-catalogitem.yaml
```

### 3. Verify Creation
```bash
# List catalogs
flightctl get catalogs

# List catalog items
flightctl get catalogitems --catalog rtu-iiot
```

### 4. Deploy to Devices
Create a Fleet with the applications (see README for full example)

## Local Testing with Docker Compose

```bash
# Start all services
docker-compose up -d

# Monitor data
mosquitto_sub -h localhost -t 'rtu/sensor/#' -v

# Stop services
docker-compose down
```

## Key Files

| File | Purpose |
|------|---------|
| `catalog.yaml` | Catalog definition |
| `modbus-gas-sensor-catalogitem.yaml` | Sensor catalog item |
| `modbus-mqtt-gateway-catalogitem.yaml` | Gateway catalog item |
| `mosquitto-broker-catalogitem.yaml` | Broker catalog item |
| `modbus-gas-sensor/` | Sensor container |
| `modbus-mqtt-gateway/` | Gateway container |
| `mosquitto-broker/` | Broker container |

## Troubleshooting

### Services can't connect
- Check service DNS names in config files
- Verify network connectivity between containers
- Check firewall rules (ports 502, 1883, 9001)

### No MQTT messages
- Verify gateway is running: `docker logs mqtt-gateway`
- Check Modbus connection: See Testing section in README
- Verify broker is accessible: `mosquitto_sub -h localhost -t '$SYS/#'`

### High CPU/Memory usage
- Reduce polling interval in gateway config
- Limit max connections in Mosquitto
- Check for infinite loops in logs

## Next Steps

1. Read the full [README.md](README.md) for detailed documentation
2. Build container images for your registry
3. Create Fleet deployments for your edge devices
4. Set up monitoring and alerting
5. Test with real sensor data

## Support

See README.md for references and support information.
