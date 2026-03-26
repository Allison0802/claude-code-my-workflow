# Plan: Adapt Workflow Configuration for PhD Dissertation

**Status:** DRAFT
**Date:** 2026-02-13

## Context

This repo uses the pedrohcgs/claude-code-my-workflow starter kit, designed for an economics course with Beamer slides. We need to adapt it for a PhD dissertation: **ML for Recurrent Events with Multiple Types** (survival analysis, UNC Chapel Hill). The repo has two sub-projects (`comparisons/`, `Missing Types/`) as separate git repos. The parent repo serves as shared config hub + home for new dissertation-level work.

**User decisions:**
- Scope: Research + papers (no teaching slides)
- Sub-projects: Hybrid model — separate repos, shared config from parent
- Colors: Neutral academic (colorblind-friendly, not institutional)
- Style: Structured, precise, rigorous, publication-ready visuals

---

## Changes (11 files + 1 new directory)

### 1. `CLAUDE.md` — Major rewrite
- Fill in: project name, UNC Chapel Hill, main branch
- Rewrite folder structure for research focus (add `Papers/`, de-emphasize `Slides/Quarto`)
- Replace slide commands with R simulation + LaTeX manuscript commands
- Trim skills table to research-relevant skills only
- Remove Beamer environments / Quarto CSS class tables (irrelevant)
- Replace lecture state table with dissertation projects table (`comparisons/`, `Missing Types/`)
- Add hybrid sub-project model documentation

### 2. `.claude/WORKFLOW_QUICK_REF.md` — Fill in all placeholders
- Non-negotiables: relative paths, `set.seed(YYYYMMDD)`, publication-ready figures (300 DPI, white bg), colorblind-friendly Okabe-Ito palette
- Preferences: Visual = polished/publication-ready; Reporting = concise bullets; Replication = strict

### 3. `.claude/rules/r-code-conventions.md` — Update palette + defaults
- Replace Emory palette with Okabe-Ito colorblind-friendly palette
- Update `theme_custom` for new colors
- Change `ggsave` defaults to `bg = "white"` (papers, not transparent slides)
- Add survival analysis R pitfalls (pseudo-obs edge cases, subject-level bootstrap)

### 4. `.claude/rules/knowledge-base-template.md` — Adapt for survival analysis
- Rename to "Dissertation Knowledge Base"
- Update path scoping to include `comparisons/**`, `Missing Types/**`, `Papers/**`
- Fill in notation registry: N(t), Y(t), λ(t), pseudo-observations, C-index, etc.
- Replace lecture tables with dissertation project + simulation study tables
- Add: Estimand Registry, DGP Configs, Tolerance Thresholds sections

### 5. `.claude/agents/domain-reviewer.md` — Customize 5 review lenses
1. Statistical correctness (estimands, pseudo-observation validity, asymptotic arguments)
2. Simulation design (DGP assumptions, sample sizes, scenario coverage, replication count)
3. ML methodology (train-test leakage, subject-level splitting, hyperparameters)
4. Missing data handling (MCAR/MAR assumptions, IPW correctness, weight diagnostics)
5. Results interpretation (C-index, competing risks nuances, relative efficiency)

### 6-9. Dormant slide-specific rules — Change path scoping
These rules are irrelevant for research-only work but preserved for future slides:
- `.claude/rules/beamer-quarto-sync.md` → scope to `_DORMANT_Slides/**`
- `.claude/rules/no-pause-beamer.md` → scope to `_DORMANT_Slides/**`
- `.claude/rules/single-source-of-truth.md` → scope to `_DORMANT_Slides/**`
- `.claude/rules/tikz-visual-quality.md` → keep for `Figures/**/*.tex` (TikZ in papers)

### 10. `.claude/rules/verification-protocol.md` — Adapt for research
- Remove slide-specific checks (Quarto rendering, SVG conversion)
- Add: R script execution verification, LaTeX manuscript compilation, results reproducibility

### 11. `MEMORY.md` — Initialize with project decisions
- Record all decisions from this session (scope, colors, conventions, hybrid model)

### 12. Create `Papers/` directory
- New directory for LaTeX manuscript chapters

---

## Verification
1. All `[BRACKETED]` placeholders replaced in CLAUDE.md
2. Dormant rules don't trigger on existing file paths
3. Each modified file internally consistent
4. `git diff` review of all changes
5. MEMORY.md captures session decisions

## Out of Scope (later)
- Sub-project CLAUDE.md updates to reference parent config
- Paper templates in `Papers/`
- Populating bibliography (protected by hook — user manages)
- New simulation infrastructure
