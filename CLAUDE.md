# CLAUDE.MD -- PhD Dissertation: ML for Recurrent Events

**Project:** ML Methods for Recurrent Events with Multiple Types
**Institution:** UNC Chapel Hill
**Branch:** main
**NotebookLM:** [ML for Recurrent Events](https://notebooklm.google.com/notebook/0bf80af5-8b8d-423d-b7ef-94b13ad48f7b) | [Interpretable AI](https://notebooklm.google.com/notebook/fea2207b-7ec1-463c-b73f-58c0c4febb41)
[Machine Learning Fundamentals](https://notebooklm.google.com/notebook/c3aab8e1-5c4b-43ec-bafc-ae3745a7c493)
[Survival Analysis Fundamentals](https://notebooklm.google.com/notebook/3faa5656-280d-4ffc-ae2d-5487075bc94e)
---

## Tech Stack

R 4.4.0 (Longleaf HPC) | XeLaTeX (3-pass + bibtex) | SLURM (UNC Longleaf)

Key R packages: `survival`, `cmprsk`, `randomForest`, `ranger`, `partykit`, `LongituRF`, `SAEforest`, `glmnet`, `nnet`, `tidyverse`, `here`

---

## Core Principles

- **Plan first** -- enter plan mode before non-trivial tasks; save plans to `quality_reports/plans/`
- **Verify after** -- compile/render and confirm output at the end of every task
- **Reproducibility** -- `set.seed(YYYYMMDD)`, `here::here()` paths, all results replicable
- **Quality gates** -- nothing ships below 80/100 (commit), 90/100 (PR), 95/100 (excellence)
- **[LEARN] tags** -- when corrected, save `[LEARN:category] wrong -> right` to MEMORY.md
- **Change logging** -- see `## Change Logging` section below and `.claude/rules/session-logging.md`
- **Skill outputs preserved** -- proposals, summaries, reports, plans, and other documents produced by skills go into dedicated dated subfolders; never overwrite previous runs
- **Test locally first** -- before writing or editing any script intended for Longleaf, run a small-scale local test (reduced N, fewer iterations) to verify logic and catch errors cheaply

---

## Key Paths

| Path | Purpose |
|------|---------|
| `.claude/rules/` | R conventions, knowledge base, session logging rules |
| `.claude/agents/` | domain-reviewer, r-reviewer, verifier, proofreader |
| `.claude/WORKFLOW_QUICK_REF.md` | Skill/command quick reference |
| `Bibliography_base.bib` | Centralized bibliography (shared across sub-projects) |
| `Papers/` | LaTeX manuscript chapters |
| `Preambles/header.tex` | LaTeX headers |
| `scripts/R/` | Shared R code (helpers, themes, palettes) |
| `quality_reports/` | Plans, session logs, merge reports |
| `explorations/` | Research sandbox (60/100 threshold) |
| `comparisons/` | Sub-project: method comparisons (separate repo) |
| `Missing Types/` | Sub-project: missing event types (separate repo) |

---

## Commands

```bash
# LaTeX manuscript (3-pass)
cd Papers && TEXINPUTS=../Preambles:$TEXINPUTS xelatex -interaction=nonstopmode file.tex
BIBINPUTS=..:$BIBINPUTS bibtex file
TEXINPUTS=../Preambles:$TEXINPUTS xelatex -interaction=nonstopmode file.tex  # run twice more

# R simulation
Rscript scripts/R/filename.R
```

---

## Longleaf / SLURM Submit Scripts

**Always use `$SLURM_SUBMIT_DIR` for the working directory — never `$(dirname "${BASH_SOURCE[0]}")`.**

Canonical idiom (used by all `submit_missing_types_*.sh` and the fixed `submit_carra_*.sh`):

```bash
WORKDIR="${SLURM_SUBMIT_DIR:-$PWD}"
cd "${WORKDIR}"
mkdir -p "${WORKDIR}/logs"
mkdir -p "${WORKDIR}/results_<scenario>"
```

**Why:** Under SLURM, `slurmd` may stage the script to `/var/spool/slurmd/<job>/` and run it from there, so `BASH_SOURCE[0]` resolves to a system path the user cannot write to. `mkdir: cannot create directory 'logs': Permission denied` across every array task is the signature. `SLURM_SUBMIT_DIR` is always set to the directory `sbatch` was invoked from, which the user owns.

**Also:** `#SBATCH --output=logs/...` opens the log file *before* the script runs. Create `logs/` at submit time (`mkdir -p logs results_<scenario> && sbatch ...`) so the first job's stderr lands somewhere, not just rely on the script's own `mkdir`.

This mistake cost one full array submission cycle on 2026-04-21 (7 CARRA CCA tasks lost before the fix landed in commit `c2e86a3`).

---

## Sub-Project Hybrid Model

Parent repo is shared config hub for two sub-projects (separate git repos):

| Sub-Project | Path | Focus |
|-------------|------|-------|
| Comparisons | `comparisons/` | ML method comparisons for recurrent events (37 scenarios) |
| Missing Types | `Missing Types/` | Pseudo-observations with missing event types (5 imputation methods) |

**Shared from parent:** `Bibliography_base.bib`, `scripts/R/`, `.claude/rules/`, `Figures/`

**Conventions across all:**
- Okabe-Ito colorblind-friendly palette (see `.claude/rules/r-code-conventions.md`)
- `here::here()` for all R paths
- `set.seed(YYYYMMDD)` at top of stochastic scripts
- Publication-ready figures: 300 DPI, white background, `.pdf` or `.png`

---

## Architecture

```
Data Generation -> Landmark Transformation -> Pseudo-observations -> Model Fitting -> Evaluation
```

- **Comparisons**: Recurrent competing risks data (frailty x complexity x correlation x censoring), Cox/RF/MERF models, time-specific C-index
- **Missing Types**: MCAR/MAR missingness (10-50%), 5 imputation methods (CCA, IPW, IPW-RF, RPM, DR), recovery of predictive performance
- Shared `functions.R`: `rate_cox_data_gen_complex()`, landmark transformation, pseudo-observation computation

---

## Agents (invoke proactively after completing work)

- **`domain-reviewer`** -- after drafting methods/simulations/results (5 lenses: survival + ML)
- **`r-reviewer`** -- after writing/modifying R scripts (quality, reproducibility, figures)
- **`verifier`** -- before committing or creating PRs (compile, render, deploy)
- **`proofreader`** -- after modifying manuscript content (grammar, typos, overflow)

---

## Change Logging

Applies to parent and both subprojects. See `.claude/rules/session-logging.md` for full protocol.

**After any major change**, Claude MUST:
1. Update `Last Updated: YYYY-MM-DD` in the modified file's header
2. Append to `quality_reports/session_logs/YYYY-MM-DD_description.md`:
   `- [HH:MM] <file> -- <what changed and why>`

**Do not log:** whitespace fixes, comment-only edits, auto-generated output files.

---

## Skills & Workflow

Skills are auto-discovered from `.claude/skills/`. See `.claude/WORKFLOW_QUICK_REF.md` for the full command reference.

Key entry points: `/review` (auto-routes by file type), `/commit`, `/paper-compile`, `/run-experiment`, `/arxiv`, `/research-pipeline`

Scientific skills at `.claude/skills/claude-scientific-skills/scientific-skills/` (scikit-survival, statistical-analysis, pymc, etc.)

Dormant slide skills archived to `.claude/skills/_DORMANT/` -- reactivate for defense or job talk.

---

## Skill Output Storage

All documents produced by skills (proposals, summaries, reports, refinement logs, review transcripts, plans, etc.) **must be saved to their own named and dated subfolder** under a dedicated directory. **Never overwrite or append to existing outputs from previous runs.**

**Pattern:** `<subproject>/quality_reports/<skill-category>/YYYY-MM-DD_<short-description>/`

**Examples:**

```text
Missing Types/quality_reports/refine-logs/2026-04-12_pseudo-obs-refinement/
comparisons/quality_reports/review-transcripts/2026-04-12_cox-vs-rf-review/
quality_reports/paper-improvement/2026-04-12_biostat-round3/
```

**Rules:**

- Each skill run creates a **new dated subfolder** -- never reuse or overwrite a previous one
- If the same skill runs twice on the same day, append a sequence number: `2026-04-12_topic-02/`
- Place outputs in the **sub-project** they belong to (`comparisons/`, `Missing Types/`), or in the parent `quality_reports/` for cross-project work
- Skill-specific folder names (e.g., `refine-logs/`, `review-transcripts/`, `paper-improvement/`, `novelty-checks/`) should reflect the skill category

---

## Current Project State

| Project | Status |
|---------|--------|
| Comparisons (`comparisons/`) | Active -- ML method comparisons |
| Missing Types (`Missing Types/`) | Active -- pseudo-obs with missing event types |
