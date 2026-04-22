# runner_dispatch.R — pick runner by cfg$compute$<tier>$backend.

run_tier <- function(tier, variants, cfg, state = NULL) {
  backend <- cfg$compute[[tier]]$backend
  if (is.null(backend))
    me_stop("compute.%s.backend missing in config", tier)
  switch(backend,
    local  = run_tier_local(tier, variants, cfg, state),
    slurm  = run_tier_slurm(variants, cfg, state, tier = tier),
    custom = run_tier_custom(variants, cfg, state, tier = tier),
    me_stop("unknown backend: %s", backend)
  )
}

#' Dispatch to the local runner for the given tier.
#' For screen tier: calls run_screen_local with n_workers from cfg.
#' For full tier: calls run_screen_local sequentially (n_workers = 1) since
#' full-tier local runs are typically heavier; user can override via n_workers.
run_tier_local <- function(tier, variants, cfg, state = NULL) {
  n_workers <- cfg$compute[[tier]]$n_workers %||% 1L
  run_screen_local(variants, n_workers = n_workers)
}
