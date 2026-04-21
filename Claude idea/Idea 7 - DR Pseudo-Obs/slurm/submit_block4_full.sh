#!/usr/bin/env bash
# ============================================================================
# Submit Block 4 full: Cross-fit RF vs parametric DR comparison
# Single run (all 4 estimators compared internally)
# Usage: sbatch slurm/submit_block4_full.sh
# Last Updated: 2026-03-22
# ============================================================================

#SBATCH --job-name=drpo_b4
#SBATCH --output=logs/block4_%j.out
#SBATCH --error=logs/block4_%j.err
#SBATCH --time=12:00:00
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=32G
#SBATCH --partition=general
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
echo "Block 4 Full -- Cross-fit RF"
echo "=============================="

# Load R
module load gdal 2>/dev/null
module load r/4.4.0
echo "R version: $(R --version | head -1)"

N_REPS=500
RESULTS_DIR=results

echo "N_REPS: ${N_REPS}"
echo "RESULTS_DIR: ${RESULTS_DIR}"
echo "=============================="

Rscript R/block4_crossfit.R "${N_REPS}" "${RESULTS_DIR}"

echo "Block 4 completed successfully."
