# Phase -1: prerequisites. Owns the IBS patch, baseline meta sidecars, and column-presence checks.

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

#' Run the evaluator in smoke mode and verify named columns are present.
#'
#' @param prereq list with: id, type ("column-presence"),
#'   smoke_env_vars (named list), required_columns (chr vec).
#' @param cfg full config; uses cfg$target_script and
#'   cfg$evaluator$results_file_pattern.
#' @return list(pass, reason).
check_column_presence <- function(prereq, cfg) {
  # Base config env vars first, smoke overrides last — later duplicates win
  # on Unix under system2(..., env = ...).
  env_kvs <- c(cfg$evaluator$env_vars, prereq$smoke_env_vars)
  env_str <- vapply(seq_along(env_kvs), function(i)
                    sprintf("%s=%s", names(env_kvs)[i], env_kvs[[i]]),
                    character(1))

  err_file <- tempfile(fileext = ".txt")
  status <- system2("Rscript", c("--vanilla", shQuote(cfg$target_script)),
                    env = env_str, stdout = NULL, stderr = err_file)
  if (status != 0) {
    tail_msg <- if (file.exists(err_file))
                   paste(utils::tail(readLines(err_file, warn = FALSE), 6L),
                         collapse = "\n") else ""
    return(list(pass = FALSE,
                reason = sprintf("evaluator exited non-zero (status=%d)%s",
                                 status,
                                 if (nzchar(tail_msg))
                                   sprintf(":\n%s", tail_msg) else "")))
  }
  out_path <- cfg$evaluator$results_file_pattern
  if (!file.exists(out_path)) {
    return(list(pass = FALSE,
                reason = sprintf("results file not found at %s", out_path)))
  }
  df <- readRDS(out_path)
  missing <- setdiff(prereq$required_columns, names(df))
  if (length(missing) > 0) {
    return(list(pass = FALSE,
                reason = sprintf("missing columns: %s",
                                 paste(missing, collapse = ", "))))
  }
  for (col in prereq$required_columns) {
    if (!is.numeric(df[[col]])) {
      return(list(pass = FALSE,
                  reason = sprintf("column %s is not numeric", col)))
    }
    if (anyNA(df[[col]])) {
      return(list(pass = FALSE,
                  reason = sprintf("column %s contains NA", col)))
    }
  }
  list(pass = TRUE,
       reason = "all required columns present, numeric, and NA-free")
}
