# Real-Time Bootc Container

## Overview

This `Containerfile2` creates a Real-Time (RT) optimized bootc container image built on top of the base `device001` image. It's designed to run real-time workloads with minimal latency by installing the RT kernel and configuring the system with real-time tuning parameters.

## Main Objective

The primary goal of this container is to:
- Replace the standard Linux kernel with the **Real-Time (RT) kernel** optimized for low-latency, deterministic performance
- Install real-time tuning tools and profiles
- Configure kernel arguments specifically for real-time performance
- Enable automatic RT profile tuning on first boot
- Provide a bootc-based image for edge devices requiring real-time capabilities

## Key Components

### 1. Real-Time Kernel Installation
- Removes the standard kernel (`kernel`, `kernel-core`, `kernel-modules`, etc.)
- Installs RT kernel variants: `kernel-rt-core`, `kernel-rt-modules`, `kernel-rt-devel`, `kernel-rt-modules-extra`

### 2. Real-Time Tools and Utilities
Installed packages include:
- **tuned**: Dynamic tuning daemon for system optimization
- **tuned-profiles-realtime**: Pre-configured real-time tuning profiles
- **realtime-tests**: Testing utilities for real-time performance
- **realtime-setup**: Real-time environment setup tools
- **rteval**: Real-time evaluation benchmarking
- **rtla**: Real-Time Linux Analysis tool
- **tuna**: CPU and IRQ affinity management
- **stress-ng**: System stress testing utility
- **tmux**: Terminal multiplexer for monitoring

### 3. First-Boot Real-Time Tuning
Since tuned profiles cannot be applied during container build time, a systemd service (`rt-post-install-tuning.service`) is installed that runs on first boot to automatically apply the configured real-time profile.

### 4. Kernel Arguments Configuration

The following kernel arguments are configured in `/usr/lib/bootc/kargs.d/` to optimize real-time performance:

#### **IOMMU Configuration** (Intel x86_64)
- **`iommu=pt`**: Sets IOMMU to passthrough mode for better I/O performance
- **`intel_iommu=on`**: Explicitly enables Intel IOMMU on x86_64 systems

#### **Memory Optimization**
- **`default_hugepagesz=1G`**: Sets default huge page size to 1GB for improved memory performance and reduced TLB (Translation Lookaside Buffer) misses

#### **CPU Latency Optimization**
- **`idle=poll`**: Disables CPU power management and idle states, keeping CPUs active for lower latency (critical for real-time workloads)

#### **Real-Time Kernel Configuration**
- **`rcutree.nocb_patience_delay=1000`**: Configures RCU (Read-Copy-Update) tree behavior for real-time performance optimization, reducing RCU callback latency

#### **Serial Console Configuration**
- **x86_64**: `console=ttyS1,115200` - Configures serial console output for Intel systems
- **ARM**: `console=tty0 console=ttyAMA0,115200n81` - Configures console for ARM-based systems


## Build Arguments

- **`TARGET_PROFILE`**: Name of the tuned profile to apply (e.g., `realtime`, `realtime-virtual-guest`, `realtime-virtual-host`)
- **`RTCPU_LIST`**: Comma-separated list of CPUs to be isolated for real-time use (default: `1`)

## Build Example

```bash
podman build \
  --build-arg TARGET_PROFILE=realtime \
  -t quay.io/luferrar/part5:device002 \
  -f Containerfile2 .
```

## Files

- **Containerfile2**: Main container definition
- **rt-tuning-first-boot.sh**: Script that applies real-time tuning on first boot
- **rt-post-install-tuning.service**: Systemd service that runs the tuning script on first boot

## Performance Considerations

This image is optimized for:
- **Low latency**: Ideal for industrial automation, robotics, and time-critical applications
- **Deterministic performance**: Reduced jitter and unpredictable delays
- **High throughput**: Optimized interrupt handling and memory management
- **Edge computing**: Suitable for edge devices requiring real-time capabilities

## Use Cases

- Real-time data acquisition systems
- Industrial control systems
- Robotics and autonomous systems
- Financial trading platforms
- Telecommunications and network processing
- Audio/video processing with strict latency requirements

## Notes

- Disabling CPU idle states (`idle=poll`) will increase power consumption
- Huge pages improve performance but reduce memory flexibility
- IRQbalance is disabled to prevent automatic CPU affinity changes
- The actual tuned profile application happens on the first boot after device deployment


