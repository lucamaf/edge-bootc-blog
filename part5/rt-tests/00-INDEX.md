# rt-tests Directory - Complete Documentation Summary

Created: May 15, 2026
Purpose: ROS2 Real-Time Latency Testing on RHEL 9 with Cyclictest

## What's Included

This directory contains a complete, production-ready setup for measuring and analyzing real-time latency on RHEL 9 systems using cyclictest. All files are adapted for RHEL and integrated with the real-time kernel configuration from `rt/Containerfile2`.

## File Manifest

### 📚 Documentation

1. **README.md** (8.1 KB)
   - Complete overview of real-time latency testing
   - Prerequisites and dependencies
   - Detailed workflow examples
   - Understanding results and metrics
   - Tuning and optimization guide
   - Advanced usage patterns
   - Troubleshooting guide
   - Performance baselines
   - → **Start here for comprehensive understanding**

2. **QUICKSTART.md** (6.0 KB)
   - 5-minute quick start guide
   - Common workflows with examples
   - Script overview table
   - Key metrics explanation
   - Troubleshooting quick reference
   - Performance optimization tips
   - Resources and support
   - → **Start here for quick reference**

3. **TECHNICAL_REFERENCE.md** (11 KB)
   - How cyclictest works
   - Real-time latency in ROS2
   - Detailed parameter explanation
   - Data interpretation guide
   - RHEL 9 kernel tuning details
   - Performance sources (controllable & uncontrollable)
   - Advanced multi-core analysis
   - ROS2 integration patterns
   - → **Reference for deep technical understanding**

### 🚀 Executable Scripts

1. **run-cyclictest.sh** (4.6 KB) - Executable
   ```bash
   ./run-cyclictest.sh [duration_hours] [interval_us]
   ```
   - Runs cyclictest with ROS2-optimized parameters
   - Memory locking enabled (prevents page faults)
   - Real-time priority 90
   - Generates histogram data for analysis
   - Color-coded console output with system info
   - Outputs: cyclictest_output.txt, cyclictest_results.txt, cyclictest_histogram.txt

2. **analyze-results.sh** (7.0 KB) - Executable
   ```bash
   ./analyze-results.sh [histogram_file] [num_cores] [max_latency]
   ```
   - Processes cyclictest histogram data
   - Generates PNG plot with gnuplot
   - Auto-detects parameters if not provided
   - Creates per-core analysis
   - Outputs: latency_plot.png, latency_plot.gnuplot

3. **test-with-load.sh** (5.4 KB) - Executable
   ```bash
   ./test-with-load.sh [duration] [load_type] [intensity]
   ```
   - Runs cyclictest with background system load
   - Load types: cpu, memory, io, combined
   - Simulates realistic ROS2 conditions
   - Organizes results by timestamp
   - Outputs: organized test_TYPE_TIMESTAMP/ directory

4. **batch-test.sh** (4.9 KB) - Executable
   ```bash
   ./batch-test.sh [iterations] [duration] [test_name]
   ```
   - Runs multiple tests for statistical analysis
   - Calculates min/max/avg/median latencies
   - Creates organized results directory
   - Generates baseline plot
   - Outputs: testname/ directory with all results

## Usage Patterns

### 1️⃣ Single Test (Basic)
```bash
./run-cyclictest.sh
./analyze-results.sh
# Files: cyclictest_output.txt, latency_plot.png
```

### 2️⃣ Realistic Load Testing (ROS2)
```bash
./test-with-load.sh 2 combined 2
# Results in: test_combined_TIMESTAMP/
```

### 3️⃣ Statistical Baseline (Production)
```bash
./batch-test.sh 10 1 my_baseline
# Results in: my_baseline/ with 10 test results
```

### 4️⃣ Extended Stability Check
```bash
./run-cyclictest.sh 6 200
./analyze-results.sh
# 6-hour test for long-term stability
```

## RHEL Integration

### From rt/Containerfile2

The container includes:
- ✅ Real-time kernel (kernel-rt)
- ✅ realtime-tests package (cyclictest, rteval, rtla, tuna)
- ✅ realtime tuned profile
- ✅ CPU isolation boot parameters
- ✅ Huge page configuration
- ✅ Memory locking support

**Already configured - no additional setup needed!**

### What You Get

Real-time guarantees for:
- Deterministic task scheduling (SCHED_FIFO)
- Predictable latency measurements
- Optimized for low-latency workloads
- Perfect for ROS2 real-time applications

## Output Files

After running tests, you'll get:

```
Single Test:
├── cyclictest_output.txt      (raw data, ~1000s lines)
├── cyclictest_results.txt     (summary statistics)
├── cyclictest_histogram.txt   (distribution data)
└── latency_plot.png           (visualization)

Batch Test:
├── test_1_output.txt
├── test_1_results.txt
├── test_1_histogram.txt
├── test_2_*
├── ...
├── test_10_*
└── baseline_latency_plot.png

Load Test:
└── test_combined_20260515_092345/
    ├── cyclictest_*
    └── latency_plot.png
```

## Performance Expectations

Typical latency values on RHEL 9 RT kernel:

| Scenario | Peak (μs) | Avg (μs) | Status |
|----------|-----------|---------|--------|
| Idle | 20-50 | 10-15 | Excellent |
| Light load | 50-100 | 15-30 | Good |
| Medium load | 100-200 | 30-60 | Good |
| Heavy load | 200-500 | 50-150 | Acceptable |
| Problematic | >1000 | >200 | ⚠️ Investigate |

## Quick Troubleshooting

| Issue | Solution |
|-------|----------|
| cyclictest not found | `sudo dnf install realtime-tests` |
| High latency (>1000μs) | `sudo tuned-adm profile realtime` |
| Permission denied | `sudo ./run-cyclictest.sh` or add to realtime group |
| gnuplot not found | `sudo dnf install gnuplot` |
| RT kernel not active | Verify: `uname -r` should include "rt" |

## Next Steps

1. **First Run**:
   ```bash
   ./run-cyclictest.sh
   ./analyze-results.sh
   # Review latency_plot.png
   ```

2. **Baseline Creation**:
   ```bash
   ./batch-test.sh 5 1 baseline
   # Statistical baseline for future comparison
   ```

3. **ROS2 Testing**:
   ```bash
   # Start your ROS2 app in one terminal
   # Then run:
   ./test-with-load.sh 2 combined 2
   ```

4. **Deep Dive**:
   - Read README.md for comprehensive guide
   - Read TECHNICAL_REFERENCE.md for deep learning
   - Run examples from QUICKSTART.md

## Support Resources

- **OSADL**: https://www.osadl.org/ (latency testing standards)
- **Linux RT**: https://wiki.linuxfoundation.org/realtime/start
- **ROS2 RT**: https://github.com/ros-realtime/ros_realtime_benchmarks_config
- **RHEL RT**: Red Hat Enterprise Linux for Real Time documentation

## Version Information

- **Created**: May 15, 2026
- **Based On**: 
  - Cyclictest v1.99
  - RHEL 9 Real-Time Kernel
  - ROS2 Humble (tested compatibility)
- **Tested On**: bootc RHEL 9 RT container

## Key Features

✅ RHEL 9 optimized (not generic Linux)
✅ ROS2 ready (realistic workload testing)
✅ Production ready (batch testing & statistics)
✅ Comprehensive documentation
✅ Color-coded output (easy to read)
✅ Auto-detection (sensible defaults)
✅ Error handling (graceful failures)
✅ Gnuplot visualization
✅ Temporal organization (timestamped results)
✅ Quick start guides

---

**Total Lines of Code**: 1662
**Total Documentation**: 25+ KB
**Estimated Runtime (all tests)**: 24-30 hours for production baseline

**Status**: ✅ Ready for Production Use
