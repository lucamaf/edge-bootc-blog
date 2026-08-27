#!/bin/bash

################################################################################
# ROS2 Cyclictest Latency Measurement Script for RHEL
#
# This script runs cyclictest with ROS2-optimized parameters and processes
# the results for later analysis.
#
# Based on: https://github.com/ros-realtime/ros_realtime_benchmarks_config
# Adapted for RHEL 10 Real-Time
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

# Find the next test number folder
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

# Detect the isolated CPU(s) from the running kernel's isolcpus= karg
# (e.g. "isolcpus=managed_irq,domain,1" -> "1"), so cyclictest actually
# measures the protected core(s) instead of drifting onto housekeeping
# CPUs that still handle IRQs and system tasks. isolcpus can carry any
# combination of the "nohz", "domain", "managed_irq" flags before the
# actual cpu-list, so filter by keeping only numeric/range tokens rather
# than trying to name every possible flag.
ISOLCPUS_RAW=$(grep -o 'isolcpus=[^ ]*' /proc/cmdline | cut -d= -f2)
ISOLATED_CPUS=$(echo "$ISOLCPUS_RAW" | awk -F, '{
    out="";
    for (i = 1; i <= NF; i++) {
        if ($i ~ /^[0-9]+(-[0-9]+)?$/) {
            out = (out == "" ? $i : out "," $i);
        }
    }
    print out;
}')

# Count CPUs in the list (expanding ranges) so thread count (-t) matches
# the affinity set (-a) exactly.
count_cpu_list() {
    local list="$1" total=0 tok lo hi
    IFS=',' read -ra toks <<< "$list"
    for tok in "${toks[@]}"; do
        if [[ "$tok" == *-* ]]; then
            lo=${tok%-*}; hi=${tok#*-}
            total=$((total + hi - lo + 1))
        else
            total=$((total + 1))
        fi
    done
    echo "$total"
}

# -S (SMP mode) is shorthand for "one thread per visible CPU, affinity =
# use all" — it conflicts with an explicit -a, silently overriding it. So
# when isolation is detected, use -a/-t explicitly instead of -S.
if [ -n "$ISOLATED_CPUS" ]; then
    ISOLATED_COUNT=$(count_cpu_list "$ISOLATED_CPUS")
    CYCLICTEST_ARGS=(-a "$ISOLATED_CPUS" -t "$ISOLATED_COUNT" -p90)
    echo "Isolated CPU(s) detected: $ISOLATED_CPUS ($ISOLATED_COUNT thread(s), pinned with -a/-t)"
else
    CYCLICTEST_ARGS=(-Sp90)
    echo -e "${YELLOW}Warning: no isolcpus= found on /proc/cmdline. Running with -S (all visible CPUs) —${NC}"
    echo -e "${YELLOW}results will include non-isolated CPUs and won't reflect best-case RT latency.${NC}"
fi
echo ""

# Start test
echo -e "${GREEN}Starting cyclictest...${NC}"
echo "Command: cyclictest -D $DURATION -m -i$INTERVAL -h400 -q ${CYCLICTEST_ARGS[*]}"
echo ""

# Run cyclictest
# Parameters explained:
#   -D: Duration (format: 1h for 1 hour, 60m for 60 minutes, etc.)
#   -m: Use memory locking (prevents swapping to disk)
#   -i: Interval in microseconds (200 = 200us = 0.2ms)
#   -h: Histogram bins (400 bins for distribution analysis)
#   -q: Quiet mode (minimal output)
#   -a/-t/-p90, or -Sp90 as fallback: set above from the running kernel's
#     isolcpus= karg

if cyclictest -D "$DURATION" -m -i"$INTERVAL" -h400 -q "${CYCLICTEST_ARGS[@]}" > "$OUTPUT_FILE" 2>&1; then
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
