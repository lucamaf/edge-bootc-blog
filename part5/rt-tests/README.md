# ROS2 Real-Time Latency Testing with Cyclictest

This directory contains scripts and documentation for measuring real-time latency performance using cyclictest on RHEL 10, particularly for ROS2 deployments.

## Overview

These tools measure system latency during periodic tasks using the cyclictest utility from the `realtime-tests` package. The results help identify real-time kernel performance and potential latency issues.

## Prerequisites

### System Requirements

- RHEL 10 with real-time kernel (rt kernel)
- The `realtime-tests` package (pre-installed in the container)
- Optional: `gnuplot` for visualization

### Dependencies

The rt/Containerfile7 already installs the required `realtime-tests` package which includes:
- `cyclictest` - the main latency measurement tool
- `rteval` - real-time evaluation toolkit
- `rtla` - real-time latency analysis tool
- `tuna` - CPU and IRQ affinity tool

For visualization, install gnuplot:
```bash
sudo dnf install gnuplot
```

## Scripts

### 1. run-cyclictest.sh

Runs cyclictest with ROS2-optimized parameters and saves raw results.

**Usage:**
```bash
./run-cyclictest.sh [duration] [interval]
```

**Parameters:**
- `duration`: Test duration in hours (default: 1)
- `interval`: Timer interval in microseconds (default: 200)

**Example:**
```bash
# Run for 2 hours with 200us interval
./run-cyclictest.sh 2 200

# Run for 1 hour with default settings
./run-cyclictest.sh
```

**Output:**
- `cyclictest_output.txt` - Raw cyclictest output
- `cyclictest_results.txt` - Processed results (header lines)
- `cyclictest_histogram.txt` - Histogram data for plotting

**Cyclictest Parameters Explained:**
- `-D`: Duration (1h = 1 hour)
- `-m`: Use memory locking (prevents swapping)
- `-S`: Use system clock
- `-p`: Priority (90 = high priority)
- `-i`: Interval in microseconds (200 = 200μs)
- `-h`: Histogram bins size (400 bins)
- `-q`: Quiet mode (minimal output)

### 2. analyze-results.sh

Processes cyclictest output and generates a latency plot using gnuplot.

**Usage:**
```bash
./analyze-results.sh [histogram_file] [num_cores] [max_latency]
```

**Parameters:**
- `histogram_file`: Input histogram file (default: cyclictest_histogram.txt)
- `num_cores`: Number of CPU cores to plot (default: auto-detect)
- `max_latency`: Maximum latency in microseconds for X-axis (default: auto)

**Example:**
```bash
# Auto-detect settings
./analyze-results.sh

# Specify cores and max latency
./analyze-results.sh cyclictest_histogram.txt 4 500
```

**Output:**
- `latency_plot.png` - Visualization of latency distribution across cores
- `latency_plot.gnuplot` - Generated gnuplot commands

## Workflow Example

### Basic Single Run

```bash
# Start a cyclictest run
./run-cyclictest.sh 1 200

# Wait for completion, then analyze
./analyze-results.sh
```

### Extended Testing

For production-level benchmarking, run extended tests:

```bash
# 6-hour test (recommended for ROS2 workloads)
./run-cyclictest.sh 6 200

# Analyze results
./analyze-results.sh cyclictest_histogram.txt
```

### Multiple Test Comparison

Run tests under different conditions and compare:

```bash
# Test with standard tuning
./run-cyclictest.sh 1 200
mv cyclictest_histogram.txt baseline_histogram.txt

# Test with additional load
stress-ng --cpu 4 &
./run-cyclictest.sh 1 200
mv cyclictest_histogram.txt loaded_histogram.txt

# Kill stress test
pkill stress-ng
```

## Understanding Results

### Key Metrics

**Maximum Latency**: The highest latency value recorded during the test
- Indicates worst-case response time
- Critical for real-time deadlines
- Lower is better

**Average Latency**: Mean latency value
- Typical system response time
- Should be much lower than max latency

**Histogram Data**: Distribution of latency samples
- Shows how latencies are distributed
- Should show a sharp peak at low latency values
- Long tails indicate potential problems

### Interpreting the Plot

The generated `latency_plot.png` shows:
- X-axis: Latency in microseconds (μs)
- Y-axis: Number of samples (logarithmic scale)
- Each line: One CPU core
- Ideal plot: Sharp peak at low latency with minimal spread

**Good Results:**
- Peak latency < 100 μs for typical workloads
- Tight distribution (narrow peak)
- No long tail extending to high latencies

**Poor Results:**
- Peak latency > 500 μs
- Broad distribution
- Long tail extending to milliseconds

## Tuning and Optimization

### CPU Isolation

For best results, isolate CPUs for cyclictest using kernel boot parameters (already configured in Containerfile7):
- `isolcpus`: Prevents kernel scheduler from using specific CPUs
- `idle=poll`: Reduces latency from CPU idle states

### Profile Selection

The container uses the `realtime` tuned profile which includes:
- CPU governor set to performance
- IRQ affinity tuning
- Swap disabled
- Real-time process scheduling

Verify active profile:
```bash
tuned-adm active
```

### Real-Time Kernel Parameters

Check current RT kernel boot parameters:
```bash
cat /proc/cmdline
```

Key parameters for low latency:
```
iommu=pt intel_iommu=on
default_hugepagesz=1G
idle=poll
rcutree.nocb_patience_delay=1000
```

## Advanced Usage

### Running with System Load

Measure latency under realistic workload:

```bash
# Terminal 1: Start background workload
stress-ng --cpu 2 --vm 1 --vm-bytes 512M --timeout 1h

# Terminal 2: Run cyclictest
./run-cyclictest.sh 1 200

# Wait for both to complete and analyze
./analyze-results.sh
```

### ROS2-Specific Testing

For ROS2 applications:

```bash
# Terminal 1: Start your ROS2 application
source /opt/ros/humble/setup.bash  # or your ROS2 version
ros2 run your_package your_node &

# Terminal 2: Run cyclictest
./run-cyclictest.sh 2 200

# Wait for completion and analyze
./analyze-results.sh
```

### Collecting Multiple Data Points

For statistical significance, run multiple tests:

```bash
#!/bin/bash
for i in {1..5}; do
  echo "Running test $i..."
  ./run-cyclictest.sh 1 200
  mv cyclictest_histogram.txt test_${i}_histogram.txt
  mv cyclictest_results.txt test_${i}_results.txt
done

# Compare all results
for i in {1..5}; do
  echo "=== Test $i ==="
  head -20 test_${i}_results.txt
done
```

## Troubleshooting

### "cyclictest: command not found"
- Ensure realtime-tests package is installed: `dnf install realtime-tests`
- Verify you're running the real-time kernel: `uname -r` should include "rt"

### Plot generation fails
- Install gnuplot: `sudo dnf install gnuplot`
- Check histogram file format: `head -20 cyclictest_histogram.txt`

### Very high latency values (> 1000 μs)
- Disable CPU frequency scaling: `tuned-adm profile realtime`
- Disable swap: `swapoff -a`
- Check for system background tasks: `top`, `ps aux`
- Verify real-time kernel is running: `uname -r` should show "rt"

### Permission issues running cyclictest
- Use sudo for real-time priority: `sudo ./run-cyclictest.sh`
- Or add user to realtime group: `usermod -a -G realtime $USER` (the `admin` user created by
  kickstart is already added automatically on first boot by `realtime-group-first-boot.service` —
  see `rt/README.md`; this manual step is only needed for other accounts)

## References

- Original script: https://www.osadl.org/uploads/media/mklatencyplot.bash
- ROS Real-Time repository: https://github.com/ros-realtime/ros_realtime_benchmarks_config
- OSADL latency testing: https://www.osadl.org/Latency-measurement.osadl
- Linux RT documentation: https://wiki.linuxfoundation.org/realtime/start
- RHEL Real-Time Tuning: https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux_for_real_time/

## Container Integration

When running in the bootc container (part5):

1. The realtime-tests package is pre-installed via rt/Containerfile7
2. The rt-kernel is active
3. The realtime tuned profile is configured
4. Real-time boot parameters are applied

Example usage in container:

```bash
# Inside the container
cd /opt/rt-tests  # or wherever the scripts are mounted

# Run tests directly (already has RT capabilities)
./run-cyclictest.sh 1 200
./analyze-results.sh
```

## Performance Baselines

Typical latency values for RHEL 10 RT kernel on various workloads:

| Workload | Peak Latency | Avg Latency |
|----------|-------------|------------|
| Idle | 20-50 μs | 10-15 μs |
| Light (single-threaded) | 50-100 μs | 15-30 μs |
| Medium (multi-threaded) | 100-200 μs | 30-60 μs |
| Heavy (stress-ng) | 200-500 μs | 50-150 μs |

Note: Actual values depend on hardware, kernel version, and tuning.
