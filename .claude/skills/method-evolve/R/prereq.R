# Phase -1: prerequisites. Owns the IBS patch and (T2) baseline meta sidecars.

IBS_PATCH_VERSION <- 1L
IBS_STAMP_RE <- "# ibs-patch-version:\\s*([0-9]+)"

has_ibs_patch <- function(path, required_version = IBS_PATCH_VERSION) {
  if (!file.exists(path)) return(FALSE)
  lines <- readLines(path, warn = FALSE)
  m <- regmatches(lines, regexec(IBS_STAMP_RE, lines))
  found <- Filter(function(x) length(x) == 2L, m)
  if (!length(found)) return(FALSE)
  ver <- as.integer(found[[1L]][[2L]])
  isTRUE(ver >= required_version)
}

apply_ibs_patch <- function(target_path, patch_path) {
  if (has_ibs_patch(target_path)) {
    me_log("INFO", "IBS patch already present (version >= %d) — skipping", IBS_PATCH_VERSION)
    return(invisible(FALSE))
  }
  patch_lines <- readLines(patch_path, warn = FALSE)
  target_lines <- readLines(target_path, warn = FALSE)
  writeLines(c(patch_lines, "", target_lines), target_path)
  me_log("INFO", "Applied IBS patch v%d to %s", IBS_PATCH_VERSION, target_path)
  invisible(TRUE)
}

#' Verify that named baselines have accompanying .meta.json sidecars
#' whose hard keys match the configuration.
#'
#' @param prereq A prerequisite spec list with fields:
#'   id (str), type ("sidecar-meta"), required_for (chr vec of baseline names),
#'   required_keys (chr vec of JSON keys to compare; default below).
#' @param cfg The full parsed config.yaml (must contain $baselines and
#'   $evaluator$env_vars).
#' @return list(pass = logical, reason = character).
check_sidecar_meta <- function(prereq, cfg) {
  default_keys <- c("scenario_name", "n_subjects", "n_sims",
                    "dgp_version", "evaluator_sha")
  keys <- prereq$required_keys %||% default_keys

  # config-side values (drawn from evaluator.env_vars where present)
  cfg_vals <- list(
    scenario_name = cfg$evaluator$env_vars$SCENARIO_NAME,
    n_subjects    = as.integer(cfg$evaluator$env_vars$N_SUBJECTS %||% NA),
    n_sims        = as.integer(cfg$evaluator$env_vars$N_SIMS %||% NA)
  )

  for (b in prereq$required_for) {
    bcfg <- cfg$baselines[[b]]
    if (is.null(bcfg) || is.null(bcfg$meta_file)) {
      return(list(pass = FALSE,
                  reason = sprintf("baseline '%s': meta_file not declared", b)))
    }
    if (!file.exists(bcfg$meta_file)) {
      return(list(pass = FALSE,
                  reason = sprintf("baseline '%s': meta file missing at %s",
                                   b, bcfg$meta_file)))
    }
    meta <- jsonlite::read_json(bcfg$meta_file, simplifyVector = TRUE)
    for (k in keys) {
      if (!k %in% names(cfg_vals)) next  # evaluator_sha & dgp_version: warn-only
      if (!identical(meta[[k]], cfg_vals[[k]])) {
        return(list(pass = FALSE,
                    reason = sprintf(
                      "baseline '%s': key %s mismatch (meta=%s, config=%s)",
                      b, k,
                      paste(meta[[k]], collapse = ","),
                      paste(cfg_vals[[k]], collapse = ","))))
      }
    }
  }
  list(pass = TRUE, reason = "all sidecar-meta keys match")
}
