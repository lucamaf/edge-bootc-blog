#!/bin/bash

################################################################################
# Cyclictest Results Analysis and Plotting Script for RHEL
#
# This script processes cyclictest histogram data and generates a visualization
# using gnuplot showing latency distribution across CPU cores.
#
# Based on: https://www.osadl.org/uploads/media/mklatencyplot.bash
# Adapted for RHEL 9 Real-Time
#
# Usage: ./analyze-results.sh [histogram_file] [num_cores] [max_latency]
#   histogram_file: Input histogram file (default: cyclictest_histogram.txt)
#   num_cores: Number of cores (default: auto-detect or nproc)
#   max_latency: Max latency for X-axis in us (default: auto-detect)
#
################################################################################

set -e

# Configuration
HISTOGRAM_FILE="${1:-cyclictest_histogram.txt}"
NUM_CORES="${2:-}"
MAX_LATENCY="${3:-}"

# Output files
PLOTCMD_FILE="latency_plot.gnuplot"
PLOT_IMAGE="latency_plot.png"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cyclictest Results Analysis${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Check if input file exists
if [ ! -f "$HISTOGRAM_FILE" ]; then
    echo -e "${RED}Error: Histogram file '$HISTOGRAM_FILE' not found${NC}"
    echo ""
    echo "Expected files from run-cyclictest.sh:"
    echo "  - cyclictest_histogram.txt"
    echo ""
    echo "Run cyclictest first:"
    echo "  ./run-cyclictest.sh [duration] [interval]"
    exit 1
fi

# Check if histogram file is empty
if [ ! -s "$HISTOGRAM_FILE" ]; then
    echo -e "${RED}Error: Histogram file '$HISTOGRAM_FILE' is empty${NC}"
    exit 1
fi

echo "Input Configuration:"
echo "  Histogram file: $HISTOGRAM_FILE"
echo "  File size: $(wc -l < "$HISTOGRAM_FILE") lines"
echo ""

# Auto-detect number of cores if not provided
if [ -z "$NUM_CORES" ]; then
    # Try to detect from histogram file (number of columns - 1)
    COLUMNS=$(head -1 "$HISTOGRAM_FILE" | awk '{print NF}')
    if [ "$COLUMNS" -gt 1 ]; then
        NUM_CORES=$((COLUMNS - 1))
    else
        NUM_CORES=$(nproc)
    fi
fi

echo "Analysis Parameters:"
echo "  Number of cores: $NUM_CORES"

# Auto-detect maximum latency if not provided
if [ -z "$MAX_LATENCY" ]; then
    # Extract from results file if available
    if [ -f "cyclictest_results.txt" ]; then
        MAX_LATENCY=$(grep "Max Latencies" cyclictest_results.txt | tr " " "\n" | grep -E '^0*[0-9]+$' | sort -n | tail -1)
    fi

    # If still not found, calculate from histogram
    if [ -z "$MAX_LATENCY" ]; then
        MAX_LATENCY=$(awk '{print $1}' "$HISTOGRAM_FILE" | sort -n | tail -1)
    fi
fi

# cyclictest zero-pads latency values (e.g. "000397"), and that also applies
# to a value passed explicitly as the 3rd argument. A leading zero makes
# both bash arithmetic and gnuplot try to parse the number as octal, which
# then fails as soon as an 8 or 9 shows up. Normalize to a clean base-10
# integer before it's used in any comparison or plot.
if [ -n "$MAX_LATENCY" ]; then
    MAX_LATENCY=$((10#$MAX_LATENCY))
fi

# Default to 400 if detection fails
if [ -z "$MAX_LATENCY" ] || [ "$MAX_LATENCY" -lt 50 ]; then
    MAX_LATENCY=400
fi

echo "  Maximum latency (X-axis): ${MAX_LATENCY}us"
echo ""

# Verify gnuplot is available
if ! command -v gnuplot &> /dev/null; then
    echo -e "${YELLOW}Warning: gnuplot not found. Plot will not be generated.${NC}"
    echo "To generate plots, install gnuplot:"
    echo "  sudo dnf install gnuplot"
    echo ""
    echo "Generated histogram data is available in: $HISTOGRAM_FILE"
    exit 0
fi

echo -e "${GREEN}Creating histogram columns...${NC}"

# Create individual histogram files for each core
# This splits the multi-column histogram into separate files for plotting
for i in $(seq 1 $NUM_CORES); do
    COLUMN=$((i + 1))
    HIST_FILE="histogram_core_$((i-1)).tmp"
    
    # Extract latency class (column 1) and core data (column N)
    cut -f1,"$COLUMN" "$HISTOGRAM_FILE" > "$HIST_FILE" 2>/dev/null || true
    
    if [ -s "$HIST_FILE" ]; then
        echo "  ✓ Created histogram for core $((i-1))"
    else
        echo "  ⚠ Warning: Could not create histogram for core $((i-1))"
    fi
done

echo ""
echo -e "${GREEN}Generating gnuplot commands...${NC}"

# Create gnuplot command file
cat > "$PLOTCMD_FILE" << 'GNUPLOT_EOF'
set title "Latency Distribution Across CPU Cores"
set terminal png size 1024,768
set xlabel "Latency (us)"
set ylabel "Number of Samples (log scale)"
set logscale y
set grid
set style data histeps
GNUPLOT_EOF

echo "set xrange [0:$MAX_LATENCY]" >> "$PLOTCMD_FILE"
echo "set yrange [0.8:*]" >> "$PLOTCMD_FILE"
echo "set output \"$PLOT_IMAGE\"" >> "$PLOTCMD_FILE"

# Build plot command with all cores
echo -n "plot " >> "$PLOTCMD_FILE"

for i in $(seq 1 $NUM_CORES); do
    HIST_FILE="histogram_core_$((i-1)).tmp"
    CPU_NO=$((i-1))
    
    if [ -s "$HIST_FILE" ]; then
        # Add comma before each line except the first
        if [ $i -ne 1 ]; then
            echo -n ", " >> "$PLOTCMD_FILE"
        fi
        
        # Format CPU label with proper spacing
        if [ $CPU_NO -lt 10 ]; then
            LABEL="CPU$CPU_NO "
        else
            LABEL="CPU$CPU_NO"
        fi
        
        echo -n "\"$HIST_FILE\" using 1:2 title \"$LABEL\" with histeps" >> "$PLOTCMD_FILE"
    fi
done

echo "" >> "$PLOTCMD_FILE"

echo "  ✓ Generated gnuplot commands"
echo ""

# Execute gnuplot
echo -e "${GREEN}Generating plot...${NC}"

if gnuplot < "$PLOTCMD_FILE"; then
    echo "  ✓ Plot generated successfully"
    echo ""
    echo -e "${GREEN}Output file: ${PLOT_IMAGE}${NC}"
    echo "  File size: $(ls -lh "$PLOT_IMAGE" | awk '{print $5}')"
else
    echo -e "${RED}✗ Error: gnuplot failed to generate plot${NC}"
    echo "Check $PLOTCMD_FILE for details"
    exit 1
fi

# Clean up temporary files
echo ""
echo -e "${GREEN}Cleaning up temporary files...${NC}"
for i in $(seq 1 $NUM_CORES); do
    HIST_FILE="histogram_core_$((i-1)).tmp"
    rm -f "$HIST_FILE"
done
echo "  ✓ Temporary files removed"

echo ""
echo -e "${GREEN}Analysis Results Summary:${NC}"
echo "  Input file: $HISTOGRAM_FILE"
echo "  Number of cores analyzed: $NUM_CORES"
echo "  Latency range: 0-${MAX_LATENCY}us"
echo ""

# Display some statistics
if [ -f "cyclictest_results.txt" ]; then
    echo "Statistics from cyclictest_results.txt:"
    grep -E "Max Latencies|Avg Latencies|Std Dev" cyclictest_results.txt | head -5 || true
    echo ""
fi

# Show plot interpretation guide
echo -e "${GREEN}Plot Interpretation:${NC}"
echo "  X-axis: Latency in microseconds (us)"
echo "  Y-axis: Number of samples (logarithmic scale)"
echo "  Each color: One CPU core"
echo ""
echo "  ✓ Good: Sharp peak at low latency, narrow distribution"
echo "  ✗ Poor: Broad distribution, long tail extending to high latencies"
echo ""

echo -e "${GREEN}Next Steps:${NC}"
echo "  1. View the generated plot:"
echo "     display $PLOT_IMAGE  # Or use your image viewer"
echo ""
echo "  2. Compare multiple runs:"
echo "     cp $PLOT_IMAGE run1_latency.png"
echo "     ./run-cyclictest.sh"
echo "     ./analyze-results.sh"
echo "     # Compare run1_latency.png with latency_plot.png"
echo ""
echo "  3. Analyze raw data:"
echo "     head -20 $HISTOGRAM_FILE"
echo ""

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Analysis complete${NC}"
echo -e "${GREEN}========================================${NC}"
