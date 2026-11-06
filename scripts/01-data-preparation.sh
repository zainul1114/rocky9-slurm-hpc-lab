#!/bin/bash
set -e

WORKDIR=/home/hpcuser/slurm-dependency-lab
cd "$WORKDIR"

echo "Stage A: Data preparation"
echo "Node: $(hostname)"
echo "Start: $(date)"

mkdir -p output
printf "101\n102\n103\n104\n105\n" > output/input.txt

echo "Prepared input:"
cat output/input.txt

sleep 15

echo "Stage A completed: $(date)"
