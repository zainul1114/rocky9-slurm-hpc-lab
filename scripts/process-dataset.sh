#!/bin/bash
set -euo pipefail

TASK_ID=${SLURM_ARRAY_TASK_ID}

WORKDIR=/home/hpcuser/slurm-dependency-lab
OUTPUT_DIR="${WORKDIR}/output"

mkdir -p "${OUTPUT_DIR}"

echo "=================================="
echo "Slurm Array Job"
echo "Array Job ID : ${SLURM_ARRAY_JOB_ID}"
echo "Task ID      : ${TASK_ID}"
echo "Job ID       : ${SLURM_JOB_ID}"
echo "Node         : $(hostname)"
echo "Start        : $(date)"
echo "=================================="

# Generate five numbers for this task
BASE=$((TASK_ID * 100))

INPUT_FILE="${OUTPUT_DIR}/dataset_${TASK_ID}.txt"
RESULT_FILE="${OUTPUT_DIR}/result_${TASK_ID}.txt"

for i in {1..5}; do
    echo $((BASE + i)) >> "${INPUT_FILE}"
done

# Calculate count, sum and average
awk '
{
    sum += $1
    count++
}
END {
    printf "Count=%d\nSum=%d\nAverage=%.2f\n", count, sum, sum/count
}' "${INPUT_FILE}" > "${RESULT_FILE}"

echo "Input file: ${INPUT_FILE}"
cat "${RESULT_FILE}"

echo "Task ${TASK_ID} completed at $(date)"
