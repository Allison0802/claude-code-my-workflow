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
