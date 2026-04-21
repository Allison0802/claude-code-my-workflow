#!/bin/bash
# =============================================================================
# submit_block5_full.sh
# Block 5: Rare-Event Stability / Reporting Threshold (1000 reps)
#
# 4 w values, each with 3 estimator variants, 1000 reps split into 20 tasks
#
# Submit: bash submit_block5_full.sh
# =============================================================================

set -e

PROJECT_DIR="$HOME/Research/Claude idea"
SCRIPT="$PROJECT_DIR/R/block5_rare_event.R"
RESULTS_DIR="$PROJECT_DIR/results/block5"
LOGS_DIR="$PROJECT_DIR/slurm/logs_block5"

mkdir -p "$RESULTS_DIR" "$LOGS_DIR"

echo "======================================================="
echo "OLMC Block 5 Full Submission"
echo "Date: $(date)"
echo "======================================================="

W_VALUES=("0.08" "0.17" "0.25" "0.50")
REPS_PER_TASK=50
N_TASKS=20

for W_VAL in "${W_VALUES[@]}"; do

  JOB_NAME="block5_w${W_VAL}"

  sbatch <<SBATCH_SCRIPT
#!/bin/bash
#SBATCH --job-name=${JOB_NAME}
#SBATCH --output=${LOGS_DIR}/${JOB_NAME}_%A_%a.out
#SBATCH --error=${LOGS_DIR}/${JOB_NAME}_%A_%a.err
#SBATCH --array=1-${N_TASKS}
#SBATCH --time=6:00:00
#SBATCH --mem=12G
#SBATCH --cpus-per-task=1
#SBATCH --mail-type=FAIL
#SBATCH --mail-user=yumeiy@ad.unc.edu

module load gcc 2>/dev/null
export LD_LIBRARY_PATH="/nas/longleaf/rhel8/apps/r/4.4.0/lib64/R/lib:\$LD_LIBRARY_PATH"
module load gdal 2>/dev/null
module load r/4.4.0

REP_START=\$(( (SLURM_ARRAY_TASK_ID - 1) * ${REPS_PER_TASK} + 1 ))

echo "Block 5 | w=${W_VAL} | reps \${REP_START}-\$(( REP_START + ${REPS_PER_TASK} - 1 ))"
echo "Start: \$(date)"

export BLOCK5_REP_START=\${REP_START}
export BLOCK5_N_REPS=${REPS_PER_TASK}
export BLOCK5_W="${W_VAL}"

Rscript "${SCRIPT}"

echo "End: \$(date)"
SBATCH_SCRIPT

  echo "Submitted: w=${W_VAL} (${N_TASKS} tasks x ${REPS_PER_TASK} reps)"
done

echo ""
echo "All Block 5 jobs submitted."
echo "To collect: Rscript ${PROJECT_DIR}/R/collect_block5.R"
