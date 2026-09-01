# Real-Time Bootc Container

## Overview

This `Containerfile7` creates a Real-Time (RT) optimized bootc container image for **RHEL 10**, built directly from `registry.redhat.io/rhel10/rhel-bootc:latest`. It's designed to run real-time workloads with minimal latency by installing the RT kernel and configuring the system with real-time tuning parameters. It supersedes `Containerfile2` (the RHEL 9 version of the same image).

## Main Objective

The primary goal of this container is to:
- Replace the standard Linux kernel with the **Real-Time (RT) kernel** optimized for low-latency, deterministic performance
- Install real-time tuning tools and profiles
- Configure kernel arguments specifically for real-time performance
- Enable automatic RT profile tuning on first boot
- Provide a bootc-based image for edge devices requiring real-time capabilities, including robot control

## Key Components

### 1. Real-Time Kernel Installation
- Removes the standard kernel (`kernel`, `kernel-core`, `kernel-modules`, `kernel-modules-core`)
- Installs the RT kernel: `kernel-rt-core`, `kernel-rt-modules`, `kernel-rt-modules-core`
- On RHEL 10, `dnf remove`/`dnf install` alone can leave a stale module directory behind from the
  removed kernel, which trips `bootc container lint`'s single-kernel check. Containerfile7 adds an
  explicit cleanup (`find /usr/lib/modules/ ... ! -iname '*rt*' -exec rm -rf {} +`) right after the
  swap to guarantee only the RT kernel's `/usr/lib/modules/<kver>` directory remains.

### 2. Real-Time Tools and Utilities
Installed packages include:
- **tuned**: Dynamic tuning daemon for system optimization
- **tuned-profiles-realtime**: Pre-configured real-time tuning profiles
- **realtime-tests**: Testing utilities for real-time performance (includes `cyclictest`)
- **realtime-setup**: Real-time environment setup tools (RT `limits.d`/udev rules)
- **rteval** / **rteval-loads**: Real-time evaluation benchmarking
- **rtla**: Real-Time Linux Analysis tool
- **tuna**: CPU and IRQ affinity management
- **stress-ng**: System stress testing utility, used to load the system while measuring latency
- **tmux**: Terminal multiplexer for monitoring

### 3. First-Boot Real-Time Tuning
Since tuned profiles cannot be applied during container build time, a systemd service (`rt-post-install-tuning.service`) is installed that runs on first boot to automatically apply the configured real-time profile.

### 4. Realtime Group for Non-Root RT Scheduling
`realtime-setup`'s own `%post` scriptlet creates the `realtime` group (GID 71), but on bootc/ostree
systems `/etc/passwd`/`/etc/group` are machine-local state — a group created at build time doesn't
reliably survive into the deployed system. Containerfile7 instead ships:
- `realtime-group.conf` — a `systemd-sysusers` snippet (`g realtime 71`) installed to
  `/usr/lib/sysusers.d/`, which is applied at every boot instead of at build time.
- `add-realtime-group.sh` + `realtime-group-first-boot.service` — a one-shot systemd unit that runs
  `usermod -aG realtime admin` on first boot, once the `admin` user (created by kickstart at install
  time, so it doesn't exist yet at build time) is available.

Membership in `realtime` grants the RT priority (`rtprio`) and memory-locking (`memlock`) limits
needed to run `cyclictest` and similar tools without `sudo` — see
[Real-Time Consistency Testing](#real-time-consistency-testing-cyclictest) below.

### 5. Kernel Arguments Configuration

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
  -t quay.io/luferrar/part5:device007rt \
  -f Containerfile7 .
```

## Files

- **Containerfile7**: Main container definition (RHEL 10)
- **rt-tuning-first-boot.sh**: Script that applies the tuned RT profile on first boot
- **rt-post-install-tuning.service**: Systemd service that runs the tuning script on first boot
- **realtime-group.conf**: `systemd-sysusers` snippet that creates the `realtime` group
- **add-realtime-group.sh**: Script that adds the `admin` user to the `realtime` group
- **realtime-group-first-boot.service**: Systemd service that runs the group-membership script on first boot

## Performance Considerations

This image is optimized for:
- **Low latency**: Ideal for industrial automation, robotics, and time-critical applications
- **Deterministic performance**: Reduced jitter and unpredictable delays
- **High throughput**: Optimized interrupt handling and memory management
- **Edge computing**: Suitable for edge devices requiring real-time capabilities

## Use Cases

- Real-time data acquisition systems
- Industrial control systems
- Robotics and autonomous systems (this image is intended to eventually drive robots — see testing below)
- Financial trading platforms
- Telecommunications and network processing
- Audio/video processing with strict latency requirements

## Real-Time Consistency Testing (cyclictest)

Before trusting this image to drive a robot, verify it actually delivers deterministic scheduling
latency. The [`part5/rt-tests/`](../rt-tests/) directory has a ready-made `cyclictest` toolkit
(`run-cyclictest.sh`, `analyze-results.sh`, `batch-test.sh`, `test-with-load.sh`) built around the
same methodology as the
[ROS 2 Real-Time Benchmarks cyclictest guide](https://ros-realtime.github.io/ros2_realtime_benchmarks/benchmark_tools/cyclictest.html)
and the original [OSADL `mklatencyplot.bash`](https://www.osadl.org/uploads/media/mklatencyplot.bash)
script. `cyclictest` measures the gap between a thread's intended and actual wake-up time — it's the
standard sanity check to run *before* benchmarking a real robotics workload on top.

Suggested workflow once a `device007rt`-based device is deployed and enrolled:

```bash
# On the device, as the admin user (member of the realtime group — no sudo needed
# for RT priority/mlock once you've re-logged in after first boot)
cd /path/to/rt-tests

# 1. Baseline: idle system
./run-cyclictest.sh 1 200
mv cyclictest_histogram.txt baseline_histogram.txt

# 2. Loaded: stress the isolated/non-isolated CPUs while measuring
stress-ng --cpu 2 --vm 1 --vm-bytes 512M --timeout 1h &
./run-cyclictest.sh 1 200
mv cyclictest_histogram.txt loaded_histogram.txt

# 3. Compare
./analyze-results.sh baseline_histogram.txt
./analyze-results.sh loaded_histogram.txt
```

For a production robot-control workload, run a long-duration soak test (6h+) and, once the actual
control loop exists, repeat the measurement with it running instead of (or alongside) `stress-ng`, per
the "ROS2-Specific Testing" section of the `rt-tests` README.

## Notes

- Disabling CPU idle states (`idle=poll`) will increase power consumption
- Huge pages improve performance but reduce memory flexibility
- IRQbalance is disabled to prevent automatic CPU affinity changes
- The actual tuned profile application, and the `realtime` group membership for `admin`, happen on
  first boot after device deployment — not at image build time