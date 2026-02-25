---
paths:
  - "**/*.R"
  - "Figures/**/*.R"
  - "scripts/**/*.R"
  - "comparisons/**/*.R"
  - "Missing Types/**/*.R"
---

# R Code Standards

**Standard:** Senior Principal Data Engineer + PhD researcher quality

---

## 1. Reproducibility

- `set.seed()` called ONCE at top (YYYYMMDD format)
- All packages loaded at top via `library()` (not `require()`)
- All paths via `here::here()` — never hardcoded absolute paths
- `dir.create(..., recursive = TRUE)` for output directories

## 2. Function Design

- `snake_case` naming, verb-noun pattern
- Roxygen-style documentation
- Default parameters, no magic numbers
- Named return values (lists or tibbles)

## 3. Domain Correctness

- Verify estimator implementations match paper formulas
- Pseudo-observation calculations: check for ties, censoring edge cases
- Subject-level bootstrap: resample subjects, not individual observations
- Competing risks: verify cause-specific vs. subdistribution hazard intent
- Check known package bugs (document below in Common Pitfalls)

## 4. Visual Identity

```r
# --- Okabe-Ito colorblind-friendly palette ---
okabe_ito <- c(
  orange    = "#E69F00",
  sky_blue  = "#56B4E9",
  green     = "#009E73",
  yellow    = "#F0E442",
  blue      = "#0072B2",
  vermilion = "#D55E00",
  purple    = "#CC79A7",
  black     = "#000000"
)

# Semantic assignments
color_primary   <- okabe_ito["blue"]      # #0072B2
color_secondary <- okabe_ito["vermilion"]  # #D55E00
color_tertiary  <- okabe_ito["green"]      # #009E73
color_accent    <- okabe_ito["orange"]     # #E69F00
color_neutral   <- "#525252"
```

### Custom Theme
```r
theme_publication <- function(base_size = 12) {
  theme_minimal(base_size = base_size) +
    theme(
      plot.title = element_text(face = "bold", size = base_size + 2),
      axis.title = element_text(size = base_size),
      legend.position = "bottom",
      panel.grid.minor = element_blank(),
      strip.text = element_text(face = "bold")
    )
}
```

### Figure Dimensions for Papers
```r
ggsave(filepath, width = 7, height = 5, dpi = 300, bg = "white")
```

## 5. RDS Data Pattern

**Heavy computations saved as RDS; papers/analysis loads pre-computed data.**

```r
saveRDS(result, here::here(out_dir, "descriptive_name.rds"))
```

## 6. Common Pitfalls

| Pitfall | Impact | Prevention |
|---------|--------|------------|
| `bg = "transparent"` in papers | Invisible on white PDF pages | Use `bg = "white"` for all paper figures |
| Hardcoded paths | Breaks on other machines | Use `here::here()` |
| Bootstrap resampling rows not subjects | Underestimates variance for recurrent events | Resample at subject level: `unique(id)` then filter |
| `pseudo()` with heavy censoring | Biased pseudo-observations | Check censoring distribution; consider IPCW |
| `coxph()` with time-varying covariates | Silent misspecification | Verify `tstart`/`tstop` intervals don't overlap |
| `survfit()` competing risks | Wrong estimator if cause not specified | Explicitly set `type` and verify cause coding |
| Ignoring tied event times | Biased Nelson-Aalen estimates | Use Efron or exact method; document choice |

## 7. Line Length & Mathematical Exceptions

**Standard:** Keep lines <= 100 characters.

**Exception: Mathematical Formulas** -- lines may exceed 100 chars **if and only if:**

1. Breaking the line would harm readability of the math (influence functions, matrix ops, finite-difference approximations, formula implementations matching paper equations)
2. An inline comment explains the mathematical operation:
   ```r
   # Sieve projection: inner product of residuals onto basis functions P_k
   alpha_k <- sum(r_i * basis[, k]) / sum(basis[, k]^2)
   ```
3. The line is in a numerically intensive section (simulation loops, estimation routines, inference calculations)

**Quality Gate Impact:**
- Long lines in non-mathematical code: minor penalty (-1 to -2 per line)
- Long lines in documented mathematical sections: no penalty

## 8. Code Quality Checklist

```
[ ] Packages at top via library()
[ ] set.seed() once at top (YYYYMMDD)
[ ] All paths via here::here()
[ ] Functions documented (Roxygen)
[ ] Figures: white bg, 300 DPI, explicit dimensions
[ ] RDS: every computed object saved
[ ] Comments explain WHY not WHAT
[ ] Subject-level resampling for bootstrap
```
