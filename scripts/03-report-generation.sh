#!/bin/bash
set -e

WORKDIR=/home/hpcuser/slurm-dependency-lab
cd "$WORKDIR"

echo "Stage C: Report generation"
echo "Node: $(hostname)"
echo "Start: $(date)"

if [ ! -f output/processed.txt ]; then
    echo "ERROR: Processed data not found"
    exit 1
fi

{
    echo "HPC Processing Report"
    echo "Generated: $(date)"
    echo "Compute node: $(hostname)"
    echo
    cat output/processed.txt
} > output/final-report.txt

cat output/final-report.txt

echo "Stage C completed: $(date)"
