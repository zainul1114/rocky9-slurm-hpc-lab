#!/bin/bash
set -e

WORKDIR=/home/hpcuser/slurm-dependency-lab
cd "$WORKDIR"

echo "Stage B: Data processing"
echo "Node: $(hostname)"
echo "Start: $(date)"

if [ ! -f output/input.txt ]; then
    echo "ERROR: Input file not found"
    exit 1
fi

awk '{sum += $1; count++} END {
    printf "Count=%d\nSum=%d\nAverage=%.2f\n", count, sum, sum/count
}' output/input.txt > output/processed.txt

cat output/processed.txt

sleep 15

echo "Stage B completed: $(date)"
