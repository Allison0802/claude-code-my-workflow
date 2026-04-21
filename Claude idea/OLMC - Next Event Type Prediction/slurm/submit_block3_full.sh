#!/bin/bash
# =============================================================================
# submit_block3_full.sh
# Block 3: Naive Bias Demonstration (1000 reps)
#
# 5 estimators x 1000 reps, split into 20 tasks of 50 each
#
# Submit: bash submit_block3_full.sh
# =============================================================================

set -e

PROJECT_DIR="$HOME/Research/Claude idea"
SCRIPT="$PROJECT_DIR/R/block3_naive_bias.R"
RESULTS_DIR="$PROJECT_DIR/results/block3"
LOGS_DIR="$PROJECT_DIR/slurm/logs_block3"

mkdir -p "$RESULTS_DIR" "$LOGS_DIR"

echo "======================================================="
echo "OLMC Block 3 Full Submission"
echo "Date: $(date)"
echo "======================================================="

ESTIMATORS=("DR" "OR-only" "IPCW-only" "observed-case" "death-as-censoring")
REPS_PER_TASK=50
N_TASKS=20  # 1000 / 50

for EST in "${ESTIMATORS[@]}"; do

  JOB_NAME="block3_${EST}"

  sbatch <<SBATCH_SCRIPT
#!/bin/bash
#SBATCH --job-name=${JOB_NAME}
#SBATCH --output=${LOGS_DIR}/${JOB_NAME}_%A_%a.out
#SBATCH --error=${LOGS_DIR}/${JOB_NAME}_%A_%a.err
#SBATCH --array=1-${N_TASKS}
#SBATCH --time=4:00:00
#SBATCH --mem=10G
#SBATCH --cpus-per-task=1
#SBATCH --mail-type=FAIL
#SBATCH --mail-user=yumeiy@ad.unc.edu

module load gcc 2>/dev/null
export LD_LIBRARY_PATH="/nas/longleaf/rhel8/apps/r/4.4.0/lib64/R/lib:\$LD_LIBRARY_PATH"
module load gdal 2>/dev/null
module load r/4.4.0

REP_START=\$(( (SLURM_ARRAY_TASK_ID - 1) * ${REPS_PER_TASK} + 1 ))

echo "Block 3 | estimator=${EST} | reps \${REP_START}-\$(( REP_START + ${REPS_PER_TASK} - 1 ))"
echo "Start: \$(date)"

export BLOCK3_REP_START=\${REP_START}
export BLOCK3_N_REPS=${REPS_PER_TASK}
export BLOCK3_ESTIMATOR="${EST}"

Rscript "${SCRIPT}"

echo "End: \$(date)"
SBATCH_SCRIPT

  echo "Submitted: ${EST} (${N_TASKS} tasks x ${REPS_PER_TASK} reps)"
done

echo ""
echo "All Block 3 jobs submitted."
echo "To collect: Rscript ${PROJECT_DIR}/R/collect_block3.R"
