#!/bin/bash

################################################################################
# Cyclictest Under Load Test Script
#
# This script runs cyclictest while generating system load to simulate
# realistic ROS2 workload conditions.
#
# Usage: ./test-with-load.sh [test_duration] [load_type] [load_intensity]
#   test_duration: Duration with unit: 1h, 60m, 3600s (default: 1h)
#   load_type: cpu, memory, io, or combined (default: combined)
#   load_intensity: 1-4, higher = more intense (default: 2)
#
# Examples:
#   ./test-with-load.sh 1h cpu 2
#   ./test-with-load.sh 2h combined 3
#
################################################################################

set -e

# Configuration
TEST_DURATION="${1:-1h}"
LOAD_TYPE="${2:-combined}"
LOAD_INTENSITY="${3:-2}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Timestamp for uniqueness
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
PARENT_DIR="load_test_${LOAD_TYPE}_${TIMESTAMP}"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cyclictest Under Load${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Parent Directory: $PARENT_DIR/"
echo "Configuration:"
echo "  Duration: $TEST_DURATION"
echo "  Load Type: $LOAD_TYPE"
echo "  Intensity: $LOAD_INTENSITY/4"
echo ""

# Create parent directory
mkdir -p "$PARENT_DIR"

# Check if stress-ng is available (recommended but not required)
STRESS_AVAILABLE=0
if command -v stress-ng &> /dev/null; then
    STRESS_AVAILABLE=1
fi

# Determine load parameters
case "$LOAD_TYPE" in
    cpu)
        if [ $STRESS_AVAILABLE -eq 1 ]; then
            WORKERS=$(($(nproc) / 2 * LOAD_INTENSITY / 2))
            WORKERS=$((WORKERS > 0 ? WORKERS : 1))
            LOAD_CMD="stress-ng --cpu $WORKERS --timeout ${TEST_DURATION} --quiet"
        else
            LOAD_CMD="for i in \$(seq 1 ${LOAD_INTENSITY}); do sh -c 'while true; do :; done' & done"
        fi
        ;;
    memory)
        if [ $STRESS_AVAILABLE -eq 1 ]; then
            VM_WORKERS=$((1 + LOAD_INTENSITY))
            VM_BYTES=$((256 * LOAD_INTENSITY))M
            LOAD_CMD="stress-ng --vm $VM_WORKERS --vm-bytes $VM_BYTES --timeout ${TEST_DURATION} --quiet"
        else
            echo -e "${YELLOW}Warning: stress-ng not found. Using CPU load instead.${NC}"
            LOAD_CMD="bash -c 'for i in \$(seq 1 2); do sh -c \"while true; do :; done\" & done'"
        fi
        ;;
    io)
        if [ $STRESS_AVAILABLE -eq 1 ]; then
            IO_WORKERS=$((1 + LOAD_INTENSITY))
            LOAD_CMD="stress-ng --hdd $IO_WORKERS --timeout ${TEST_DURATION} --quiet --temp-path /tmp"
        else
            echo -e "${YELLOW}Warning: stress-ng not found. Using CPU load instead.${NC}"
            LOAD_CMD="bash -c 'for i in \$(seq 1 2); do sh -c \"while true; do :; done\" & done'"
        fi
        ;;
    combined)
        if [ $STRESS_AVAILABLE -eq 1 ]; then
            WORKERS=$((LOAD_INTENSITY))
            LOAD_CMD="stress-ng --cpu $WORKERS --vm 1 --vm-bytes 256M --io 1 --timeout ${TEST_DURATION} --quiet"
        else
            echo -e "${YELLOW}Warning: stress-ng not found. Using CPU load instead.${NC}"
            LOAD_CMD="bash -c 'for i in \$(seq 1 2); do sh -c \"while true; do :; done\" & done'"
        fi
        ;;
    *)
        echo -e "${RED}Error: Unknown load type: $LOAD_TYPE${NC}"
        echo "Valid types: cpu, memory, io, combined"
        exit 1
        ;;
esac

echo "Test Configuration:"
echo "  Duration: $TEST_DURATION"
echo "  Load Type: $LOAD_TYPE"
echo "  Intensity: $LOAD_INTENSITY/4"
#echo "  Test Name: $TEST_NAME"
echo ""

if [ $STRESS_AVAILABLE -eq 1 ]; then
    echo "Load Command: stress-ng (installed)"
else
    echo -e "${YELLOW}Note: stress-ng not installed. Install with:${NC}"
    echo "  sudo dnf install stress-ng"
fi

echo ""

# Change to parent directory
cd "$PARENT_DIR"

echo -e "${GREEN}Starting load generation in background...${NC}"

# Start load generation
eval "$LOAD_CMD &" &>/dev/null || true
LOAD_PID=$!
echo "  ✓ Load process started (PID: $LOAD_PID)"
echo ""

# Give load time to start
sleep 2

echo -e "${GREEN}Starting cyclictest...${NC}"

# Run cyclictest (from parent directory context)
if ../run-cyclictest.sh "$TEST_DURATION" 200; then
    echo -e "${GREEN}✓ Cyclictest completed${NC}"
else
    echo -e "${RED}✗ Cyclictest failed${NC}"
fi

echo ""
echo -e "${GREEN}Stopping load generation...${NC}"

# Kill load processes
if kill $LOAD_PID 2>/dev/null; then
    echo "  ✓ Load stopped"
fi

# Kill any remaining stress-ng processes
pkill -f stress-ng 2>/dev/null || true
pkill -f "sh -c 'while true" 2>/dev/null || true

sleep 1

echo ""
echo -e "${GREEN}Analyzing results...${NC}"

# Analyze results from the test directory
TEST_RESULT_DIR="$(ls -td test[0-9][0-9][0-9] 2>/dev/null | head -1)"
if [ -d "$TEST_RESULT_DIR" ] && ../analyze-results.sh "$TEST_RESULT_DIR/cyclictest_histogram.txt" > /dev/null 2>&1; then
    mv latency_plot.png "$TEST_RESULT_DIR/latency_plot.png"
    echo -e "${GREEN}✓ Analysis complete${NC}"
fi

echo ""
echo -e "${GREEN}Test Results:${NC}"
echo "  Parent Directory: $PARENT_DIR/"
echo "  Test Folder: $PARENT_DIR/$TEST_RESULT_DIR/"
echo "  Raw output: $PARENT_DIR/$TEST_RESULT_DIR/cyclictest_output.txt"
echo "  Results: $PARENT_DIR/$TEST_RESULT_DIR/cyclictest_results.txt"
echo "  Histogram: $PARENT_DIR/$TEST_RESULT_DIR/cyclictest_histogram.txt"
echo "  Plot: $PARENT_DIR/$TEST_RESULT_DIR/latency_plot.png"
echo ""

# Go back to original directory
cd ..

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Load test complete${NC}"
echo -e "${GREEN}========================================${NC}"

echo ""
echo -e "${GREEN}To compare with baseline:${NC}"
echo "  # Review results"
echo "  head -20 $PARENT_DIR/$TEST_RESULT_DIR/cyclictest_results.txt"
echo ""
echo "  # View plot"
echo "  display $PARENT_DIR/$TEST_RESULT_DIR/latency_plot.png"
echo ""
echo -e "${GREEN}To run another test:${NC}"
echo "  ./test-with-load.sh 1h cpu 2"
echo "  ./test-with-load.sh 1h memory 3"
echo "  ./test-with-load.sh 1h combined 4"
