#!/usr/bin/env bash
# ============================================================================
# Submit Block 1 pilot: IF variance sanity check
# Array job: one task per sample size (n = 200, 500, 1000, 2000)
# Usage: sbatch slurm/submit_block1_pilot.sh
# Last Updated: 2026-03-22
# ============================================================================

#SBATCH --job-name=drpo_b1_pilot
#SBATCH --output=logs/block1_pilot_%a.out
#SBATCH --error=logs/block1_pilot_%a.err
#SBATCH --time=4:00:00
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=16G
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
echo "Block 1 Pilot -- IF Sanity"
echo "Array Task ID: ${SLURM_ARRAY_TASK_ID}"
echo "=============================="

# Load R
module load gdal 2>/dev/null
module load r/4.4.0
echo "R version: $(R --version | head -1)"

# ---------------------------------------------------------------------------
# Map array task ID to sample size
# ---------------------------------------------------------------------------
declare -A SIZE_MAP
SIZE_MAP[1]=200
SIZE_MAP[2]=500
SIZE_MAP[3]=1000
SIZE_MAP[4]=2000

N_SIZE="${SIZE_MAP[${SLURM_ARRAY_TASK_ID}]}"

if [ -z "$N_SIZE" ]; then
  echo "ERROR: Invalid SLURM_ARRAY_TASK_ID=${SLURM_ARRAY_TASK_ID}"
  exit 1
fi

N_REPS=200
RESULTS_DIR=results

echo "N_SIZE: ${N_SIZE}"
echo "N_REPS: ${N_REPS}"
echo "RESULTS_DIR: ${RESULTS_DIR}"
echo "=============================="

Rscript R/block1_if_sanity.R "${N_REPS}" "${N_SIZE}" "${RESULTS_DIR}"

echo "Block 1 pilot (n=${N_SIZE}) completed successfully."
