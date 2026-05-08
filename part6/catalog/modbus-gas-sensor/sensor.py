#!/usr/bin/env python3
"""
Modbus RTU/TCP Gas Flow Sensor Simulator

Simulates a gas flow sensor with RS485/Modbus interface.
Measures:
  - Differential Pressure (DP) for orifice plates
  - Static Pressure (SP) for volume correction
  - Temperature (T) for gas density correction
  - Gas Flow (calculated)

Modbus Map:
  Holding Register 100: Differential Pressure (DP) in Pa
  Holding Register 101: Static Pressure (SP) in Pa
  Holding Register 102: Temperature (T) in Celsius
  Holding Register 103: Gas Flow (calculated) in m³/h
"""

import logging
import time
import math
import yaml
from pymodbus.server import AsyncModbusSerialServer, AsyncModbusTcpServer
from pymodbus.datastore import ModbusSequentialDataBlock, ModbusSlaveContext, ModbusServerContext
from pymodbus.device import ModbusDeviceIdentification, ModbusBasicInfo

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class GasSensorSimulator:
    """Simulates gas flow measurements based on differential pressure, static pressure, and temperature."""
    
    def __init__(self, config):
        self.config = config
        self.dp = config.get('initial_dp', 50.0)  # Pa
        self.sp = config.get('initial_sp', 101325.0)  # Pa (1 atm)
        self.temp = config.get('initial_temp', 20.0)  # Celsius
        self.orifice_diameter = config.get('orifice_diameter', 0.05)  # meters
        self.discharge_coefficient = config.get('discharge_coefficient', 0.61)  # Typical value
        
    def calculate_flow(self):
        """
        Calculate gas flow using ISO 5167 (orifice plate) formula
        Q = C * A * sqrt(2 * DP / rho)
        where:
          C = discharge coefficient
          A = orifice area
          DP = differential pressure
          rho = gas density (calculated from SP and T)
        """
        if self.dp < 0:
            return 0.0
            
        # Calculate gas density using ideal gas law
        # At pressure P and temperature T: rho = P / (R_specific * T)
        # R_specific for air ≈ 287 J/(kg·K)
        T_kelvin = self.temp + 273.15
        R_specific = 287.0
        rho = self.sp / (R_specific * T_kelvin)
        
        # Orifice area
        A = math.pi * (self.orifice_diameter / 2) ** 2
        
        # Flow calculation
        if rho > 0:
            flow = self.discharge_coefficient * A * math.sqrt(2 * self.dp / rho)
            # Convert m³/s to m³/h
            flow_m3h = flow * 3600
            return max(0, flow_m3h)
        return 0.0
    
    def simulate_measurements(self):
        """Simulate realistic sensor data with small variations."""
        # Add small random variations to simulate real sensor behavior
        import random
        self.dp += random.uniform(-2, 2)  # ±2 Pa variation
        self.sp += random.uniform(-100, 100)  # ±100 Pa variation
        self.temp += random.uniform(-0.5, 0.5)  # ±0.5°C variation
        
        # Keep values within realistic ranges
        self.dp = max(0, min(1000, self.dp))  # 0-1000 Pa
        self.sp = max(95000, min(110000, self.sp))  # 95-110 kPa
        self.temp = max(-10, min(60, self.temp))  # -10 to 60°C
        
        flow = self.calculate_flow()
        return self.dp, self.sp, self.temp, flow


def load_config():
    """Load configuration from config.yaml."""
    with open('config.yaml', 'r') as f:
        return yaml.safe_load(f) or {}


async def update_registers(sensor, context, slave_id=1):
    """Periodically update Modbus registers with sensor data."""
    while True:
        try:
            dp, sp, temp, flow = sensor.simulate_measurements()
            
            # Convert float to integer for Modbus registers (fixed point)
            # Store with 2 decimal places precision
            dp_int = int(dp * 100)
            sp_int = int(sp * 10)
            temp_int = int(temp * 100)
            flow_int = int(flow * 100)
            
            # Update holding registers
            builder = context[slave_id].builder
            builder.reset()
            builder.add_holding_registers(100, [dp_int, sp_int, temp_int, flow_int])
            
            logger.info(f"DP: {dp:.2f} Pa | SP: {sp:.2f} Pa | T: {temp:.2f}°C | Flow: {flow:.4f} m³/h")
            time.sleep(1)
            
        except Exception as e:
            logger.error(f"Error updating registers: {e}")
            time.sleep(1)


async def run_server():
    """Run Modbus TCP server."""
    config = load_config()
    server_config = config.get('server', {})
    host = server_config.get('host', '0.0.0.0')
    port = server_config.get('port', 502)
    
    logger.info(f"Starting Modbus TCP server on {host}:{port}")
    
    sensor = GasSensorSimulator(config.get('sensor', {}))
    
    # Create data store
    store = ModbusSlaveContext(
        di=ModbusSequentialDataBlock(0, [0] * 100),
        co=ModbusSequentialDataBlock(0, [0] * 100),
        hr=ModbusSequentialDataBlock(0, [0] * 200),
        ir=ModbusSequentialDataBlock(0, [0] * 100),
    )
    
    context = ModbusServerContext(stores={1: store}, single=False)
    
    # Set device identification
    identity = ModbusDeviceIdentification(
        info=ModbusBasicInfo(),
        objects={
            0x00: "RTU Gas Sensor Simulator",
            0x01: "Modbus TCP",
            0x02: "1.0.0",
        },
    )
    
    # Create and start server
    server = await AsyncModbusTcpServer(
        ("0.0.0.0", 502),
        context=context,
        identity=identity,
    )
    
    async with server:
        logger.info("Modbus server started successfully")
        # Start updating registers
        await update_registers(sensor, context)


if __name__ == "__main__":
    import asyncio
    asyncio.run(run_server())
