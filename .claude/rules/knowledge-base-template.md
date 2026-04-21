---
paths:
  - "Papers/**/*.tex"
  - "scripts/**/*.R"
  - "comparisons/**/*.R"
  - "Missing Types/**/*.R"
---

# Dissertation Knowledge Base: ML for Recurrent Events with Multiple Types

## Notation Registry

| Rule | Convention | Example | Anti-Pattern |
|------|-----------|---------|-------------|
| Counting process | $N_k(t)$ for type $k$ | $N_1(t)$ = events of type 1 by time $t$ | $N(t,k)$ or $N^{(k)}$ |
| At-risk indicator | $Y(t)$ = 1 if under observation at $t$ | $Y_i(t)$ for subject $i$ | $R(t)$, $Z(t)$ |
| Intensity/hazard | $\lambda_k(t)$ for cause-specific | $\lambda_1(t \mid \mathcal{F}_{t^-})$ | $h(t)$, $\mu(t)$ (ambiguous) |
| Cumulative hazard | $\Lambda_k(t) = \int_0^t \lambda_k(s) ds$ | | $H(t)$ |
| Pseudo-observation | $\hat{\theta}_i$ for subject $i$ | $\hat{\theta}_i = n \hat{\theta} - (n-1)\hat{\theta}^{(-i)}$ | $\tilde{\theta}_i$, $PO_i$ |
| Censoring time | $C_i$ for subject $i$ | | $T_c$, $U$ |
| Event time | $T_{ij}$ = $j$-th event time for subject $i$ | | $t_{ij}$ (lowercase for observed) |
| Covariates | $\mathbf{X}_i$ (bold for vector) | | $Z$ (conflicts with at-risk) |

## Symbol Reference

| Symbol | Meaning | Context |
|--------|---------|---------|
| $N_k(t)$ | Counting process for event type $k$ | Recurrent events |
| $Y(t)$ | At-risk indicator | Survival/counting |
| $\lambda_k(t)$ | Cause-specific intensity | Competing risks / multi-type |
| $\hat{\theta}_i$ | Pseudo-observation for subject $i$ | Pseudo-observation methods |
| $\mu_k(t)$ | Mean cumulative function for type $k$ | $E[N_k(t)]$ |
| $C(t, s)$ | C-index at time $t$ with horizon $s$ | Discrimination metric |
| $\text{Brier}(t)$ | Brier score at time $t$ | Calibration metric |
| $\hat{G}(t)$ | Kaplan-Meier estimate of censoring | IPCW weights |

## Dissertation Projects

| # | Project | Core Question | Key Methods | Status |
|---|---------|--------------|-------------|--------|
| 1 | Comparisons | How do ML methods compare for recurrent event prediction? | Random forests, boosting, neural nets, Cox-based | Active |
| 2 | Missing Types | How to handle missing event type indicators? | Pseudo-observations, IPW, multiple imputation | Active |

## Simulation Studies

| Study | DGP | Sample Sizes | Scenarios | Purpose |
|-------|-----|-------------|-----------|---------|
| | | | | |

## Estimand Registry

| Estimand | Definition | Identification | Estimation |
|----------|-----------|---------------|------------|
| Mean cumulative function | $\mu_k(t) = E[N_k(t)]$ | No unmeasured confounding | Nelson-Aalen type estimator |
| Cause-specific hazard | $\lambda_k(t) = \lim_{h\to 0} P(T \in [t,t+h), K=k \mid T \geq t)/h$ | Independent censoring | Cox PH, ML methods |
| Pseudo-observation | $\hat{\theta}_i = n\hat{\theta} - (n-1)\hat{\theta}^{(-i)}$ | Regularity conditions (Graw et al. 2009) | Jackknife leave-one-out |

## DGP Configurations

| Config | Hazard | Censoring | Types | Dependence | Use |
|--------|--------|-----------|-------|------------|-----|
| | | | | | |

## Tolerance Thresholds

| Quantity | Tolerance | Context |
|----------|-----------|---------|
| Point estimates | 1e-6 | Regression coefficients |
| Standard errors | 1e-3 | Bootstrap / asymptotic SE |
| C-index | 1e-3 | Discrimination comparison |
| Brier score | 1e-4 | Calibration comparison |

## Design Principles

| Principle | Evidence | Projects Applied |
|-----------|----------|-----------------|
| Subject-level bootstrap | Recurrent events are correlated within subject | All |
| IPCW for censoring | Dependent censoring biases pseudo-obs | Missing Types |
| Train-test by subject | Prevents data leakage with recurrent events | Comparisons |

## Anti-Patterns (Don't Do This)

| Anti-Pattern | What Happened | Correction |
|-------------|---------------|-----------|
| Row-level train-test split | Leaks future events into training | Split at subject level |
| Ignoring event type in censoring model | Informative censoring bias | Stratify censoring model by type |
| Using subdistribution hazard for prediction | Not interpretable for recurrent events | Use cause-specific hazard |

## R Code Pitfalls

| Bug | Impact | Fix |
|-----|--------|-----|
| `pseudo()` with heavy censoring (>50%) | Biased pseudo-observations | Use IPCW-adjusted pseudo-obs |
| `coxph()` cluster(id) vs frailty(id) | Different variance estimates | Choose based on marginal vs conditional model |
| `survfit()` without specifying type | Default may not match intent | Always explicit: `type = "kaplan-meier"` or `"flemington-harrington"` |
| `Surv(time, status)` with multiple types | Treats all events as one | Use `Surv(time, factor(status))` for competing risks |
| Parallel RNG without `RNGkind("L'Ecuyer")` | Non-reproducible parallel simulations | Set `RNGkind("L'Ecuyer-CMRG")` before `mclapply()` |
