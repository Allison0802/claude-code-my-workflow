# ============================================================================
# METADATA
# ============================================================================
# Description: Source shared functions from Missing Types/ subproject
# Last Updated: 2026-03-22
# ============================================================================

# Determine project root
if (requireNamespace("here", quietly = TRUE)) {
  project_root <- here::here()
} else {
  project_root <- getwd()
}

# Path to Missing Types functions
missing_types_path <- file.path(dirname(project_root), "Missing Types", "functions.R")

if (!file.exists(missing_types_path)) {
  # Try alternative path (if running from Research/)
  missing_types_path <- file.path(project_root, "Missing Types", "functions.R")
}

if (!file.exists(missing_types_path)) {
  stop("Cannot find Missing Types/functions.R. Expected at: ", missing_types_path,
       "\nSet MISSING_TYPES_PATH environment variable if needed.")
}

# Allow override via environment variable
if (Sys.getenv("MISSING_TYPES_PATH") != "") {
  missing_types_path <- Sys.getenv("MISSING_TYPES_PATH")
}

cat("Sourcing Missing Types functions from:", missing_types_path, "\n")
source(missing_types_path)

# Verify key functions are available
required_fns <- c(
  "rate_cox_data_gen_complex",
  "transform_with_covariates_complex",
  "generate_km_pseudoEst",
  "introduce_mcar_missingness",
  "introduce_mar_missingness",
  "fit_propensity_model",
  "fit_propensity_model_rf",
  "compute_dr_indicators",
  "compute_dr_indicators_rf",
  "custom_c_index_time_specific"
)

missing_fns <- required_fns[!sapply(required_fns, exists, mode = "function")]
if (length(missing_fns) > 0) {
  stop("Missing required functions from Missing Types/functions.R: ",
       paste(missing_fns, collapse = ", "))
}

cat("All required Missing Types functions loaded successfully.\n")
