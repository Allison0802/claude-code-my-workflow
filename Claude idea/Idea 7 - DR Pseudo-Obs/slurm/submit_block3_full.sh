#!/usr/bin/env bash
# ============================================================================
# Submit Block 3 full: Bias demonstration under missingness
# Array job: one task per missingness rate (10%, 20%, 30%, 50%)
# Usage: sbatch slurm/submit_block3_full.sh
# Last Updated: 2026-03-22
# ============================================================================

#SBATCH --job-name=drpo_b3
#SBATCH --output=logs/block3_%a.out
#SBATCH --error=logs/block3_%a.err
#SBATCH --time=12:00:00
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=32G
#SBATCH --partition=general
#SBATCH --array=1-4
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
echo "Block 3 Full -- Bias Demo"
echo "Array Task ID: ${SLURM_ARRAY_TASK_ID}"
echo "=============================="

# Load R
module load r/4.4.0
echo "R version: $(R --version | head -1)"

# ---------------------------------------------------------------------------
# Map array task ID to missingness percentage
# ---------------------------------------------------------------------------
declare -A PCT_MAP
PCT_MAP[1]=10
PCT_MAP[2]=20
PCT_MAP[3]=30
PCT_MAP[4]=50

MISS_PCT="${PCT_MAP[${SLURM_ARRAY_TASK_ID}]}"

if [ -z "$MISS_PCT" ]; then
  echo "ERROR: Invalid SLURM_ARRAY_TASK_ID=${SLURM_ARRAY_TASK_ID}"
  exit 1
fi

N_REPS=500
RESULTS_DIR=results

echo "MISS_PCT: ${MISS_PCT}"
echo "N_REPS: ${N_REPS}"
echo "RESULTS_DIR: ${RESULTS_DIR}"
echo "=============================="

Rscript R/block3_bias_demo.R "${N_REPS}" "${MISS_PCT}" "${RESULTS_DIR}"

echo "Block 3 (miss_pct=${MISS_PCT}%) completed successfully."
