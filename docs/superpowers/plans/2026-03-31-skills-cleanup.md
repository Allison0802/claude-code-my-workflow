# Skills Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reduce `.claude/skills/` from 164 skills to ~64 by deleting LLM-irrelevant skills, archiving dormant slide skills, adding 2 missing auto-claude skills, and fixing 5 stale project-specific skill descriptions.

**Architecture:** Pure file system operations (cp, mv, rm -rf) plus targeted in-place edits to 5 SKILL.md files. No code compilation or tests — verification is via `ls` / `grep` commands. All paths relative to project root: `/Users/alison/Library/CloudStorage/OneDrive-UniversityofNorthCarolinaatChapelHill/Research/`

**Tech Stack:** Bash, Edit tool for SKILL.md changes.

**Spec:** `docs/superpowers/specs/2026-03-30-skills-cleanup-design.md`

---

### Task 1: Check formula-derivation and proof-writer overlap

Both exist in auto-claude source AND in `.claude/skills/`. Verify whether the project copies differ from the auto-claude source before later tasks overwrite them.

**Files:**
- Read: `.claude/skills/formula-derivation/SKILL.md`
- Read: `Auto-claude-code-research-in-sleep/skills/formula-derivation/SKILL.md`
- Read: `.claude/skills/proof-writer/SKILL.md`
- Read: `Auto-claude-code-research-in-sleep/skills/proof-writer/SKILL.md`

- [ ] **Step 1: Diff formula-derivation**

```bash
diff .claude/skills/formula-derivation/SKILL.md \
     Auto-claude-code-research-in-sleep/skills/formula-derivation/SKILL.md
```

Expected: If output is empty, files are identical — no action needed. If there are differences, note which version is more complete/project-specific (the `.claude/skills/` version likely has project-specific content and should be kept as-is).

- [ ] **Step 2: Diff proof-writer**

```bash
diff .claude/skills/proof-writer/SKILL.md \
     Auto-claude-code-research-in-sleep/skills/proof-writer/SKILL.md
```

Expected: Same as above — keep whichever is more complete/project-specific.

- [ ] **Step 3: Commit note** (no file changes unless diffs revealed issues)

If identical: no commit needed. If project version is superior: add a comment to this plan's task marking "project version kept — do not overwrite."

---

### Task 2: Add 2 missing auto-claude skills

**Files:**
- Create: `.claude/skills/semantic-scholar/` (copy from source)
- Create: `.claude/skills/vast-gpu/` (copy from source)

- [ ] **Step 1: Copy semantic-scholar**

```bash
cp -r "Auto-claude-code-research-in-sleep/skills/semantic-scholar" \
      ".claude/skills/semantic-scholar"
```

- [ ] **Step 2: Copy vast-gpu**

```bash
cp -r "Auto-claude-code-research-in-sleep/skills/vast-gpu" \
      ".claude/skills/vast-gpu"
```

- [ ] **Step 3: Verify both were added**

```bash
ls .claude/skills/semantic-scholar/
ls .claude/skills/vast-gpu/
```

Expected: Each shows `SKILL.md` (and any supporting files).

- [ ] **Step 4: Commit**

```bash
git add .claude/skills/semantic-scholar .claude/skills/vast-gpu
git commit -m "feat: add missing auto-claude skills (semantic-scholar, vast-gpu)"
```

---

### Task 3: Archive dormant slide skills

**Files:**
- Create: `.claude/skills/_DORMANT/` directory
- Move: 9 slide-workflow skills into `_DORMANT/`

- [ ] **Step 1: Create _DORMANT directory**

```bash
mkdir -p .claude/skills/_DORMANT
```

- [ ] **Step 2: Move all 9 dormant skills**

```bash
cd .claude/skills && mv \
  translate-to-quarto \
  create-lecture \
  slide-excellence \
  qa-quarto \
  pedagogy-review \
  extract-tikz \
  deploy \
  visual-audit \
  devils-advocate \
  _DORMANT/
```

- [ ] **Step 3: Verify archive**

```bash
ls .claude/skills/_DORMANT/
```

Expected output (9 directories):
```
create-lecture  deploy  devils-advocate  extract-tikz  pedagogy-review
qa-quarto  slide-excellence  translate-to-quarto  visual-audit
```

- [ ] **Step 4: Commit**

```bash
git add -A .claude/skills/
git commit -m "chore: archive dormant slide-workflow skills to _DORMANT/"
```

---

### Task 4: Delete LLM-specific skills (~70 skills)

**Files:** Remove ~70 directories from `.claude/skills/`

- [ ] **Step 1: Delete all LLM-specific skills**

```bash
cd .claude/skills && rm -rf \
  gptq awq gguf hqq bitsandbytes \
  vllm sglang tensorrt-llm llama-cpp \
  deepspeed accelerate trl-fine-tuning llama-factory axolotl unsloth peft \
  openrlhf grpo-rl-training simpo torchtitan megatron-core pytorch-fsdp2 moe-training \
  mamba rwkv nanogpt llava blip-2 \
  langchain llamaindex dspy guidance outlines instructor crewai autogpt langsmith phoenix \
  transformer-lens nnsight saelens pyvene \
  llamaguard prompt-guard constitutional-ai nemo-guardrails nemo-curator nemo-evaluator \
  lm-evaluation-harness bigcode-evaluation-harness \
  sentence-transformers sentencepiece huggingface-tokenizers whisper \
  stable-diffusion segment-anything clip audiocraft \
  chroma faiss pinecone qdrant \
  modal lambda-labs skypilot \
  long-context flash-attention speculative-decoding litgpt miles \
  model-merging model-pruning knowledge-distillation slime verl
```

- [ ] **Step 2: Verify none remain**

```bash
ls .claude/skills/ | grep -E \
  "^(gptq|awq|gguf|vllm|deepspeed|trl-fine-tuning|langchain|llamaindex|dspy|stable-diffusion|whisper|faiss|modal|litgpt|transformer-lens)$"
```

Expected: no output (empty).

- [ ] **Step 3: Commit**

```bash
git add -A .claude/skills/
git commit -m "chore: delete LLM-specific skills (quantization, serving, fine-tuning, agents, vision, audio)"
```

---

### Task 5: Delete document-bundle duplicates and misc irrelevant skills

**Files:** Remove ~18 directories from `.claude/skills/`

- [ ] **Step 1: Delete document-bundle duplicates**

These are available globally from the `document-skills@anthropic-agent-skills` plugin — no functionality lost.

```bash
cd .claude/skills && rm -rf \
  algorithmic-art brand-guidelines canvas-design doc-coauthoring docx \
  frontend-design internal-comms mcp-builder pdf pptx \
  skill-creator slack-gif-creator theme-factory web-artifacts-builder \
  webapp-testing xlsx
```

- [ ] **Step 2: Delete misc irrelevant extras**

```bash
cd .claude/skills && rm -rf 20-ml-paper-writing humanizer
```

- [ ] **Step 3: Verify skill count is in the right range**

```bash
ls .claude/skills/ | grep -v "_DORMANT" | wc -l
```

Expected: approximately 64 (±2). If significantly higher, check for unexpected survivors.

- [ ] **Step 4: Verify document-skills still available globally**

```bash
ls ~/.claude/skills/ | grep -E "brand-guidelines|canvas-design|docx"
```

Expected: those directories present in the global plugin cache.

- [ ] **Step 5: Commit**

```bash
git add -A .claude/skills/
git commit -m "chore: delete document-bundle duplicates and misc irrelevant skills"
```

> Note: all deleted document skills remain available globally via `~/.claude/skills/` from the `document-skills@anthropic-agent-skills` plugin.

---

### Task 6: Fix compile-latex — update for manuscripts

**Files:**
- Modify: `.claude/skills/compile-latex/SKILL.md`

- [ ] **Step 1: Update frontmatter description**

In `.claude/skills/compile-latex/SKILL.md`, change:

```
description: Compile a Beamer LaTeX slide deck with XeLaTeX (3 passes + bibtex). Use when compiling lecture slides.
```

To:

```
description: Compile a LaTeX document with XeLaTeX (3 passes + bibtex). Use for manuscripts in Papers/ or slide decks in Slides/.
```

- [ ] **Step 2: Update title and intro**

Change:

```markdown
# Compile Beamer LaTeX Slides

Compile a Beamer slide deck using XeLaTeX with full citation resolution.
```

To:

```markdown
# Compile LaTeX Documents

Compile a LaTeX manuscript or slide deck using XeLaTeX with full citation resolution.
```

- [ ] **Step 3: Update Step 1 to support both Papers/ and Slides/**

Change:

```markdown
1. **Navigate to Slides/ directory** and compile with 3-pass sequence:

```bash
cd Slides
TEXINPUTS=../Preambles:$TEXINPUTS xelatex -interaction=nonstopmode $ARGUMENTS.tex
BIBINPUTS=..:$BIBINPUTS bibtex $ARGUMENTS
TEXINPUTS=../Preambles:$TEXINPUTS xelatex -interaction=nonstopmode $ARGUMENTS.tex
TEXINPUTS=../Preambles:$TEXINPUTS xelatex -interaction=nonstopmode $ARGUMENTS.tex
```
```

To:

```markdown
1. **Determine target directory** (`Papers/` for manuscripts, `Slides/` for slide decks) and compile with 3-pass sequence:

**For manuscripts (Papers/):**
```bash
cd Papers
TEXINPUTS=../Preambles:$TEXINPUTS xelatex -interaction=nonstopmode $ARGUMENTS.tex
BIBINPUTS=..:$BIBINPUTS bibtex $ARGUMENTS
TEXINPUTS=../Preambles:$TEXINPUTS xelatex -interaction=nonstopmode $ARGUMENTS.tex
TEXINPUTS=../Preambles:$TEXINPUTS xelatex -interaction=nonstopmode $ARGUMENTS.tex
```

**For slide decks (Slides/):**
```bash
cd Slides
TEXINPUTS=../Preambles:$TEXINPUTS xelatex -interaction=nonstopmode $ARGUMENTS.tex
BIBINPUTS=..:$BIBINPUTS bibtex $ARGUMENTS
TEXINPUTS=../Preambles:$TEXINPUTS xelatex -interaction=nonstopmode $ARGUMENTS.tex
TEXINPUTS=../Preambles:$TEXINPUTS xelatex -interaction=nonstopmode $ARGUMENTS.tex
```
```

- [ ] **Step 4: Update the open PDF step**

Change:

```markdown
3. **Open the PDF** for visual verification:
   ```bash
   open Slides/$ARGUMENTS.pdf
   ```
```

To:

```markdown
3. **Open the PDF** for visual verification:
   ```bash
   open Papers/$ARGUMENTS.pdf   # for manuscripts
   open Slides/$ARGUMENTS.pdf   # for slides
   ```
```

- [ ] **Step 5: Verify the change**

```bash
grep "description:" .claude/skills/compile-latex/SKILL.md
```

Expected: `description: Compile a LaTeX document with XeLaTeX (3 passes + bibtex). Use for manuscripts in Papers/ or slide decks in Slides/.`

- [ ] **Step 6: Commit**

```bash
git add .claude/skills/compile-latex/SKILL.md
git commit -m "fix: update compile-latex to support Papers/ manuscripts, not just Slides/"
```

---

### Task 7: Fix proofread — extend scope to manuscripts

**Files:**
- Modify: `.claude/skills/proofread/SKILL.md`

- [ ] **Step 1: Update frontmatter description**

Change:

```
description: Run the proofreading protocol on lecture files. Checks grammar, typos, overflow, consistency, and academic writing quality. Produces a report without editing files.
```

To:

```
description: Run the proofreading protocol on manuscripts and documents. Checks grammar, typos, overflow, consistency, and academic writing quality. Produces a report without editing files.
```

- [ ] **Step 2: Update title and intro**

Change:

```markdown
# Proofread Lecture Files

Run the mandatory proofreading protocol on lecture files.
```

To:

```markdown
# Proofread Manuscripts and Documents

Run the mandatory proofreading protocol on manuscripts and lecture files.
```

- [ ] **Step 3: Add Papers/*.tex as scan target in Step 1**

Change:

```markdown
   - If `$ARGUMENTS` is "all": review all lecture files in `Slides/` and `Quarto/`
```

To:

```markdown
   - If `$ARGUMENTS` is "all": review all documents in `Papers/`, `Slides/`, and `Quarto/`
```

- [ ] **Step 4: Update the report save step**

Change:

```markdown
4. **Save each report** to `quality_reports/`:
   - For `.tex` files: `quality_reports/FILENAME_report.md`
   - For `.qmd` files: `quality_reports/FILENAME_qmd_report.md`
```

To:

```markdown
4. **Save each report** to `quality_reports/`:
   - For `.tex` files (manuscripts or slides): `quality_reports/FILENAME_report.md`
   - For `.qmd` files: `quality_reports/FILENAME_qmd_report.md`
```

- [ ] **Step 5: Verify**

```bash
grep "description:" .claude/skills/proofread/SKILL.md
```

Expected: `description: Run the proofreading protocol on manuscripts and documents. ...`

- [ ] **Step 6: Commit**

```bash
git add .claude/skills/proofread/SKILL.md
git commit -m "fix: extend proofread scope to Papers/ manuscripts, not just Slides/"
```

---

### Task 8: Fix validate-bib — add Papers/ scan target

**Files:**
- Modify: `.claude/skills/validate-bib/SKILL.md`

- [ ] **Step 1: Add Papers/*.tex to the Files to scan section**

Change:

```markdown
## Files to scan:
```
Slides/*.tex
Quarto/*.qmd
```
```

To:

```markdown
## Files to scan:
```
Papers/*.tex
Slides/*.tex
Quarto/*.qmd
```
```

- [ ] **Step 2: Verify**

```bash
grep -A4 "Files to scan" .claude/skills/validate-bib/SKILL.md
```

Expected output includes `Papers/*.tex` before `Slides/*.tex`.

- [ ] **Step 3: Commit**

```bash
git add .claude/skills/validate-bib/SKILL.md
git commit -m "fix: add Papers/*.tex to validate-bib scan targets"
```

---

### Task 9: Fix review-paper — replace econometrics framing with biostatistics

**Files:**
- Modify: `.claude/skills/review-paper/SKILL.md`

- [ ] **Step 1: Update frontmatter description**

Change:

```
description: Comprehensive manuscript review covering argument structure, econometric specification, citation completeness, and potential referee objections
```

To:

```
description: Comprehensive manuscript review covering argument structure, statistical methodology, citation completeness, and potential referee objections
```

- [ ] **Step 2: Rename and rewrite Dimension 2**

Change:

```markdown
### 2. Identification Strategy
- Is the causal claim credible?
- What are the key identifying assumptions? Are they stated explicitly?
- Are there threats to identification (omitted variables, reverse causality, measurement error)?
- Are robustness checks adequate?
- Is the estimator appropriate for the research design?
```

To:

```markdown
### 2. Statistical Methodology
- Is the statistical method appropriate for the research question and data structure?
- Are the key model assumptions stated explicitly (e.g., independent censoring, positivity, MAR)?
- Are threats to validity addressed (model misspecification, informative censoring, unmeasured confounding)?
- Are sensitivity analyses or robustness checks adequate?
- Is the estimator appropriate for the data structure (recurrent events, competing risks, missing data)?
```

- [ ] **Step 3: Rename and rewrite Dimension 3**

Change:

```markdown
### 3. Econometric Specification
- Correct standard errors (clustered? robust? bootstrap?)?
- Appropriate functional form?
- Sample selection issues?
- Multiple testing concerns?
- Are point estimates economically meaningful (not just statistically significant)?
```

To:

```markdown
### 3. Estimation Approach
- Correct variance estimation (sandwich estimator, jackknife, bootstrap)?
- Appropriate functional form and link function?
- Sample or simulation scenario selection issues?
- Multiple comparison concerns?
- Are point estimates clinically or practically meaningful (not just statistically significant)?
```

- [ ] **Step 4: Update the Summary Statistics output table**

Change:

```markdown
| Argument Structure | [N] |
| Identification | [N] |
| Econometrics | [N] |
```

To:

```markdown
| Argument Structure | [N] |
| Statistical Methodology | [N] |
| Estimation Approach | [N] |
```

- [ ] **Step 5: Verify**

```bash
grep -E "Econometric|Identification Strategy" .claude/skills/review-paper/SKILL.md
```

Expected: no output (both terms removed).

```bash
grep -E "Statistical Methodology|Estimation Approach" .claude/skills/review-paper/SKILL.md
```

Expected: 3 matches (heading, table row, and section title).

- [ ] **Step 6: Commit**

```bash
git add .claude/skills/review-paper/SKILL.md
git commit -m "fix: reframe review-paper from econometrics to biostatistics/survival analysis"
```

---

### Task 10: Fix data-analysis — reframe from panel econometrics to survival/simulation

**Files:**
- Modify: `.claude/skills/data-analysis/SKILL.md`

- [ ] **Step 1: Update frontmatter description and argument hint**

Change:

```
description: End-to-end R data analysis workflow from exploration through regression to publication-ready tables and figures
argument-hint: "[dataset path or description of analysis goal]"
```

To:

```
description: End-to-end R data analysis workflow for survival data or simulation output — from exploration through modeling to publication-ready tables and figures
argument-hint: "[dataset path, simulation results path, or description of analysis goal (e.g., 'summarize bias/coverage for IPW estimator')]"
```

- [ ] **Step 2: Update Phase 3 Main Analysis**

Change:

```markdown
### Phase 3: Main Analysis

Based on the research question:
- **Regression analysis:** Use `fixest` for panel data, `lm`/`glm` for cross-section
- **Standard errors:** Cluster at the appropriate level (document why)
- **Multiple specifications:** Start simple, progressively add controls
- **Effect sizes:** Report standardized effects alongside raw coefficients
```

To:

```markdown
### Phase 3: Main Analysis

Based on the research question:
- **Survival analysis:** Use `survival::coxph()` for Cox models, `survival::survfit()` for KM curves, `cmprsk` for competing risks
- **Simulation summaries:** Compute bias, empirical SE, SE ratio, RMSE, coverage across Monte Carlo replications
- **Multiple specifications:** Start simple, progressively add complexity (frailty, strata, time-varying covariates)
- **Effect sizes:** Report hazard ratios with confidence intervals; for simulation, report relative bias (%)
```

- [ ] **Step 3: Update Phase 4 Tables section**

Change:

```markdown
- Use `modelsummary` for regression tables (preferred) or `stargazer`
- Include all standard elements: coefficients, SEs, significance stars, N, R-squared
- Export as `.tex` for LaTeX inclusion and `.html` for quick viewing
```

To:

```markdown
- Use `knitr::kable()` or `gt` for summary tables
- For Cox models: include HRs, 95% CIs, p-values, N, events, concordance index
- For simulation: include bias, SE ratio, RMSE, coverage columns per scenario
- Export as `.tex` for LaTeX inclusion
```

- [ ] **Step 4: Update the script structure template**

Change:

```r
library(tidyverse)
library(fixest)
library(modelsummary)

set.seed(42)
```

To:

```r
library(tidyverse)
library(survival)
library(here)

set.seed(20240101)  # use YYYYMMDD format per project convention
```

- [ ] **Step 5: Update the argument example in the Important section**

Change:

```markdown
- **Reproduce, don't guess.** If the user specifies a regression, run exactly that.
```

Leave this line unchanged — it applies equally.

Change any reference to "CPS data", "wages", or "state fixed effects":

```markdown
**Input:** `$ARGUMENTS` — a dataset path (e.g., `data/county_panel.csv`) or a description of the analysis goal (e.g., "regress wages on education with state fixed effects using CPS data").
```

To:

```markdown
**Input:** `$ARGUMENTS` — a dataset path (e.g., `data/recurrent_events.rds`) or a description of the analysis goal (e.g., "summarize bias and coverage for the IPW estimator across 37 simulation scenarios").
```

- [ ] **Step 6: Verify econometrics terms are gone**

```bash
grep -iE "fixest|modelsummary|wages|CPS|panel data|fixed effects|clustered" \
  .claude/skills/data-analysis/SKILL.md
```

Expected: no output.

- [ ] **Step 7: Commit**

```bash
git add .claude/skills/data-analysis/SKILL.md
git commit -m "fix: reframe data-analysis from panel econometrics to survival/simulation R workflow"
```

---

### Task 11: Update CLAUDE.md skill quick reference

**Files:**
- Modify: `CLAUDE.md`

The dormant skills section in CLAUDE.md currently notes slide skills as dormant. Update it to also mention they are now physically archived in `_DORMANT/`.

- [ ] **Step 1: Find the dormant mention in CLAUDE.md**

```bash
grep -n "Dormant\|dormant\|_DORMANT\|translate-to-quarto\|create-lecture" CLAUDE.md
```

Note the line numbers.

- [ ] **Step 2: Update the dormant section**

Find the existing dormant note (should be near the Scientific Skills section):

```markdown
**Dormant** (slide/teaching focused — reactivate for defense or job talk):
`create-lecture`, `pedagogy-review`, `slide-excellence`, `translate-to-quarto`, `qa-quarto`, `extract-tikz`
```

Update to:

```markdown
**Dormant** (slide/teaching focused — archived to `.claude/skills/_DORMANT/`, reactivate by moving back for defense or job talk):
`create-lecture`, `pedagogy-review`, `slide-excellence`, `translate-to-quarto`, `qa-quarto`, `extract-tikz`, `deploy`, `visual-audit`, `devils-advocate`
```

- [ ] **Step 3: Verify**

```bash
grep -A2 "Dormant" CLAUDE.md
```

Expected: updated line with `_DORMANT/` path and all 9 skills listed.

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md to reflect _DORMANT/ archive and 9 dormant skills"
```

---

### Task 12: Final verification

- [ ] **Step 1: Check total active skill count**

```bash
ls .claude/skills/ | grep -v "_DORMANT" | wc -l
```

Expected: ~64 (acceptable range: 60–68).

- [ ] **Step 2: Confirm all auto-claude skills present**

```bash
comm -23 \
  <(ls Auto-claude-code-research-in-sleep/skills/ | sort) \
  <(ls .claude/skills/ | grep -v _DORMANT | sort)
```

Expected: empty output (all 47 auto-claude skills are present).

- [ ] **Step 3: Confirm no LLM framework skills remain**

```bash
ls .claude/skills/ | grep -E \
  "^(vllm|sglang|deepspeed|trl-fine-tuning|llama-factory|axolotl|peft|langchain|llamaindex|dspy|stable-diffusion|whisper|faiss|chroma|modal|gptq|awq|gguf|transformer-lens|nnsight|saelens)$"
```

Expected: empty output.

- [ ] **Step 4: Confirm _DORMANT has exactly 9 skills**

```bash
ls .claude/skills/_DORMANT/ | wc -l
```

Expected: 9.

- [ ] **Step 5: Spot-check 5 fixed skills**

```bash
grep "description:" \
  .claude/skills/compile-latex/SKILL.md \
  .claude/skills/proofread/SKILL.md \
  .claude/skills/validate-bib/SKILL.md \
  .claude/skills/review-paper/SKILL.md \
  .claude/skills/data-analysis/SKILL.md
```

Expected:
```
compile-latex: ...Use for manuscripts in Papers/ or slide decks in Slides/.
proofread: ...manuscripts and documents...
validate-bib: ...Validate bibliography entries...  (description unchanged — check Papers/*.tex is in Files to scan instead)
review-paper: ...statistical methodology...
data-analysis: ...survival data or simulation output...
```

- [ ] **Step 6: Write session log entry**

Append to `quality_reports/session_logs/2026-03-31_skills-cleanup.md`:

```markdown
- [HH:MM] .claude/skills/ — Cleaned up from 164 to ~64 skills: deleted ~70 LLM-specific, ~16 document-bundle duplicates, archived 9 dormant slide skills to _DORMANT/, added semantic-scholar and vast-gpu, fixed 5 stale project-specific skill descriptions
```

- [ ] **Step 7: Final commit**

```bash
git add quality_reports/session_logs/2026-03-31_skills-cleanup.md
git commit -m "docs: add session log for skills cleanup"
```
