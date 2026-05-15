#!/bin/bash

################################################################################
# ROS2 Cyclictest Latency Measurement Script for RHEL
#
# This script runs cyclictest with ROS2-optimized parameters and processes
# the results for later analysis.
#
# Based on: https://github.com/ros-realtime/ros_realtime_benchmarks_config
# Adapted for RHEL 9 Real-Time
#
# Usage: ./run-cyclictest.sh [duration] [interval_us]
#   duration: Test duration with unit: 1h, 60m, 3600s (default: 1h)
#   interval_us: Timer interval in microseconds (default: 200)
#
################################################################################

set -e

# Configuration
DURATION="${1:-1h}"
INTERVAL="${2:-200}"

# Find the next test number
find_next_test_number() {
    local max_num=0
    for dir in test[0-9][0-9][0-9] test[0-9][0-9][0-9]_*; do
        if [ -d "$dir" ] 2>/dev/null; then
            # Extract number from directory name (first 6 chars after "test")
            local num=$(echo "$dir" | grep -o '^test[0-9]*' | sed 's/test//')
            if [ -n "$num" ] && [ "$num" -gt "$max_num" ]; then
                max_num=$num
            fi
        fi
    done
    echo $((max_num + 1))
}

TEST_NUM=$(find_next_test_number)
TEST_DIR=$(printf "test%03d" $TEST_NUM)
OUTPUT_FILE="$TEST_DIR/cyclictest_output.txt"
RESULTS_FILE="$TEST_DIR/cyclictest_results.txt"
HISTOGRAM_FILE="$TEST_DIR/cyclictest_histogram.txt"

# Create test directory
mkdir -p "$TEST_DIR"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if running as root (required for real-time priority)
if [ "$EUID" -ne 0 ]; then
    echo -e "${YELLOW}Warning: Not running as root. Real-time priority may not be available.${NC}"
    echo "Consider running with: sudo ./run-cyclictest.sh"
fi

# Verify cyclictest is available
if ! command -v cyclictest &> /dev/null; then
    echo -e "${RED}Error: cyclictest not found. Install realtime-tests package:${NC}"
    echo "  sudo dnf install realtime-tests"
    exit 1
fi

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}ROS2 Cyclictest Latency Measurement${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Test Number: $TEST_DIR"
echo "Configuration:"
echo "  Duration: $DURATION"
echo "  Interval: ${INTERVAL}us"
echo "  Output Directory: $TEST_DIR/"
echo ""

# Get system info
CORES=$(nproc)
echo "System Information:"
echo "  CPU Cores: $CORES"
echo "  Kernel: $(uname -r)"
echo "  RT Kernel: $(uname -r | grep -q rt && echo 'Yes' || echo 'No')"
echo "  Active tuned profile: $(tuned-adm active 2>/dev/null | awk '{print $NF}' || echo 'Unknown')"
echo ""

# Check if RT kernel is running
if ! uname -r | grep -q rt; then
    echo -e "${YELLOW}Warning: RT kernel may not be active. Check with: uname -r${NC}"
    echo -e "${YELLOW}Latency results may not be optimal.${NC}"
    echo ""
fi

# Start test
echo -e "${GREEN}Starting cyclictest...${NC}"
echo "Command: cyclictest -D $DURATION -m -Sp90 -i$INTERVAL -h400 -q"
echo ""

# Run cyclictest
# Parameters explained:
#   -D: Duration (format: 1h for 1 hour, 60m for 60 minutes, etc.)
#   -m: Use memory locking (prevents swapping to disk)
#   -S: Use system clock (CLOCK_SYSTIME)
#   -p: Priority (90 is high priority for RT scheduling)
#   -i: Interval in microseconds (200 = 200us = 0.2ms)
#   -h: Histogram bins (400 bins for distribution analysis)
#   -q: Quiet mode (minimal output)

# Note: -a option would set CPU affinity, but we let the system handle it
# For isolated CPUs, they're handled by kernel boot parameters in Containerfile2

if cyclictest -D "$DURATION" -m -Sp90 -i"$INTERVAL" -h400 -q > "$OUTPUT_FILE" 2>&1; then
    echo -e "${GREEN}✓ Cyclictest completed successfully${NC}"
else
    EXIT_CODE=$?
    echo -e "${RED}✗ Cyclictest failed with exit code $EXIT_CODE${NC}"
    exit $EXIT_CODE
fi

echo ""
echo -e "${GREEN}Processing results...${NC}"

# Extract header/summary lines (lines starting with #)
grep "^#" "$OUTPUT_FILE" > "$RESULTS_FILE" 2>/dev/null || true

# Extract histogram data (remove header comments and empty lines)
grep -v -e "^#" -e "^$" "$OUTPUT_FILE" | tr " " "\t" > "$HISTOGRAM_FILE" 2>/dev/null || true

# Get some statistics
if [ -s "$RESULTS_FILE" ]; then
    echo ""
    echo "Summary Statistics:"
    grep "Max Latencies" "$RESULTS_FILE" || echo "  Max Latencies: (see $RESULTS_FILE)"
    grep "Avg Latencies" "$RESULTS_FILE" || echo "  Avg Latencies: (see $RESULTS_FILE)"
fi

# Count histogram entries
HISTOGRAM_LINES=$(wc -l < "$HISTOGRAM_FILE" 2>/dev/null || echo "0")
echo ""
echo "Output Files Generated:"
echo "  ✓ $OUTPUT_FILE (raw cyclictest output, $(wc -l < "$OUTPUT_FILE") lines)"
echo "  ✓ $RESULTS_FILE (summary data, $(wc -l < "$RESULTS_FILE") lines)"
echo "  ✓ $HISTOGRAM_FILE (histogram data, $HISTOGRAM_LINES data lines)"
echo ""

echo -e "${GREEN}Next Steps:${NC}"
echo "  1. Analyze and plot results:"
echo "     ./analyze-results.sh $TEST_DIR/cyclictest_histogram.txt"
echo ""
echo "  2. View detailed results:"
echo "     head -30 $TEST_DIR/cyclictest_results.txt"
echo ""
echo "  3. View all test results:"
echo "     ls -lh test*/"
echo ""
echo "  4. Compare tests:"
echo "     diff <(head -10 $TEST_DIR/cyclictest_results.txt) <(head -10 test001/cyclictest_results.txt)"
echo ""

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Results saved in: $TEST_DIR/${NC}"
echo -e "${GREEN}========================================${NC}"
