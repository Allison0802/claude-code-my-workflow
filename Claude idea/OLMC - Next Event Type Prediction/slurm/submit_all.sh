#!/bin/bash
# =============================================================================
# submit_all.sh
# Master submission script for OLMC experiment suite
#
# Run order (from EXPERIMENT_PLAN.md):
#   1. Block 1 pilot (200 reps) -> verify implementation
#   2. Block 2 pilot (200 reps) -> verify DR mechanism
#   3. Block 3 + Block 4 (1000 reps, parallel) -> key novelty claims
#   4. Block 1 full + Block 2 full (1000 reps, parallel) -> after pilots pass
#   5. Block 5 (1000 reps) -> stability threshold
#   6. Block 6 (500 reps, optional) -> flexible nuisance
#
# Usage: bash submit_all.sh [step]
#   step 1: Block 1 pilot only
#   step 2: Block 2 pilot only
#   step 3: Blocks 3 + 4 full (parallel)
#   step 4: Blocks 1 + 2 full (parallel)
#   step 5: Block 5 full
#   step all: Submit everything (NOT recommended; run sequentially with checks)
# =============================================================================

set -e

SLURM_DIR="$(cd "$(dirname "$0")" && pwd)"
STEP="${1:-help}"

case "$STEP" in
  1)
    echo "=== Step 1: Block 1 Pilot (200 reps) ==="
    bash "$SLURM_DIR/submit_block1_pilot.sh"
    echo ""
    echo "After completion, run: Rscript R/collect_block1.R"
    echo "If PASS, proceed to step 2."
    ;;
  2)
    echo "=== Step 2: Block 2 Pilot (200 reps) ==="
    bash "$SLURM_DIR/submit_block2_pilot.sh"
    echo ""
    echo "After completion, run: Rscript R/collect_block2.R"
    echo "If PASS, proceed to step 3."
    ;;
  3)
    echo "=== Step 3: Blocks 3 + 4 Full (1000 reps each, parallel) ==="
    bash "$SLURM_DIR/submit_block3_full.sh"
    bash "$SLURM_DIR/submit_block4_full.sh"
    echo ""
    echo "After completion, run:"
    echo "  Rscript R/collect_block3.R"
    echo "  Rscript R/collect_block4.R"
    ;;
  4)
    echo "=== Step 4: Blocks 1 + 2 Full (1000 reps each) ==="
    echo "TODO: Create submit_block1_full.sh and submit_block2_full.sh"
    echo "(Same as pilots but with N_REPS=1000 and N_TASKS=20)"
    ;;
  5)
    echo "=== Step 5: Block 5 Full (1000 reps) ==="
    bash "$SLURM_DIR/submit_block5_full.sh"
    echo ""
    echo "After completion, run: Rscript R/collect_block5.R"
    ;;
  help|*)
    echo "Usage: bash submit_all.sh [step]"
    echo ""
    echo "Steps:"
    echo "  1  Block 1 pilot (200 reps) -- run first"
    echo "  2  Block 2 pilot (200 reps) -- run after Block 1 passes"
    echo "  3  Blocks 3+4 full (1000 reps) -- parallel, after Block 2 passes"
    echo "  4  Blocks 1+2 full (1000 reps) -- after pilots pass"
    echo "  5  Block 5 full (1000 reps) -- after Blocks 1-4 pass"
    echo ""
    echo "Run sequentially with gate checks between steps."
    ;;
esac
