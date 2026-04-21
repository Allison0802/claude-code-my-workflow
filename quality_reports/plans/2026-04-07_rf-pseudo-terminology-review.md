# RF Pseudo Paper — Terminology & Commentary Audit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Status:** APPROVED

**Goal:** Fix three categories of terminology and framing errors in `comparisons/Paper/RF pseudo.tex`, verified against the NotebookLM knowledge base for this paper.

**Architecture:** All fixes are in-place edits to a single `.tex` file. The `\rev{...}` (blue revision) passages contain the most issues. No structural changes — only targeted string replacements.

**File:** `comparisons/Paper/RF pseudo.tex`

---

## Audit Findings from NotebookLM

Three categories of errors, ordered by severity:

### A — Factually Incorrect Terminology (1 instance)
The simulation section calls the data "recurrent competing risks data." This is **wrong**: competing risks means one event type permanently precludes the others. Here, both Type 1 and Type 2 events can recur in the same subject — these are **multiple type recurrent events**, not competing risks.

### B — Inappropriate "AI" Framing (~15 instances, all in `\rev{}` blocks)
NotebookLM confirms: the source papers (Loe et al. 2024, 2025) consistently use **"machine learning"**, not "AI", "responsible AI deployment", "AI reliability", or "AI-based". The heavy "AI" framing in the revision markup is not standard in biostatistics methodology papers and misrepresents the statistical nature of the work.

### C — Misleading Description of Censoring (1 instance)
Censoring is described as "data imperfection inherent to observational longitudinal studies." This is **misleading**: censoring is a standard, defining feature of **all** survival data including RCTs — not an imperfection unique to observational studies.

---

## Task 1: Fix "competing risks" terminology in simulation

**File:** `comparisons/Paper/RF pseudo.tex` (line ~244)

- [ ] **Find and replace:** Change the only occurrence in the simulation data generation paragraph.

```
OLD:
We generated recurrent competing risks data using a frailty-based intensity model.

NEW:
We generated multiple type recurrent event data using a frailty-based intensity model.
```

- [ ] **Verify:** Search for any other instances of "competing risks" in the paper that describe the simulation setup (not the literature review). The literature review correctly names competing risks models from other papers — do not change those.

---

## Task 2: Fix "AI" framing — abstract and introduction

**File:** `comparisons/Paper/RF pseudo.tex`

### 2a — Abstract (line ~34)
- [ ] **Replace:**
```
OLD (in \rev{}):
AI-based dynamic risk prediction in chronic disease,

NEW:
machine learning–based dynamic risk prediction in chronic disease,
```
Note: "tree-based methods" in the same abstract sentence is already correct — do not touch it.

### 2b — Introduction, first AI mention (line ~44)
- [ ] **Replace:**
```
OLD:
AI-based dynamic risk prediction in chronic disease management.

NEW:
machine learning–based dynamic risk prediction in chronic disease management.
```

### 2c — Introduction, "responsible AI" (line ~50)
- [ ] **Replace:**
```
OLD:
advancing the statistical foundations for responsible AI in longitudinal real-world evidence generation.

NEW:
advancing the statistical foundations for responsible use of machine learning methods in longitudinal real-world evidence generation.
```

### 2d — Keywords
- [ ] **Replace** `artificial intelligence` in the keyword list with `machine learning`. This aligns with source paper conventions (the Loe et al. papers do not use "AI" as a keyword).

---

## Task 3: Fix "AI" framing — methods section (pseudo-observation paragraph)

**File:** `comparisons/Paper/RF pseudo.tex` (line ~105)

### 3a — "data imperfection" fix (also Category C)
- [ ] **Replace:**
```
OLD:
The pseudo-observation approach addresses this data imperfection inherent to observational longitudinal studies by constructing complete, unbiased outcome proxies via jackknife estimation, enabling standard AI regression tools to be applied to otherwise inaccessible censored survival outcomes.

NEW:
The pseudo-observation approach addresses this censoring challenge, which is inherent to all time-to-event data, by constructing complete, unbiased outcome proxies via jackknife estimation, enabling standard machine learning regression tools to be applied to otherwise inaccessible censored survival outcomes.
```

---

## Task 4: Fix "AI" framing — simulation study opening

**File:** `comparisons/Paper/RF pseudo.tex` (line ~238)

- [ ] **Replace:**
```
OLD:
\rev{To evaluate AI method reliability across the range of conditions encountered in real-world longitudinal registry studies,

NEW:
\rev{To evaluate the reliability of machine learning methods across the range of conditions encountered in real-world longitudinal registry studies,
```

---

## Task 5: Fix "AI" framing — discussion section

**File:** `comparisons/Paper/RF pseudo.tex` (lines ~596–626)

### 5a — "tree-based AI prediction methods" (line ~596)
- [ ] **Replace:**
```
OLD:
how to reliably apply tree-based AI prediction methods to the multi-type recurrent event processes

NEW:
how to reliably apply tree-based prediction methods to the multiple type recurrent event processes
```

### 5b — "AI for real-world evidence" (line ~596)
- [ ] **Replace:**
```
OLD:
In the context of AI for real-world evidence generation,

NEW:
In the context of machine learning for real-world evidence generation,
```

### 5c — "From an AI reliability perspective" (line ~602)
- [ ] **Replace:**
```
OLD:
\rev{From an AI reliability perspective,} a notable finding

NEW:
\rev{A notable finding
```
(The phrase adds no content; the sentence reads naturally without it.)

### 5d — "AI reliability assessment" (line ~602)
- [ ] **Replace:**
```
OLD:
This finding underscores the importance of AI reliability assessment---including systematic diagnostic checks for identifiability failures---before deploying AI-based prediction methods on real-world registry data where effective sample sizes per stratum may be limited.

NEW:
This finding underscores the importance of reliability assessment---including systematic diagnostic checks for identifiability failures---before deploying machine learning–based prediction methods on real-world registry data where effective sample sizes per stratum may be limited.
```

### 5e — "deploying AI prediction tools" (line ~608)
- [ ] **Replace:**
```
OLD:
These recommendations are motivated by the needs of practitioners deploying AI prediction tools in real-world clinical registry settings,

NEW:
These recommendations are motivated by the needs of practitioners deploying machine learning prediction tools in real-world clinical registry settings,
```

### 5f — "clinical AI applications" (line ~608)
- [ ] **Replace:**
```
OLD:
For clinical AI applications---such as monitoring uveitis flare risk in pediatric rheumatology---

NEW:
For clinical machine learning applications---such as monitoring uveitis flare risk in pediatric rheumatology---
```

### 5g — "individual-level AI predictions" (line ~612)
- [ ] **Replace:**
```
OLD:
uncertainty quantification (UQ) of individual-level AI predictions

NEW:
uncertainty quantification (UQ) of individual-level model predictions
```

### 5h — "patient-facing AI applications" / "responsible AI deployment" (line ~614)
- [ ] **Replace:**
```
OLD:
This is particularly important for patient-facing AI applications, where predicted probabilities outside $[0,1]$ could undermine clinical trust and create patient safety concerns; ensuring valid probabilistic outputs is a prerequisite for responsible AI deployment in healthcare.

NEW:
This is particularly important for patient-facing clinical decision support applications, where predicted probabilities outside $[0,1]$ could undermine clinical trust and create patient safety concerns; ensuring valid probabilistic outputs is a prerequisite for responsible deployment in healthcare.
```

### 5i — "AI capabilities" (line ~626)
- [ ] **Replace:**
```
OLD:
could enhance the AI capabilities of the pseudo-observation landmarking framework

NEW:
could enhance the predictive capabilities of the pseudo-observation landmarking framework
```

---

## Task 6: Verify no over-editing

- [ ] **Check** that all instances of "machine learning" already in the paper (e.g., in the introduction's ML paragraph) are untouched.
- [ ] **Check** that literature review references to competing risks methods (Holt and Prentice 1978, Andersen 2002) are NOT changed — those correctly describe the cited methods, not our setup.
- [ ] **Check** that "tree-based methods" and "random forest" occurrences are untouched.
- [ ] **Search** for any remaining "AI" occurrences to confirm none were missed: `grep -n "AI" "RF pseudo.tex"`

---

## Task 7: Compile and verify

- [ ] **Compile** the paper:
```bash
cd comparisons/Paper && TEXINPUTS=../../Preambles:$TEXINPUTS xelatex -interaction=nonstopmode "RF pseudo.tex"
```
- [ ] **Confirm** no LaTeX errors introduced by edits.
- [ ] **Skim** the compiled PDF at the changed locations to confirm readability.

---

## Task 8: Session log

- [ ] **Append** to `quality_reports/session_logs/2026-04-07_rf-pseudo-terminology-review.md`:
```
- [HH:MM] comparisons/Paper/RF pseudo.tex — Fixed 3 categories of terminology: (A) "competing risks" → "multiple type recurrent events" in simulation; (B) ~12 instances of "AI" → "machine learning" in \rev{} blocks; (C) "data imperfection inherent to observational studies" → accurate description of censoring as universal to survival data.
```

---

## Self-Review Checklist

- [x] Category A (competing risks): 1 fix in simulation paragraph — covered in Task 1.
- [x] Category B (AI framing): All ~12 instances across abstract, intro, methods, sim, discussion — covered in Tasks 2–5.
- [x] Category C (censoring description): 1 fix in pseudo-observation paragraph — covered in Task 3a (combined with 3a).
- [x] No placeholders — every old/new string is exact.
- [x] Keywords fix included (Task 2d).
- [x] Over-editing guard included (Task 6).
- [x] Compile verification included (Task 7).
