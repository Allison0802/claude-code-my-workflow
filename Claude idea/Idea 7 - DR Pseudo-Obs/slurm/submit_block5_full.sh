#!/usr/bin/env bash
# ============================================================================
# Submit Block 5 full: MCAR vs MAR comparison
# Array job: 2 patterns x 3 rates = 6 scenarios
# Usage: sbatch slurm/submit_block5_full.sh
# Last Updated: 2026-03-22
# ============================================================================

#SBATCH --job-name=drpo_b5
#SBATCH --output=logs/block5_%a.out
#SBATCH --error=logs/block5_%a.err
#SBATCH --time=12:00:00
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=32G
#SBATCH --partition=general
#SBATCH --array=1-6
#SBATCH --mail-type=FAIL
#SBATCH --mail-user=yumeiy@ad.unc.edu

set -e

# ---------------------------------------------------------------------------
# Environment
# ---------------------------------------------------------------------------
PROJECT_DIR="${PROJECT_DIR:-$HOME/Research/Idea7_DR_PseudoObs}"
cd "${PROJECT_DIR}"
mkdir -p logs results

echo "=============================="
echo "Block 5 Full -- MCAR vs MAR"
echo "Array Task ID: ${SLURM_ARRAY_TASK_ID}"
echo "=============================="

# Load R
module load r/4.4.0
echo "R version: $(R --version | head -1)"

# ---------------------------------------------------------------------------
# Map array task ID to pattern + rate
# ---------------------------------------------------------------------------
declare -A PATTERN_MAP
declare -A PCT_MAP

PATTERN_MAP[1]="MCAR";  PCT_MAP[1]=20
PATTERN_MAP[2]="MCAR";  PCT_MAP[2]=30
PATTERN_MAP[3]="MCAR";  PCT_MAP[3]=50
PATTERN_MAP[4]="MAR";   PCT_MAP[4]=20
PATTERN_MAP[5]="MAR";   PCT_MAP[5]=30
PATTERN_MAP[6]="MAR";   PCT_MAP[6]=50

MISS_PATTERN="${PATTERN_MAP[${SLURM_ARRAY_TASK_ID}]}"
MISS_PCT="${PCT_MAP[${SLURM_ARRAY_TASK_ID}]}"

if [ -z "$MISS_PATTERN" ] || [ -z "$MISS_PCT" ]; then
  echo "ERROR: Invalid SLURM_ARRAY_TASK_ID=${SLURM_ARRAY_TASK_ID}"
  exit 1
fi

N_REPS=500
RESULTS_DIR=results

echo "MISS_PATTERN: ${MISS_PATTERN}"
echo "MISS_PCT: ${MISS_PCT}"
echo "N_REPS: ${N_REPS}"
echo "RESULTS_DIR: ${RESULTS_DIR}"
echo "=============================="

Rscript R/block5_mcar_mar.R "${N_REPS}" "${MISS_PATTERN}" "${MISS_PCT}" "${RESULTS_DIR}"

echo "Block 5 (${MISS_PATTERN}_${MISS_PCT}%) completed successfully."
