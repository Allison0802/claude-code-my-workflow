# RF Pseudo Paper — Biostatistics Special Collection Revision Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Status:** DRAFT

**Goal:** Revise `comparisons/Paper/RF pseudo.tex` for submission to *Biostatistics* special collection "Statistical Foundations of AI and Real-World Evidence Generation" — targeted framing adjustments only, no new content.

**Architecture:** The paper is already well-matched to the collection. Four targeted text edits align the framing with the collection's language (statistical foundations, RWE, reliability, pre-deployment diagnostics), plus one keyword addition. Scientific content and all "machine learning" terminology from the previous terminology audit are unchanged.

**File:** `comparisons/Paper/RF pseudo.tex`

---

## Background: Collection vs. Paper Alignment

The special collection calls for submissions on:
> "Statistical methods for developing or validating AI and ML models using RWD; approaches to address data imperfections; reliability and uncertainty quantification; fairness and transportability; monitoring and deployment."

| Collection Theme | Paper Status | Action Needed |
|-----------------|-------------|---------------|
| Statistical foundations for AI/ML using RWD | Present but framing implicit | Strengthen abstract + intro |
| Addressing data imperfections (censoring, heterogeneity, missingness) | Strong — §2.4 (methods), §5.4 (limitations) | No change |
| Reliability + failure-mode characterization | Strong — §6 (Stratified MERF failure, §602) | Strengthen intro contribution statement |
| Transportability and fairness | Present — limitations §618 | No change |
| Monitoring / deployment | Present — future work §626 | No change |
| UQ of individual predictions | Gap correctly acknowledged §612 | No change (future work) |
| **Keywords** | "artificial intelligence" absent | Add keyword |

**Critical constraint:** The previous session (2026-04-07) correctly replaced ~21 inflated "AI" instances with "machine learning" throughout the paper. Do NOT re-add "AI" to scientific content (methods, results, discussion body). The only "AI" addition is in keywords, where it is appropriate as the collection's primary search term. The previous session's fixes stand.

---

## Task 1: Add "artificial intelligence" to keywords

**File:** `comparisons/Paper/RF pseudo.tex` (line 38)

The collection is titled "Statistical Foundations of **AI** and Real-World Evidence Generation." Adding "artificial intelligence" to keywords ensures discoverability and signals alignment to the editorial office.

- [ ] **Edit keywords line:**

```
OLD:
\noindent\textbf{Keywords:} machine learning; dynamic prediction; mixed-effects models; multiple event types; pseudo-observations; random forest; real-world evidence; recurrent events.

NEW:
\noindent\textbf{Keywords:} artificial intelligence; dynamic prediction; machine learning; mixed-effects models; multiple event types; pseudo-observations; random forest; real-world evidence; recurrent events.
```

---

## Task 2: Abstract — explicit "RWE" and "statistical foundations" framing

**File:** `comparisons/Paper/RF pseudo.tex` (line 34)

The abstract's opening sentence mentions "machine learning–based dynamic risk prediction" but does not use the collection's "real-world evidence (RWE)" or "statistical foundations" language. These are the first words an editor reads.

- [ ] **Edit abstract opening `\rev{}` block — change only the subordinate clause:**

```
OLD:
\rev{Longitudinal patient registries offer growing opportunities for machine learning--based dynamic risk prediction in chronic disease, yet the statistical challenges of recurrent, multi-type event processes remain underexplored in this context.}

NEW:
\rev{Longitudinal patient registries offer growing opportunities for machine learning--based dynamic risk prediction in chronic disease, yet rigorous statistical foundations for applying these methods to recurrent, multi-type event processes in real-world evidence (RWE) settings remain underdeveloped.}
```

Rationale: "underexplored in this context" → "underdeveloped in RWE settings" surfaces both collection themes (statistical foundations + RWE) in the first sentence.

---

## Task 3: Introduction — name "statistical foundations" in the RWE paragraph

**File:** `comparisons/Paper/RF pseudo.tex` (line 44)

The second `\rev{}` block describes observational data challenges but its closing sentence is generic. Adding "statistical foundations" language makes the connection to the collection explicit.

- [ ] **Edit closing sentence of the second `\rev{}` block in §1:**

```
OLD:
Establishing which methods remain reliable under these conditions requires systematic evaluation across a broad range of realistic data scenarios.

NEW:
Establishing which methods remain statistically valid and reliable under these conditions---and characterizing their failure modes before deployment---requires systematic evaluation across a broad range of realistic data scenarios, and constitutes a direct contribution to the statistical foundations for machine learning applied to real-world evidence generation.
```

---

## Task 4: Introduction — strengthen contribution statement with "pre-deployment diagnostics"

**File:** `comparisons/Paper/RF pseudo.tex` (line 50)

The final `\rev{}` block in the introduction currently says "advancing the statistical foundations for responsible use of machine learning methods." Adding "pre-deployment diagnostic criteria" makes the reliability contribution concrete and directly maps to the collection's reliability/deployment theme.

- [ ] **Edit the final `\rev{}` block in the introduction:**

```
OLD:
\rev{We additionally document a systematic reliability failure of the Stratified MERF and demonstrate the approach on real-world registry data, advancing the statistical foundations for responsible use of machine learning methods in longitudinal real-world evidence generation.}

NEW:
\rev{We additionally document a systematic reliability failure of the Stratified MERF---including empirical diagnostic criteria for identifying pre-deployment identifiability failures based on event-free proportion and effective sample size---and demonstrate the approach on real-world registry data, advancing the statistical foundations for reliable and responsible deployment of machine learning methods in longitudinal real-world evidence generation.}
```

---

## Task 5: Compile and verify

- [ ] **Compile the paper (single-pass sufficient for text-only edits):**

```bash
cd "comparisons/Paper" && TEXINPUTS=../../Preambles:$TEXINPUTS xelatex -interaction=nonstopmode "RF pseudo.tex" 2>&1 | tail -5
```

- [ ] **Confirm** no LaTeX errors (exit status 0, no `!` error lines in output).
- [ ] **Verify** output: 23 pages, 0 errors. (If page count changes, inspect for runaway lines.)
- [ ] **Full 3-pass compile** only if cross-references need updating:

```bash
cd "comparisons/Paper"
TEXINPUTS=../../Preambles:$TEXINPUTS xelatex -interaction=nonstopmode "RF pseudo.tex"
BIBINPUTS=..:$BIBINPUTS bibtex "RF pseudo"
TEXINPUTS=../../Preambles:$TEXINPUTS xelatex -interaction=nonstopmode "RF pseudo.tex"
TEXINPUTS=../../Preambles:$TEXINPUTS xelatex -interaction=nonstopmode "RF pseudo.tex"
```

---

## Task 6: Session log

- [ ] **Create** `quality_reports/session_logs/2026-04-08_rf-pseudo-special-collection-revision.md` with:

```
# Session Log — RF Pseudo Special Collection Revision

**Date:** 2026-04-08
**Branch:** main

## Summary

Targeted framing revision of `comparisons/Paper/RF pseudo.tex` for submission to
*Biostatistics* special collection "Statistical Foundations of AI and Real-World
Evidence Generation."

## Changes

- [HH:MM] `comparisons/Paper/RF pseudo.tex` — 4 framing edits + 1 keyword addition:
  - **(Keywords):** Added "artificial intelligence" (collection's primary term).
  - **(Abstract):** "underexplored in this context" → "underdeveloped in real-world
    evidence (RWE) settings" — surfaces both collection themes in sentence 1.
  - **(Intro §1 RWE paragraph):** Closing sentence strengthened to explicitly name
    "statistical foundations for machine learning applied to real-world evidence
    generation."
  - **(Intro §1 contribution statement):** Added "empirical diagnostic criteria for
    pre-deployment identifiability failures" to the Stratified MERF reliability
    sentence.
  - Scientific content unchanged; "machine learning" terminology from 2026-04-07
    audit preserved throughout.

## Result

- Compiles clean: 23 pages, no errors.
- Paper framing explicitly aligned with 4 collection themes: statistical foundations,
  RWE, pre-deployment reliability diagnostics, responsible deployment.
```

---

## Self-Review Checklist

- [x] Keywords: "artificial intelligence" added — collection's primary language.
- [x] Abstract: "statistical foundations" + "RWE settings" in sentence 1.
- [x] Introduction: "statistical foundations for machine learning applied to RWE" named.
- [x] Contribution statement: "pre-deployment diagnostic criteria" named.
- [x] Scientific content unchanged: no "AI" added back to methods/results/discussion.
- [x] All OLD strings are exact matches from the current file (verified from line reads).
- [x] Compile verification included.
- [x] No placeholders, no TBDs.
- [x] Prior terminology audit (2026-04-07) is respected throughout.
