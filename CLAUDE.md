# CLAUDE.MD -- PhD Dissertation: ML for Recurrent Events

**Project:** ML Methods for Recurrent Events with Multiple Types
**Institution:** UNC Chapel Hill
**Branch:** main

---

## Core Principles

- **Plan first** -- enter plan mode before non-trivial tasks; save plans to `quality_reports/plans/`
- **Verify after** -- compile/render and confirm output at the end of every task
- **Reproducibility** -- `set.seed(YYYYMMDD)`, `here::here()` paths, all results replicable
- **Quality gates** -- nothing ships below 80/100
- **[LEARN] tags** -- when corrected, save `[LEARN:category] wrong → right` to MEMORY.md

---

## Folder Structure

```
Research/
├── CLAUDE.MD                    # This file
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

## Skills Quick Reference

| Command | What It Does |
|---------|-------------|
| `/compile-latex [file]` | 3-pass XeLaTeX + bibtex |
| `/proofread [file]` | Grammar/typo review |
| `/review-r [file]` | R code quality review |
| `/validate-bib` | Cross-reference citations |
| `/commit [msg]` | Stage, commit, PR, merge |
| `/lit-review [topic]` | Literature search + synthesis |
| `/research-ideation [topic]` | Research questions + strategies |
| `/interview-me [topic]` | Interactive research interview |
| `/review-paper [file]` | Manuscript review |
| `/data-analysis [dataset]` | End-to-end R analysis |

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

## Current Project State

| Project | Location | Status | Key Content |
|---------|----------|--------|-------------|
| Comparisons | `comparisons/` | Active | ML method comparisons for recurrent events |
| Missing Types | `Missing Types/` | Active | Pseudo-observations with missing event types |
