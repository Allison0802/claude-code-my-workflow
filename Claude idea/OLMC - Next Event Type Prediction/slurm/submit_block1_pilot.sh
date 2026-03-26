#!/bin/bash
# =============================================================================
# submit_block1_pilot.sh
# Block 1 Pilot: EIF / Oracle Sanity Check
#
# Run 200 reps x {n=500, n=1000, n=2000} x 4 estimators
# Parallelized as 3 arrays (one per n), 4 tasks per array (one per estimator)
# Each task runs 200/4 = 50 reps
#
# Submit: bash submit_block1_pilot.sh
# Monitor: squeue -u $USER
# Collect: Rscript collect_block1.R
# =============================================================================

set -e

PROJECT_DIR="$HOME/Research/Claude idea"
SCRIPT="$PROJECT_DIR/R/block1_sanity.R"
RESULTS_DIR="$PROJECT_DIR/results/block1"
LOGS_DIR="$PROJECT_DIR/slurm/logs_block1"

mkdir -p "$RESULTS_DIR" "$LOGS_DIR"

echo "======================================================="
echo "OLMC Block 1 Pilot Submission"
echo "Project: $PROJECT_DIR"
echo "Date: $(date)"
echo "======================================================="

# Estimators (array task index 1-4)
ESTIMATORS=("DR-oracle" "DR-correct" "OR-only" "IPCW-only")

# N values to run
N_VALUES=(500 1000 2000)

# Reps per task: 200 total, split into 4 chunks of 50
REPS_PER_TASK=50
N_TASKS=4   # one per estimator

for N_VAL in "${N_VALUES[@]}"; do

  JOB_NAME="block1_n${N_VAL}"

  # Write per-array-task script inline and submit
  sbatch <<SBATCH_SCRIPT
#!/bin/bash
#SBATCH --job-name=${JOB_NAME}
#SBATCH --output=${LOGS_DIR}/${JOB_NAME}_%A_%a.out
#SBATCH --error=${LOGS_DIR}/${JOB_NAME}_%A_%a.err
#SBATCH --array=1-${N_TASKS}
#SBATCH --time=4:00:00
#SBATCH --mem=8G
#SBATCH --cpus-per-task=1
#SBATCH --mail-type=FAIL
#SBATCH --mail-user=yumeiy@ad.unc.edu

# ---- Environment ----
module load gcc 2>/dev/null
export LD_LIBRARY_PATH="/nas/longleaf/rhel8/apps/r/4.4.0/lib64/R/lib:\$LD_LIBRARY_PATH"
module load r/4.4.0

# ---- Identify estimator from array task ID ----
ESTIMATORS=("DR-oracle" "DR-correct" "OR-only" "IPCW-only")
EST_IDX=\$(( SLURM_ARRAY_TASK_ID - 1 ))
ESTIMATOR=\${ESTIMATORS[\$EST_IDX]}

# Rep range for this task: each task runs REPS_PER_TASK reps
REP_START=\$(( (SLURM_ARRAY_TASK_ID - 1) * ${REPS_PER_TASK} + 1 ))

echo "Block 1 Pilot | n=${N_VAL} | estimator=\${ESTIMATOR} | reps \${REP_START}-\$(( REP_START + ${REPS_PER_TASK} - 1 ))"
echo "Job: \$SLURM_JOB_ID | Array task: \$SLURM_ARRAY_TASK_ID | Node: \$SLURMD_NODENAME"
echo "Start: \$(date)"

export BLOCK1_N=${N_VAL}
export BLOCK1_REP_START=\${REP_START}
export BLOCK1_N_REPS=${REPS_PER_TASK}
export BLOCK1_ESTIMATOR=\${ESTIMATOR}

Rscript "${SCRIPT}"

echo "End: \$(date)"
SBATCH_SCRIPT

  echo "Submitted array job for n=${N_VAL} (${N_TASKS} tasks x ${REPS_PER_TASK} reps)"
done

echo ""
echo "All Block 1 pilot jobs submitted."
echo "Expected output: ${RESULTS_DIR}/block1_n{500,1000,2000}_reps*.csv"
echo ""
echo "To collect and summarize results after completion:"
echo "  Rscript ${PROJECT_DIR}/R/collect_block1.R"
