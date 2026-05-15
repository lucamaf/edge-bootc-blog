# Technical Reference - Cyclictest and Real-Time Latency

## What is Cyclictest?

Cyclictest is a program that measures real-time system latency by creating periodic tasks and measuring their actual wake-up time compared to expected time. It's part of the `rt-tests` package from the Linux Foundation's Real-Time Working Group.

### How It Works

1. **Timer Setup**: Creates a periodic task with precise interval (e.g., 200μs)
2. **Task Wake-Up**: Task waits for each period to expire
3. **Latency Measurement**: Compares actual wake-up time to expected time
4. **Histogram**: Records distribution of latencies
5. **Analysis**: Calculates statistics (min, max, avg)

```
Ideal Timeline:
Period 1  Period 2  Period 3
│         │        │
Expected: ├─200μs─┤├─200μs─┤
Actual:   ├─202μs─┤├─195μs─┤  (Latency Jitter: 2-5μs)

Latency = Actual Wake-Up Time - Expected Wake-Up Time
```

## Real-Time Latency in ROS2

### Why Latency Matters

ROS2 applications often have real-time requirements:

- **Robotic Control**: Must react within milliseconds to sensor input
- **Autonomous Systems**: Time-critical decision making
- **Safety Systems**: Hard deadlines for safety-critical operations
- **Sensor Processing**: Fixed frequency processing (e.g., 1000 Hz camera feed)

### Maximum Latency Deadline

If your ROS2 node must process at 100 Hz:
- Period = 10ms = 10,000μs
- Maximum acceptable latency ≈ 5,000μs (50% of period is aggressive)
- Recommended: < 1,000μs for safety margin

### Latency Categories

```
Latency Type          Typical Range    ROS2 Impact
──────────────────────────────────────────────────
Interrupt latency     1-50 μs          Minimal
Context switching     50-500 μs        Moderate
Memory access         100-1000 μs      High
Page faults           1000+ μs         Critical
Thermal throttling    > 10000 μs       System failure
```

## Cyclictest Parameters Explained

### Our Configuration

```bash
cyclictest -D 1h -m -Sp90 -i200 -h400 -q
```

| Parameter | Value | Purpose |
|-----------|-------|---------|
| `-D` | 1h | Duration (1 hour = 3600 seconds ≈ 18M iterations at 200μs) |
| `-m` | - | Memory locking (mlockall - prevents page faults) |
| `-S` | - | Use system timer (CLOCK_SYSTIME) |
| `-p` | 90 | Priority (real-time FIFO priority, 1-99, higher is better) |
| `-i` | 200 | Interval in microseconds (must be > kernel tick = 1000μs/HZ) |
| `-h` | 400 | Histogram bins (resolution of latency distribution) |
| `-q` | - | Quiet mode (only output results, not intermediate data) |

### Alternative Configurations

```bash
# Very short interval (high frequency monitoring)
cyclictest -D 1h -m -Sp90 -i100 -h400 -q

# Very long duration (extended stability test)
cyclictest -D 24h -m -Sp90 -i200 -h400 -q

# Multiple threads on different CPUs
cyclictest -D 1h -m -Sp90 -i200 -h400 -q -t2 -a0,2

# Custom CPU affinity
cyclictest -D 1h -m -Sp90 -i200 -h400 -q -a1
```

## Data Interpretation

### Histogram Output Format

Raw output from cyclictest:
```
# cyclictest-1.99, heavy load
# Latency (μs)
# Index: Count at index
0: 1000000      <- 1M samples at 0μs latency
1: 50000        <- 50k samples at 1μs latency
5: 30000        <- 30k samples at 5μs latency
20: 5000        <- 5k samples at 20μs latency
50: 100         <- 100 samples at 50μs latency (outliers)
200: 10         <- 10 samples at 200μs latency (bad news)
```

### Statistics Calculation

From sample data:
```
Max Latencies = 200 μs           (worst case)
Avg Latencies = 15 μs            (typical case)
Std Dev = 8 μs                   (measure of variability)
```

**Interpretation:**
- Max 200μs: Occasional spikes but not extreme
- Avg 15μs: Excellent typical performance
- Std Dev 8μs: Moderate variability (good for RT)

### Plot Interpretation

**X-Axis**: Latency in microseconds (logarithmic scale recommended)
**Y-Axis**: Number of samples (count at each latency value)

```
Ideal Distribution (Good RT System):
     │
   1M├╱╲
     │  ╲╲
  100k│   ╲╲
     │     ╲╲
   10k├      ╲╲
     │        ╲
  100├         ╲─── Sharp peak at low latency
     │            ╲
    1├             ╲_____
     └──────────────────────
       0   20   50  100  200+ μs


Poor Distribution (Problematic System):
     │
  100k├╱╲╲╲
     │╱╱╱╱╱╱
   10k├╱╱╱
     │╱╱
  1k├─── Spread out (bad)
     │
   1├─────────────────
     └──────────────────────
       0   20   50  100  200+ μs
```

## RHEL 9 Real-Time Kernel

### Boot Parameters (in Containerfile2)

```
iommu=pt                    # IOMMU passthrough mode (latency improvement)
intel_iommu=on              # Enable Intel IOMMU hardware
default_hugepagesz=1G       # Use 1GB huge pages (reduce TLB misses)
idle=poll                   # Poll CPU instead of sleep (lower latency)
rcutree.nocb_patience_delay=1000  # RCU callback tuning
console=ttyS1,115200       # Serial console output
```

### Tuned Profile: realtime

The `realtime` profile optimizes for low latency:

```
[main]
summary=Optimize for real-time tasks

[sysctl]
kernel.sched_migration_cost_ns=5000000
kernel.sched_min_granularity_ns=10000000
vm.swappiness=10
kernel.hung_task_timeout_secs=600

[cpu]
force_latency=cstate.id:0,1
governor=performance

[irq]
affinity_set=isolated
```

Verify active:
```bash
tuned-adm active
# or show settings:
tuned-adm verify
```

### CPU Isolation

From Containerfile2 boot parameters, specific CPUs can be isolated.

**Check current isolation:**
```bash
cat /proc/cmdline | grep -o 'isolcpus=[^ ]*'
```

**Benefits:**
- Kernel scheduler avoids isolated CPUs
- Reduces context switching
- Minimizes cache misses
- Enables CPU affinity for cyclictest

## Latency Sources in RHEL 9

### Controllable Sources

1. **Context Switching**
   - Fixed by using realtime-priority tasks
   - Mitigated by CPU isolation
   - **Typical latency**: 50-200μs

2. **Memory Access**
   - Fixed by mlockall (memory locking)
   - Mitigated by huge pages
   - **Typical latency**: 100-500μs

3. **Interrupt Handling**
   - Fixed by CPU isolation
   - Mitigated by IRQ affinity tuning
   - **Typical latency**: 10-100μs

4. **CPU Frequency Scaling**
   - Fixed by setting to performance mode
   - **Typical latency if active**: 1000+ μs

### Uncontrollable Sources

1. **System Management Interrupts (SMI)**
   - Hardware level, can't be disabled from OS
   - **Typical latency**: 100-1000μs

2. **Thermal Management**
   - Hardware throttling, triggers at high temp
   - **Typical latency when active**: 5000+ μs

3. **Bus Contention**
   - Multiple devices competing for memory bandwidth
   - **Typical latency**: 100-500μs

## Performance Tuning Checklist

- [ ] Verify RT kernel active: `uname -r` contains "rt"
- [ ] Verify realtime tuned profile: `tuned-adm active`
- [ ] Check CPU isolation: `cat /proc/cmdline`
- [ ] Verify performance governor: `cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor`
- [ ] Disable swap: `swapon --show` should be empty
- [ ] Run baseline test: `./run-cyclictest.sh 1 200`
- [ ] Analyze results: `./analyze-results.sh`
- [ ] Compare to target latency values

## Advanced: Multiple CPU Core Analysis

Cyclictest can run on multiple cores simultaneously. The histogram shows results for each core:

```
# Latency  CPU0    CPU1    CPU2    CPU3
0         100000  100000  100000  100000
1         50000   50000   50000   50000
5         30000   29000   31000   30000
10        5000    5100    4900    5200
```

**Analysis per core:**
- Look for consistent patterns (all cores similar)
- Identify outlier cores (one core worse than others)
- Check for core-specific issues

**If one core has bad latency:**
1. Could indicate hardware issue
2. Could indicate uneven load distribution
3. Check CPU affinity in your ROS2 application

## ROS2 Integration

### RT Linux + ROS2 Middleware

ROS2 can leverage real-time guarantees:

```
┌──────────────────────────────────────┐
│ ROS2 Application (your code)         │
│ ├─ Callback: process_sensor()       │
│ └─ Frequency: 100 Hz (10ms)         │
├──────────────────────────────────────┤
│ RMW (Middleware Layer)               │
│ └─ Uses DDS/RTPS protocol           │
├──────────────────────────────────────┤
│ Linux RT Kernel                      │
│ ├─ SCHED_FIFO priority scheduling   │
│ └─ Low latency guarantees            │
├──────────────────────────────────────┤
│ Real-Time Hardware (CPU + Memory)    │
│ └─ Tuned for deterministic response  │
└──────────────────────────────────────┘

Latency Budget:
Total: 10ms (100 Hz)
├─ ROS2 overhead: 1-2ms
├─ Cyclictest measurement: 20-50μs
├─ Your callback: 5-8ms
└─ Buffer/margin: 1ms
```

### Recommended ROS2 Settings

```bash
# Set high priority
sudo chrt -f 50 ros2 run your_package your_node

# Use isolated CPUs
taskset -c 1-3 ros2 run your_package your_node

# Combined
sudo chrt -f 50 taskset -c 1-3 ros2 run your_package your_node
```

## References

### Cyclictest
- Original: https://git.kernel.org/pub/scm/utils/rt-tests/rt-tests.git/
- Documentation: https://wiki.linuxfoundation.org/realtime/documentation/howto/tools/cyclictest

### Real-Time Linux
- OSADL: https://www.osadl.org/
- Linux Foundation RT: https://wiki.linuxfoundation.org/realtime/start

### RHEL Real-Time
- Red Hat RT Documentation: https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux_for_real_time/
- RHEL Performance Tuning: https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux_for_real_time/9/html/configuring_and_managing_monitoring_tools/getting-started-with-real-time_monitoring-tools

### ROS2 Real-Time
- ROS2 Real-Time Support: https://design.ros2.org/articles/real_time_systems.html
- ROS Real-Time Working Group: https://github.com/ros-realtime

---

**Technical Reference Version**: 1.0
**Last Updated**: May 15, 2026
**Based On**: Linux RT v6.x, RHEL 9, ROS2 Humble
