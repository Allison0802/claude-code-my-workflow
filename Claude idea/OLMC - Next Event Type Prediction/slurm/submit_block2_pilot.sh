#!/bin/bash
# =============================================================================
# submit_block2_pilot.sh
# Block 2 Pilot: Double-Robustness Matrix
#
# Run 200 reps x 6 conditions (DR-both-correct, DR-G-wrong, DR-OR-wrong,
# DR-both-wrong, OR-only, IPCW-only) at n=1500
# Each condition gets 200 reps split into 4 tasks of 50
#
# Submit: bash submit_block2_pilot.sh
# Monitor: squeue -u $USER
# Collect: Rscript collect_block2.R
# =============================================================================

set -e

PROJECT_DIR="$HOME/Research/Claude idea"
SCRIPT="$PROJECT_DIR/R/block2_dr_matrix.R"
RESULTS_DIR="$PROJECT_DIR/results/block2"
LOGS_DIR="$PROJECT_DIR/slurm/logs_block2"

mkdir -p "$RESULTS_DIR" "$LOGS_DIR"

echo "======================================================="
echo "OLMC Block 2 Pilot Submission"
echo "Project: $PROJECT_DIR"
echo "Date: $(date)"
echo "======================================================="

CONDITIONS=("DR-both-correct" "DR-G-wrong" "DR-OR-wrong" "DR-both-wrong" "OR-only" "IPCW-only")
REPS_PER_TASK=50
N_TASKS=4

for COND in "${CONDITIONS[@]}"; do

  JOB_NAME="block2_${COND}"

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

# ---- Environment ----
module load gcc 2>/dev/null
export LD_LIBRARY_PATH="/nas/longleaf/rhel8/apps/r/4.4.0/lib64/R/lib:\$LD_LIBRARY_PATH"
module load gdal 2>/dev/null
module load r/4.4.0

REP_START=\$(( (SLURM_ARRAY_TASK_ID - 1) * ${REPS_PER_TASK} + 1 ))

echo "Block 2 | condition=${COND} | reps \${REP_START}-\$(( REP_START + ${REPS_PER_TASK} - 1 ))"
echo "Job: \$SLURM_JOB_ID | Array task: \$SLURM_ARRAY_TASK_ID | Node: \$SLURMD_NODENAME"
echo "Start: \$(date)"

export BLOCK2_REP_START=\${REP_START}
export BLOCK2_N_REPS=${REPS_PER_TASK}
export BLOCK2_CONDITION="${COND}"

Rscript "${SCRIPT}"

echo "End: \$(date)"
SBATCH_SCRIPT

  echo "Submitted array job for condition=${COND} (${N_TASKS} tasks x ${REPS_PER_TASK} reps)"
done

echo ""
echo "All Block 2 pilot jobs submitted (6 conditions x 4 tasks = 24 jobs)."
echo "Expected output: ${RESULTS_DIR}/block2_cond*_reps*.csv"
echo ""
echo "To collect results: Rscript ${PROJECT_DIR}/R/collect_block2.R"
