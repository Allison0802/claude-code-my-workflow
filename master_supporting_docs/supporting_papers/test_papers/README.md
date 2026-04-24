# Synthetic Test Papers for `paper-stress-test` Skill

Purpose: exercise the full nine-lens debate loop at `--depth 1` in ~10–15 minutes per run, to verify the 2026-04-24 skill mutations (see `.claude/skills/paper-stress-test/autoresearch-paper-stress-test/changelog.md`) produce artifacts that pass evals E1–E10.

Each paper is **deliberately** flawed on several lenses so the Reviewer has real material to attack and the Author has material to concede — exercising severity decisions, per-lens validator calls, and the editorial-tone ban in `agents/author.md`.

## Papers

### Paper A — `testpaper_a_rmst_variance.pdf`

**Type:** `new-estimator`
**Topic:** closed-form variance for RMST pseudo-observations
**~1.5 pages.**

**Baked-in weaknesses (one per targeted lens):**

| Lens | Weakness | Expected Reviewer attack |
|------|----------|---|
| 0 data | only simulated at $n=500$ | "Why no small-$n$ check?" |
| 1 estimand | $\tau=2$ fixed; OK | clean-ish |
| 2 identification | assumes $T \perp C$ flatly | "No baseline-covariate extension?" |
| 3 methodology | no rate / Donsker / asymptotic derivation | "Where is the proof of asymptotic normality?" |
| 4 overclaims | "drop-in replacement" is strong | "Under what conditions does the approximation hold?" |
| 5 alternatives | no jackknife timing comparator | "Why not benchmark vs jackknife?" |
| 6 generalizability | single-event right-censoring only | "What about competing risks?" |
| 7 positioning | does **not** cite Andersen–Klein–Rosthøj 2003 | thematic-notebook hit via *ML for Recurrent Events* |
| 8 reproducibility | no seed, no code | "Where is the simulation script?" |

**Expected recommendation:** `flag` (≥3 major findings).

### Paper B — `testpaper_b_rf_calibration.pdf`

**Type:** `predictive-ML`
**Topic:** SMOTE + random forest calibration
**~1.5 pages.**

**Baked-in weaknesses:**

| Lens | Weakness | Expected Reviewer attack |
|------|----------|---|
| 0 data | SMOTE applied to **combined train+val** before splitting | "Synthetic examples leak into validation; reported AUROC is optimistic." |
| 1 estimand | Brier + ECE are reasonable | clean |
| 2 identification | test set from same distribution | "No held-out site / temporal split?" |
| 3 methodology | default hyperparameters, no tuning | "No sensitivity analysis on tree depth." |
| 4 overclaims | "state-of-the-art" with no confidence intervals or baselines | "Compared against what SOTA?" |
| 5 alternatives | no comparison vs class weights, calibration wrappers | "Why not Platt scaling / isotonic?" |
| 6 generalizability | two datasets, one private | "External validation?" |
| 7 positioning | cites Chawla 2002 + Breiman 2001 only | "No engagement with modern calibration literature (Guo 2017, Niculescu-Mizil 2005)." |
| 8 reproducibility | no seed, no code, private dataset | "Unreproducible claim." |

**Expected recommendation:** `flag` or `skip` (leakage is a critical-level finding).

## How to use

```bash
# From repo root:
/paper-stress-test master_supporting_docs/supporting_papers/test_papers/testpaper_a_rmst_variance.pdf --depth 1 --no-checkpoint
```

After the run:

```bash
# Score against the mutation evals:
python3 .claude/skills/paper-stress-test/autoresearch-paper-stress-test/score_corpus.py
```

The new run's artifacts should pass E1–E10 at ≥ 8/10 per run. If any eval fails, read the specific lens's transcript + state and check which mutation was bypassed.

## Regenerating from source

```bash
cd master_supporting_docs/supporting_papers/test_papers
pandoc testpaper_a_rmst_variance.md -o testpaper_a_rmst_variance.pdf --pdf-engine=xelatex
pandoc testpaper_b_rf_calibration.md -o testpaper_b_rf_calibration.pdf --pdf-engine=xelatex
```

## Not real research

Both papers are synthetic, written for skill-testing purposes only. The methods described are not recommended; in particular, applying SMOTE before a train/val split is a well-known leakage pattern, and the RMST "closed-form variance" in Paper A skips the rate conditions that would make it a real theorem.
