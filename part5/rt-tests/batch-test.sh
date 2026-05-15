#!/bin/bash

################################################################################
# Batch Cyclictest Runner for Statistical Analysis
#
# This script runs multiple cyclictest iterations to collect statistical data
# for more reliable latency analysis.
#
# Usage: ./batch-test.sh [num_iterations] [duration_per_test] [test_name]
#   num_iterations: Number of test runs (default: 5)
#   duration_per_test: Duration with unit: 1h, 60m, 3600s (default: 1h)
#   test_name: Descriptive name for results directory (default: batch_TIMESTAMP)
#
# Example:
#   ./batch-test.sh 5 1h baseline
#   ./batch-test.sh 10 2h ros2_loaded
#
################################################################################

set -e

# Configuration
NUM_ITERATIONS="${1:-5}"
DURATION_PER_TEST="${2:-1h}"
TEST_NAME="${3:-batch_$(date +%Y%m%d_%H%M%S)}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Batch Cyclictest Runner${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

echo "Configuration:"
echo "  Number of iterations: $NUM_ITERATIONS"
echo "  Duration per test: $DURATION_PER_TEST"
echo "  Results directory: $TEST_NAME/"
echo ""

# Create results directory
mkdir -p "$TEST_NAME"

echo -e "${GREEN}Starting batch tests...${NC}"
echo ""

# Store max latencies for comparison
LATENCIES=()

# Run tests
for i in $(seq 1 $NUM_ITERATIONS); do
    echo -e "${BLUE}=== Test $i of $NUM_ITERATIONS ===${NC}"
    echo "Running cyclictest for $DURATION_PER_TEST..."
    
    # Run cyclictest
    if ./run-cyclictest.sh "$DURATION_PER_TEST" 200; then
        # Move results to batch directory
        mv cyclictest_output.txt "$TEST_NAME/test_${i}_output.txt"
        mv cyclictest_results.txt "$TEST_NAME/test_${i}_results.txt"
        mv cyclictest_histogram.txt "$TEST_NAME/test_${i}_histogram.txt"
        
        # Extract max latency
        MAX_LAT=$(grep "Max Latencies" "$TEST_NAME/test_${i}_results.txt" 2>/dev/null | tr " " "\n" | sort -n | tail -1 | sed 's/^0*//;s/.*\([0-9]\{1,\}\).*/\1/' || echo "0")
        LATENCIES+=($MAX_LAT)
        
        echo -e "${GREEN}✓ Test $i completed (max: ${MAX_LAT}us)${NC}"
    else
        echo -e "${RED}✗ Test $i failed${NC}"
    fi
    
    echo ""
done

echo -e "${GREEN}Batch testing complete!${NC}"
echo ""

# Analyze results
echo -e "${GREEN}Statistical Analysis:${NC}"
echo ""

if [ ${#LATENCIES[@]} -gt 0 ]; then
    # Calculate statistics
    SORTED=($(printf '%s\n' "${LATENCIES[@]}" | sort -n))
    
    # Min/Max
    MIN=${SORTED[0]}
    MAX=${SORTED[-1]}
    
    # Sum
    SUM=0
    for val in "${LATENCIES[@]}"; do
        SUM=$((SUM + val))
    done
    
    # Average
    AVG=$((SUM / ${#LATENCIES[@]}))
    
    # Median
    LEN=${#LATENCIES[@]}
    if [ $((LEN % 2)) -eq 0 ]; then
        MEDIAN=$(( (${SORTED[$((LEN/2-1))]} + ${SORTED[$((LEN/2))]}) / 2 ))
    else
        MEDIAN=${SORTED[$((LEN/2))]}
    fi
    
    echo "Maximum Latency Statistics:"
    echo "  Minimum: ${MIN}us"
    echo "  Maximum: ${MAX}us"
    echo "  Average: ${AVG}us"
    echo "  Median:  ${MEDIAN}us"
    echo "  Range:   $((MAX - MIN))us"
    echo "  Samples: ${#LATENCIES[@]}"
    echo ""
    
    # Distribution
    echo "Distribution:"
    echo "  Values: ${LATENCIES[@]}"
    echo ""
fi

# Generate comparison plot (analyze first test as baseline)
echo -e "${GREEN}Generating baseline plot...${NC}"
if ./analyze-results.sh "$TEST_NAME/test_1_histogram.txt"; then
    mv latency_plot.png "$TEST_NAME/baseline_latency_plot.png"
    echo "  ✓ Baseline plot: $TEST_NAME/baseline_latency_plot.png"
fi

echo ""
echo -e "${GREEN}Results Summary:${NC}"
echo "  Results directory: $TEST_NAME/"
echo "  Files generated:"

ls -1 "$TEST_NAME/" | while read file; do
    SIZE=$(ls -lh "$TEST_NAME/$file" | awk '{print $5}')
    echo "    - $file ($SIZE)"
done

echo ""
echo -e "${GREEN}Next Steps:${NC}"
echo ""
echo "1. Review individual results:"
echo "   head -20 $TEST_NAME/test_1_results.txt"
echo ""
echo "2. Compare all results:"
echo "   for f in $TEST_NAME/test_*_results.txt; do"
echo "     echo \"=== \$f ===\""
echo "     head -3 \"\$f\""
echo "   done"
echo ""
echo "3. View baseline plot:"
echo "   display $TEST_NAME/baseline_latency_plot.png"
echo ""
echo "4. Create detailed comparison report:"
echo "   cat > compare_tests.sh << 'EOF'"
echo "   #!/bin/bash"
echo "   for f in $TEST_NAME/test_*_results.txt; do"
echo "     echo \"Test: \$f\""
echo "     grep -E 'Max|Avg' \"\$f\" | head -5"
echo "     echo \"\""
echo "   done"
echo "   EOF"
echo "   chmod +x compare_tests.sh"
echo "   ./compare_tests.sh"
echo ""

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Batch processing complete${NC}"
echo -e "${GREEN}========================================${NC}"
