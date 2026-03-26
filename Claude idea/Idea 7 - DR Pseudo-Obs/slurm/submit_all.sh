#!/usr/bin/env bash
# ============================================================================
# Master orchestrator: submit DR pseudo-observation experiment blocks
# Usage:
#   bash slurm/submit_all.sh 1        # Submit Block 1 only
#   bash slurm/submit_all.sh 2        # Submit Block 2 only
#   bash slurm/submit_all.sh all      # Submit Blocks 1-2 (pilot), then 3-5 (full)
# Last Updated: 2026-03-22
# ============================================================================

set -e

PROJECT_DIR="${PROJECT_DIR:-$HOME/Research/Idea7_DR_PseudoObs}"
SLURM_DIR="${PROJECT_DIR}/slurm"
cd "${PROJECT_DIR}"
mkdir -p logs results

BLOCK="${1:-}"

if [ -z "$BLOCK" ]; then
  echo "Usage: bash slurm/submit_all.sh <block|all>"
  echo ""
  echo "  1    Block 1 pilot (IF sanity, 200 reps, 4 sample sizes)"
  echo "  2    Block 2 pilot (DR matrix, 200 reps, 6 estimators)"
  echo "  3    Block 3 full  (bias demo, 500 reps, 4 miss rates)"
  echo "  4    Block 4 full  (cross-fit, 500 reps, single job)"
  echo "  5    Block 5 full  (MCAR vs MAR, 500 reps, 6 scenarios)"
  echo "  all  Submit all blocks with dependencies"
  echo ""
  exit 1
fi

submit_block() {
  local block_num="$1"
  local dep_flag="${2:-}"

  case "$block_num" in
    1)
      echo "Submitting Block 1 pilot..."
      if [ -n "$dep_flag" ]; then
        JOB_ID=$(sbatch ${dep_flag} "${SLURM_DIR}/submit_block1_pilot.sh" | awk '{print $NF}')
      else
        JOB_ID=$(sbatch "${SLURM_DIR}/submit_block1_pilot.sh" | awk '{print $NF}')
      fi
      echo "  Block 1 submitted: job ${JOB_ID}"
      ;;
    2)
      echo "Submitting Block 2 pilot..."
      if [ -n "$dep_flag" ]; then
        JOB_ID=$(sbatch ${dep_flag} "${SLURM_DIR}/submit_block2_pilot.sh" | awk '{print $NF}')
      else
        JOB_ID=$(sbatch "${SLURM_DIR}/submit_block2_pilot.sh" | awk '{print $NF}')
      fi
      echo "  Block 2 submitted: job ${JOB_ID}"
      ;;
    3)
      echo "Submitting Block 3 full..."
      if [ -n "$dep_flag" ]; then
        JOB_ID=$(sbatch ${dep_flag} "${SLURM_DIR}/submit_block3_full.sh" | awk '{print $NF}')
      else
        JOB_ID=$(sbatch "${SLURM_DIR}/submit_block3_full.sh" | awk '{print $NF}')
      fi
      echo "  Block 3 submitted: job ${JOB_ID}"
      ;;
    4)
      echo "Submitting Block 4 full..."
      if [ -n "$dep_flag" ]; then
        JOB_ID=$(sbatch ${dep_flag} "${SLURM_DIR}/submit_block4_full.sh" | awk '{print $NF}')
      else
        JOB_ID=$(sbatch "${SLURM_DIR}/submit_block4_full.sh" | awk '{print $NF}')
      fi
      echo "  Block 4 submitted: job ${JOB_ID}"
      ;;
    5)
      echo "Submitting Block 5 full..."
      if [ -n "$dep_flag" ]; then
        JOB_ID=$(sbatch ${dep_flag} "${SLURM_DIR}/submit_block5_full.sh" | awk '{print $NF}')
      else
        JOB_ID=$(sbatch "${SLURM_DIR}/submit_block5_full.sh" | awk '{print $NF}')
      fi
      echo "  Block 5 submitted: job ${JOB_ID}"
      ;;
    *)
      echo "ERROR: Unknown block '${block_num}'"
      exit 1
      ;;
  esac
}

if [ "$BLOCK" == "all" ]; then
  echo "============================================"
  echo "Submitting all blocks with dependencies"
  echo "============================================"
  echo ""

  # Pilot blocks (no dependencies)
  submit_block 1
  JOB1="$JOB_ID"

  submit_block 2 "--dependency=afterok:${JOB1}"
  JOB2="$JOB_ID"

  # Full blocks depend on both pilots completing
  PILOT_DEP="--dependency=afterok:${JOB1}:${JOB2}"

  submit_block 3 "${PILOT_DEP}"
  submit_block 4 "${PILOT_DEP}"
  submit_block 5 "${PILOT_DEP}"

  echo ""
  echo "============================================"
  echo "All blocks submitted."
  echo "Pilot blocks: ${JOB1}, ${JOB2}"
  echo "Full blocks depend on pilot completion."
  echo "Monitor with: squeue -u \$USER"
  echo "============================================"
else
  submit_block "$BLOCK"
fi
