# Quick Start Guide - ROS2 Cyclictest Latency Measurement

## 5-Minute Quick Start

### 1. Basic Latency Test (1 hour)
```bash
cd /path/to/rt-tests
./run-cyclictest.sh
./analyze-results.sh
# View latency_plot.png
```

### 2. Test with System Load (realistic ROS2 conditions)
```bash
./test-with-load.sh 1 combined 2
# Results in: test_combined_TIMESTAMP/
```

### 3. Multiple Tests for Comparison
```bash
./batch-test.sh 5 1 my_baseline
# Results in: my_baseline/
```

## Script Overview

| Script | Purpose | Time | Output |
|--------|---------|------|--------|
| `run-cyclictest.sh` | Measure latency | 1-6 hours | Histogram data |
| `analyze-results.sh` | Plot results | 1 minute | PNG plot |
| `test-with-load.sh` | Test under load | 1-6 hours | Organized results |
| `batch-test.sh` | Run multiple tests | Hours × iterations | Statistical analysis |

## Common Workflows

### Scenario 1: Quick Baseline Check
```bash
./run-cyclictest.sh 1 200
./analyze-results.sh
```
**Time:** ~1 hour + 1 minute

### Scenario 2: Extended Stability Test
```bash
./run-cyclictest.sh 6 200
./analyze-results.sh
```
**Time:** ~6 hours + 1 minute

### Scenario 3: ROS2 Application Testing
```bash
# Terminal 1
source /opt/ros/humble/setup.bash
ros2 run your_package your_node &

# Terminal 2
./run-cyclictest.sh 2 200
./analyze-results.sh
```
**Time:** ~2 hours

### Scenario 4: Statistical Comparison (Production)
```bash
# Baseline
./batch-test.sh 10 1 baseline_results

# After tuning
./batch-test.sh 10 1 tuned_results
```
**Time:** ~10-20 hours

### Scenario 5: Realistic Workload Test
```bash
./test-with-load.sh 2 combined 3
# Results in: test_combined_TIMESTAMP/
```
**Time:** ~2 hours

## Understanding Results

### Key Metrics
- **Max Latency**: Highest latency recorded (worst-case)
- **Avg Latency**: Average latency value
- **Median**: Middle value in distribution

### Interpreting the Plot
```
Good:    Narrow peak, tight distribution, all under 100μs
         ↓
         ████
         ████████
         ████████████


Poor:    Broad distribution, long tail extending high
         ↓
      ██████
      ██████░░
      ██░░░░░░░░░░░
```

### Target Values (RHEL 10 RT Kernel)
- **Idle System**: 20-50 μs
- **Light Load**: 50-100 μs
- **Medium Load**: 100-200 μs
- **Heavy Load**: 200-500 μs

## Troubleshooting

### Problem: "cyclictest: command not found"
```bash
# Install realtime-tests package
sudo dnf install realtime-tests
```

### Problem: Very high latency (> 1000 μs)
```bash
# Check if RT kernel is running
uname -r  # Should include "rt"

# Verify tuned profile
tuned-adm active

# Set to realtime profile
sudo tuned-adm profile realtime

# Disable CPU frequency scaling
sudo systemctl stop cpupower
```

### Problem: Permission denied when running cyclictest
```bash
# Add user to realtime group (requires logout/login)
sudo usermod -a -G realtime $USER

# Or run with sudo
sudo ./run-cyclictest.sh
```

### Problem: "gnuplot: command not found"
```bash
# Install gnuplot for visualization
sudo dnf install gnuplot
```

## File Organization After Running Tests

```
rt-tests/
├── README.md
├── run-cyclictest.sh
├── analyze-results.sh
├── test-with-load.sh
├── batch-test.sh
├── QUICKSTART.md (this file)
│
├── cyclictest_output.txt         (from run-cyclictest.sh)
├── cyclictest_results.txt        (from run-cyclictest.sh)
├── cyclictest_histogram.txt      (from run-cyclictest.sh)
├── latency_plot.png              (from analyze-results.sh)
├── latency_plot.gnuplot          (from analyze-results.sh)
│
├── test_combined_20260515_092345/
│   ├── cyclictest_output.txt
│   ├── cyclictest_results.txt
│   ├── cyclictest_histogram.txt
│   └── latency_plot.png          (from test-with-load.sh)
│
└── my_baseline/
    ├── test_1_output.txt
    ├── test_1_results.txt
    ├── test_1_histogram.txt
    ├── test_2_output.txt
    ├── ...
    ├── test_10_results.txt
    └── baseline_latency_plot.png  (from batch-test.sh)
```

## Advanced Usage

### Compare Two Runs
```bash
# Get max latency from both tests
echo "Run 1:"
grep "Max Latencies" run1/test_1_results.txt

echo "Run 2:"
grep "Max Latencies" run2/test_1_results.txt
```

### Create Custom Test Script
```bash
#!/bin/bash
# my_test.sh

# Run baseline
./run-cyclictest.sh 1 200
cp cyclictest_histogram.txt baseline.txt

# Run with custom load
# (add your workload here)

# Compare
./analyze-results.sh baseline.txt
```

### Monitor Multiple Cores Differently
Edit the plot parameters in analyze-results.sh to change X-axis range:
```bash
./analyze-results.sh cyclictest_histogram.txt 4 1000
# 4 cores, 1000us max on X-axis
```

## Performance Optimization Tips

1. **Isolate CPUs**: Already configured in Containerfile7
   ```bash
   cat /proc/cmdline | grep -o 'isolcpus=[^ ]*'
   ```

2. **Verify Realtime Profile**:
   ```bash
   sudo tuned-adm active
   sudo tuned-adm recommend
   ```

3. **Check IRQ Affinity**:
   ```bash
   cat /proc/irq/*/smp_affinity
   ```

4. **Disable Swap** (if not already):
   ```bash
   sudo swapoff -a
   ```

5. **Monitor During Test**:
   ```bash
   # In another terminal
   watch -n 1 'ps aux | grep -E "cyclictest|stress"'
   ```

## Resources

- [OSADL Latency Testing](https://www.osadl.org/Latency-measurement.osadl)
- [ROS Real-Time](https://github.com/ros-realtime/ros_realtime_benchmarks_config)
- [Linux RT Wiki](https://wiki.linuxfoundation.org/realtime/start)
- [RHEL Real-Time Tuning](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux_for_real_time/)

## Support

For issues with:
- **Cyclictest**: Check realtime-tests documentation
- **Gnuplot**: Check gnuplot official documentation
- **ROS2**: Consult ROS2 real-time guide
- **RHEL**: Check Red Hat documentation

---

**Last Updated**: May 15, 2026
**Tested On**: RHEL 10 with RT kernel (part5 bootc container)
