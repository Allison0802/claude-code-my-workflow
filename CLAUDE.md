# CLAUDE.MD -- PhD Dissertation: ML for Recurrent Events

**Project:** ML Methods for Recurrent Events with Multiple Types
**Institution:** UNC Chapel Hill
**Branch:** main

---

## Tech Stack

| Tool | Version / Detail |
|------|-----------------|
| R | 4.4.0 (Longleaf HPC) |
| LaTeX | XeLaTeX (3-pass + bibtex) |
| Cluster | SLURM (UNC Longleaf) |
| Key R packages | `survival`, `cmprsk`, `randomForest`, `ranger`, `partykit`, `LongituRF`, `SAEforest`, `glmnet`, `nnet`, `tidyverse`, `here` |

---

## Setup & Installation

```bash
# R packages (install once)
install.packages(c(
  "tidyverse", "survival", "cmprsk", "Hmisc",
  "randomForest", "ranger", "partykit", "LongituRF", "SAEforest",
  "glmnet", "nnet", "parallel", "here",
  "gridExtra", "patchwork"
))

# LaTeX: requires XeLaTeX distribution (e.g., TeX Live or MacTeX)
# Verify: xelatex --version

# Clone sub-projects (separate repos)
cd Research/
git clone <comparisons-repo-url> comparisons/
git clone <missing-types-repo-url> "Missing Types/"
```

---

## Core Principles

- **Plan first** -- enter plan mode before non-trivial tasks; save plans to `quality_reports/plans/`
- **Verify after** -- compile/render and confirm output at the end of every task
- **Reproducibility** -- `set.seed(YYYYMMDD)`, `here::here()` paths, all results replicable
- **Quality gates** -- nothing ships below 80/100
- **[LEARN] tags** -- when corrected, save `[LEARN:category] wrong → right` to MEMORY.md
- **Change logging** -- after any major change in **any folder** (parent or subprojects `comparisons/`, `Missing Types/`): (1) update the `Last Updated` metadata header in the modified script, and (2) append a one-line entry to `quality_reports/session_logs/` describing what changed and why

---

## Folder Structure

```
Research/
├── CLAUDE.md                    # This file
├── .claude/                     # Rules, skills, agents, hooks
│   ├── rules/                   # r-code-conventions.md, knowledge-base-template.md, etc.
│   ├── agents/                  # domain-reviewer.md, etc.
│   └── WORKFLOW_QUICK_REF.md   # Skill/command quick reference
├── Bibliography_base.bib        # Centralized bibliography (shared across sub-projects)
├── Figures/                     # Shared figures and images
├── Papers/                      # LaTeX manuscript chapters
├── Preambles/header.tex         # LaTeX headers
├── Quarto/                      # Quarto documents
├── Slides/                      # Presentation slides
├── scripts/                     # Utility scripts
│   └── R/                       # Shared R code (helpers, themes, palettes)
├── docs/                        # Documentation
├── guide/                       # Project guide materials
├── quality_reports/             # Plans, session logs, merge reports
├── explorations/                # Research sandbox (see rules)
├── templates/                   # Session log, quality report templates
├── master_supporting_docs/      # Reference papers
├── comparisons/                 # Sub-project: method comparisons (separate repo)
└── Missing Types/               # Sub-project: missing event types (separate repo)
```

---

## Commands

```bash
# LaTeX manuscript (3-pass, XeLaTeX)
cd Papers && TEXINPUTS=../Preambles:$TEXINPUTS xelatex -interaction=nonstopmode file.tex
BIBINPUTS=..:$BIBINPUTS bibtex file
TEXINPUTS=../Preambles:$TEXINPUTS xelatex -interaction=nonstopmode file.tex
TEXINPUTS=../Preambles:$TEXINPUTS xelatex -interaction=nonstopmode file.tex

# Run R simulation
Rscript scripts/R/filename.R

# Quality score
python scripts/quality_score.py file
```

---

## Quality Thresholds

| Score | Gate | Meaning |
|-------|------|---------|
| 80 | Commit | Good enough to save |
| 90 | PR | Ready for deployment |
| 95 | Excellence | Aspirational |

---

## Skills & Agents Quick Reference

### Writing & Manuscript

| Command | What It Does |
|---------|-------------|
| `/compile-latex [file]` | 3-pass XeLaTeX + bibtex (manual) |
| `/paper-compile [file]` | Compile LaTeX, auto-fix errors, verify output |
| `/proofread [file]` | Grammar/typo review |
| `/review-paper [file]` | Deep manuscript review |
| `/validate-bib` | Cross-reference citations |
| `/paper-plan [outline]` | Structured paper outline from review + results |
| `/paper-write [section]` | Draft LaTeX section by section |
| `/paper-figure [results]` | Publication-quality figures from experiment data |
| `/paper-writing [outline]` | Full pipeline: plan → figures → write → compile |
| `/auto-paper-improvement-loop [file]` | Autonomous GPT review → fix → recompile loop |

### R Code & Analysis

| Command | What It Does |
|---------|-------------|
| `/review-r [file]` | R code quality, reproducibility, figure compliance |
| `/data-analysis [dataset]` | End-to-end R analysis workflow |
| `/analyze-results [path]` | Analyze experiment results, build comparison tables |
| `/visual-audit [file]` | Figure layout audit (overflow, fonts, spacing) |

### SLURM / Simulation

| Command | What It Does |
|---------|-------------|
| `/run-experiment [script]` | Deploy and run R simulations on Longleaf SLURM |
| `/monitor-experiment [job]` | Check SLURM progress, collect results, flag failures |

### Literature & Ideas

| Command | What It Does |
|---------|-------------|
| `/lit-review [topic]` | Literature search + synthesis |
| `/research-lit [topic]` | Search papers, find related work, summarize key ideas |
| `/arxiv [query]` | Search, download, summarize arXiv papers |
| `/novelty-check [idea]` | Verify novelty against recent literature |
| `/idea-creator [topic]` | Generate and rank research ideas |
| `/idea-discovery [topic]` | Full pipeline: lit → ideas → novelty check |
| `/research-ideation [topic]` | Research questions + strategies |
| `/interview-me [topic]` | Interactive research interview |

### Review & QA

| Command | What It Does |
|---------|-------------|
| `/research-review [file]` | Deep critical review via GPT/Codex |
| `/auto-review-loop [file]` | Autonomous multi-round review → fix loop |
| `/auto-review-loop-llm [file]` | Same, using any OpenAI-compatible LLM API |
| `/devils-advocate [claim]` | Adversarial review of methods or arguments |
| `/proof-writer [theorem]` | Write rigorous mathematical proofs |
| `/research-pipeline [topic]` | Full pipeline: idea discovery → implementation → review |

### Git

| Command | What It Does |
|---------|-------------|
| `/commit [msg]` | Stage, commit, PR, merge with quality check |

---

## Agents Quick Reference

Agents run autonomously via the Agent tool. Invoke proactively after completing work.

| Agent | When to Use |
|-------|------------|
| `domain-reviewer` | After drafting methods, simulations, or results — checks statistical correctness through 5 lenses (survival analysis + ML expertise) |
| `r-reviewer` | After writing or modifying any R script — checks code quality, reproducibility, figure standards |
| `verifier` | Before committing or creating PRs — checks compile, render, deploy |
| `proofreader` | After creating or modifying manuscript content — grammar, typos, overflow |

---

## Scientific Skills (claude-scientific-skills bundle)

Available at `.claude/skills/claude-scientific-skills/scientific-skills/`. Reference for methodology and Python cross-checking:

| Skill | Relevance |
|-------|----------|
| `scikit-survival` | Survival analysis reference: Cox, RSF, concordance index, competing risks |
| `statistical-analysis` | Test selection, assumption checks, APA-formatted results |
| `exploratory-data-analysis` | EDA guidance for simulation output |
| `pymc` | Bayesian frailty modeling (hierarchical extension research) |
| `pubmed-database` | Medical literature search for clinical context |
| `openalex-database` | Academic paper search across all fields |
| `literature-review` | Structured lit review workflow |
| `hypothesis-generation` | Research hypothesis development |
| `peer-review` | Manuscript peer review guidance |
| `scientific-writing` | Academic writing style and structure |

**Dormant** (slide/teaching focused — archived to `.claude/skills/_DORMANT/`, reactivate for defense or job talk):
`translate-to-quarto`, `create-lecture`, `slide-excellence`, `qa-quarto`, `pedagogy-review`, `extract-tikz`, `deploy`, `visual-audit`, `devils-advocate`

---

## Sub-Project Hybrid Model

This repo is the **parent hub** for two sub-projects that are separate git repos:

| Sub-Project | Path | Focus |
|-------------|------|-------|
| Comparisons | `comparisons/` | Method comparison simulations |
| Missing Types | `Missing Types/` | Handling missing event types |

**Shared resources from parent:**
- `Bibliography_base.bib` -- centralized bibliography
- `scripts/R/` -- shared R helpers, color palette, ggplot theme
- `.claude/rules/` -- shared conventions (R code, knowledge base)
- `Figures/` -- shared figures referenced across papers

**Conventions across all sub-projects:**
- Colorblind-friendly Okabe-Ito palette (see `.claude/rules/r-code-conventions.md`)
- `here::here()` for all file paths in R
- `set.seed(YYYYMMDD)` at top of every stochastic script
- Publication-ready figures: 300 DPI, white background, `.pdf` or `.png`

---

## Architecture

```
Data Generation → Landmark Transformation → Pseudo-observations → Model Fitting → Evaluation
```

- **Comparisons project**: Generates recurrent competing risks data under 37 scenarios (frailty × complexity × correlation × censoring), fits Cox/RF/MERF models, evaluates via time-specific C-index
- **Missing Types project**: Introduces MCAR/MAR missingness (10-50%) into event types, applies 5 imputation methods (CCA, IPW, IPW-RF, RPM, DR), evaluates recovery of predictive performance
- Both projects share `functions.R` for data generation (`rate_cox_data_gen_complex()`), landmark transformation, and pseudo-observation computation

---

## Change Logging

**This rule applies to the parent folder and both subprojects (`comparisons/`, `Missing Types/`).**

After any major change (new feature, bug fix, refactored function, new scenario, updated analysis), Claude MUST:

1. **Update script header** -- set `Last Updated: YYYY-MM-DD` in the modified file's metadata block.
2. **Append a session log entry** -- add one line to `quality_reports/session_logs/YYYY-MM-DD_description.md`:
   ```
   - [HH:MM] <file or folder> — <what changed and why>
   ```
   Create the file if it does not exist for today's date.

**Triggers (log any of these):**
- R script added, edited, or deleted
- Simulation scenario added or removed
- Analysis pipeline changed
- LaTeX manuscript section edited
- Figure generation updated
- Functions in `functions.R` modified

**Do not log:** trivial whitespace fixes, comment-only edits, or auto-generated output files.

---

## Current Project State

| Project | Location | Status | Key Content |
|---------|----------|--------|-------------|
| Comparisons | `comparisons/` | Active | ML method comparisons for recurrent events |
| Missing Types | `Missing Types/` | Active | Pseudo-observations with missing event types |
