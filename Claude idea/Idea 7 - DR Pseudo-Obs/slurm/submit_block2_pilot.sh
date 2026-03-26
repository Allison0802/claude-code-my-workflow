#!/usr/bin/env bash
# ============================================================================
# Submit Block 2 pilot: Double-robustness 2x2 matrix
# Array job: one task per estimator (6 estimators)
# Usage: sbatch slurm/submit_block2_pilot.sh
# Last Updated: 2026-03-22
# ============================================================================

#SBATCH --job-name=drpo_b2_pilot
#SBATCH --output=logs/block2_pilot_%a.out
#SBATCH --error=logs/block2_pilot_%a.err
#SBATCH --time=4:00:00
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=16G
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
echo "Block 2 Pilot -- DR Matrix"
echo "Array Task ID: ${SLURM_ARRAY_TASK_ID}"
echo "=============================="

# Load R
module load r/4.4.0
echo "R version: $(R --version | head -1)"

# ---------------------------------------------------------------------------
# Map array task ID to estimator
# ---------------------------------------------------------------------------
declare -A EST_MAP
EST_MAP[1]="both_correct"
EST_MAP[2]="prop_wrong"
EST_MAP[3]="out_wrong"
EST_MAP[4]="both_wrong"
EST_MAP[5]="ipw_only"
EST_MAP[6]="or_only"

ESTIMATOR="${EST_MAP[${SLURM_ARRAY_TASK_ID}]}"

if [ -z "$ESTIMATOR" ]; then
  echo "ERROR: Invalid SLURM_ARRAY_TASK_ID=${SLURM_ARRAY_TASK_ID}"
  exit 1
fi

N_REPS=200
RESULTS_DIR=results

echo "ESTIMATOR: ${ESTIMATOR}"
echo "N_REPS: ${N_REPS}"
echo "RESULTS_DIR: ${RESULTS_DIR}"
echo "=============================="

Rscript R/block2_dr_matrix.R "${N_REPS}" "${ESTIMATOR}" "${RESULTS_DIR}"

echo "Block 2 pilot (${ESTIMATOR}) completed successfully."
