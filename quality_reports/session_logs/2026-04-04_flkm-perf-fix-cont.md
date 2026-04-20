# Session Log: 2026-04-04 — FL-KM Validation Performance Fix (continued)

## Context
Continuation of 2026-04-03 fix. Re-submitted cluster jobs still running after 13 hours
because the bind_rows fix only removed extra O(n²) overhead; the inherent jackknife O(n²)
remains. N=500 × 20 seeds × 5 chunks ≈ 65h total — exceeds 48h SLURM wall time.

## Changes

- [Missing Types/submit_flkm_warning_validation_first_pass.sh] Reduced N_SUBJECTS 500→150,
  N_SIMS 20→8, cpus-per-task 4→8→20, mem 64G→128G. CHUNK_SIZE auto-derives from
  SLURM_CPUS_PER_TASK (fallback updated to 20). Added FLKM_MC_CORES=1 export with doc
  comment. With N_SIMS=8 and CHUNK_SIZE=20, all 8 seeds run in one chunk (~1.5h total);
  bumping N_SIMS to 20 would use all 20 CPUs in one chunk.

- [Missing Types/functions.R] Added `mc_cores` parameter to `generate_flkm_pseudoEst()`
  (reads env var FLKM_MC_CORES, default 1). Replaced both inner `for (i in seq_len(n_tp))`
  loops (none-branch and validation-branch) with lapply/mclapply dispatch. When mc_cores=1
  (default) uses plain lapply — safe inside PSOCK workers. When mc_cores>1 uses
  parallel::mclapply — only valid with CHUNK_SIZE=1 to avoid CPU oversubscription.
  Added runtime documentation comment block above function.

- [Missing Types/CLAUDE.md] Added "FL-KM Runtime: O(n²) Warning" section with observed
  wall times (N=20/150/500), parallelism rules table, and note that N=500 main simulation
  runs will approach the 48h wall time limit.

## Action Required on Cluster
```bash
scancel -u yumeiy
# Sync functions.R and submit_flkm_warning_validation_first_pass.sh to cluster
sbatch submit_flkm_warning_validation_first_pass.sh
```

## Future Simulations (N=500, 500 reps)
Each seed takes ~13h with 1 core. With CHUNK_SIZE=32, 32 seeds run simultaneously → each
chunk takes ~13h. 500/32 ≈ 16 chunks × 13h = 208h >> 48h limit. Checkpointing via
SAVE_INTERVAL must be relied upon; consider N=300 for interim analyses ((300/500)²≈36%
of cost → ~4.7h/chunk → 500/32 × 4.7 ≈ 73h still > 48h). **This needs a separate plan.**
