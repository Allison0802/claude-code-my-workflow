# Session Log: 2026-04-11 -- RF pseudo.tex Reframing for Biostatistics AI+RWE Special Collection

**Status:** COMPLETED

## Objective

Reframe `comparisons/Paper/RF pseudo.tex` for the *Biostatistics* Special Collection on "Statistical Foundations of AI and Real-World Evidence Generation." De-emphasize the "Stratified vs. Joint" horse-race framing and elevate the landmark pseudo-observation pipeline as a general AI/ML-for-RWD tool, while explicitly NOT claiming the landmark pseudo-observation framework as a novel contribution (Andersen et al. 2003, 2010 introduced it; Loe et al. 2025 integrated with RF). Run `/auto-paper-improvement-loop` with HUMAN_CHECKPOINT=true, max_round=4.

## Changes Made

| File | Change | Reason | Quality Score |
|------|--------|--------|---|
| `comparisons/Paper/RF pseudo.tex` | Round 1: title, abstract, intro, methods preamble, discussion reframed; +9 new citations; semi-formal MERF identifiability analysis added | Fix C1 misalignment with special collection scope; never claim LM-PO as novel per user instruction | 5 → 6.5 / 10 |
| `comparisons/Paper/RF pseudo.tex` | Round 2: softened "systematic" → "focused"; delimited MERF generalization; qualified model-agnosticism; removed unsubstantiated "Joint RF miscalibrated" claim; reduced contributions 4→3; EFP formally defined; sex/race stratification asymmetry clarified | Fix R2 review: rhetoric/content mismatch, asymmetric verbs, overclaim of calibration | 6.5 → 7.0 / 10 |
| `comparisons/Paper/RF pseudo.tex` | Round 3: title → "Evaluating Pseudo-Observation Random Forests..."; explicit "what we do NOT deliver" scope in abstract; calibration deferral rationale; Bayesian speculation removed; operational backend check added; EFP reframed positively | Fix R3 review: attribution safety, honest scoping, remove speculative hedges | 7.0 → 7.5 / 10 |
| `comparisons/Paper/RF pseudo.tex` | Round 4: typo fix ("attenuat ing"); MERF "extend" → "additionally evaluate"; narrowed scope of provisional claim; CARRA-simulation bridging sentence; "architectural hooks" metaphor; abstract deferral explained as publishing strategy | Final polish per R4 review (no CRITICAL issues remained) | 7.5 / 10 |
| `comparisons/Paper/RF pseudo.tex` | Post-R4: removed "what this paper does NOT deliver" sentence from abstract; softened Limitations calibration language from "companion deployment study in preparation" to "natural next steps for follow-up work" | User request: avoid committing to a vapor companion paper; keep honesty in Limitations only | 7.5 / 10 |
| `comparisons/Paper/PAPER_IMPROVEMENT_LOG.md` | Full 4-round improvement log written | Document score progression and fix list for future reference | -- |
| `comparisons/Paper/PAPER_IMPROVEMENT_STATE.json` | State finalized: status=completed, last_score=7.5 | End-of-session persistence | -- |
| `comparisons/Paper/RF pseudo_round{1,2,3}_biostat_rwe.pdf` | Round-by-round PDF snapshots saved | Enable progression comparison | -- |
| `comparisons/Paper/RF pseudo_round4_final_biostat_rwe.pdf` | Final submission-candidate PDF | End state of the auto-improvement loop | -- |

## Design Decisions

| Decision | Alternatives Considered | Rationale |
|----------|------------------------|-----------|
| Title: "Evaluating Pseudo-Observation Random Forests for..." | Option A ("Pseudo-Observation Random Forests for..."), Option B ("Dynamic Prediction of Multi-Type... with Pseudo-Observation Forests"), Option C ("Machine Learning for...") | R3 reviewer flagged "with Pseudo-Observation Forests" as subtly implying authorship. "Evaluating..." makes the non-claim explicit without losing the RWD hook. |
| Drop "architecturally supported but not empirically validated" sentence from abstract | Keep it as a defensive hedge | User preference: tighter abstract, no implicit commitment to companion paper, honesty lives in Limitations instead. R4 reviewer flagged "companion deployment paper" as a hard constraint — removing the sentence removes that risk. |
| Do NOT run new SLURM experiments (IPCW Brier, sex-stratified C-index, MERF variance trajectories) | Run them over ~2 SLURM days to move score from 7.5 → 8.5 | Scope constraint of this session was LaTeX-only. The gaps are acknowledged in Limitations as future work. |
| Reviewer backend: Claude Opus subagent | Codex MCP (GPT-5.4) | Codex MCP unavailable at session start; auto-fallback engaged. Opus was sufficient for methodology-paper review. |
| 4 rounds with HUMAN_CHECKPOINT on each | Autonomous 2-round loop | User explicitly overrode default max_round=2 → 4 and human_checkpoint=false → true. Enabled mid-loop course corrections (title shortening, abstract trim). |

## Incremental Work Log

**2026-04-10 ~14:00:** Session start. Detected Codex MCP unavailable; reviewer backend = Claude Opus subagent. Preserved original as `RF pseudo_round0_original.tex`. Read full manuscript (660 lines).

**2026-04-10 ~14:10:** Round 1 review via Opus subagent. Score 5/10. Identified 3 CRITICAL issues (C1-C3) and 5 MAJOR issues (M1-M5).

**2026-04-10 ~14:20:** User checkpoint: "go" + "change the title, as the PO landmarking is not a novel contribution of our method." Applied Round 1 fixes (title/abstract/intro/methods preamble reframing, +9 citations, MERF semi-formal analysis, AI governance discussion). Compiled to 25 pages, 0 undefined refs.

**2026-04-10 ~14:45:** Round 2 review. Score 6.5. Identified C1 (rhetoric/content mismatch), C2 (calibration still absent), M1-M5. User checkpoint: "Option B, go" (selected shorter title + approved fixes). Applied Round 2 fixes.

**2026-04-10 ~15:10:** Round 3 review. Score 7.0. Reviewer flagged title "with Pseudo-Observation Forests" as residually implying authorship; recommended "Evaluating...". User: "go". Applied Round 3 fixes including title tweak.

**2026-04-10 ~15:35:** Round 4 (final) review. Score 7.5. Verdict: (a) submit as-is after 30-min LaTeX polish. Applied M4-1 through M4-3 + minor polish.

**2026-04-11 ~00:00:** Final compile: 25 pages, 0 undefined refs, 1 pre-existing overfull hbox (simulation table in `\resizebox`). Saved `RF pseudo_round4_final_biostat_rwe.pdf`. Wrote PAPER_IMPROVEMENT_LOG.md and finalized PAPER_IMPROVEMENT_STATE.json.

**2026-04-11 ~00:30:** User requested removal of "what this paper does NOT deliver" sentence from abstract. Removed it and softened corresponding Limitations language (no more "companion deployment study in preparation" commitment). Recompiled cleanly at 25 pages.

## Learnings & Corrections

- **[LEARN:framing]** When adapting existing methodology for a new venue, never let autonomous reframing drift into claiming the methodology as our novel contribution. The user had to intervene after Round 0 to say "PO landmarking is not a novel contribution of our method." Default future behavior: read the full introduction before any autonomous reframing of a paper that builds on prior methods, and preserve the attribution chain explicitly in the title/abstract/intro.

- **[LEARN:abstract-hedging]** Abstracts should not advertise their own gaps defensively. A "what this paper does NOT deliver" sentence feels honest but creates two problems: (1) implicit commitment to a companion paper that may not exist, and (2) cues hostile reviewers to focus on what's missing rather than what's present. Keep honesty in the Limitations section; let the abstract lead with what the paper does.

- **[LEARN:review-loop-scope]** Four rounds of LaTeX-only review gained +2.5 points (5.0 → 7.5), but the remaining +1.0-1.5 points required empirical additions (calibration, sex-stratified C-index, MERF variance trajectories) that SLURM could deliver in ~2 days but a LaTeX-only loop cannot. When a paper needs both framing fixes AND empirical fixes, budget SLURM time alongside the improvement loop.

## Verification Results

| Check | Result | Status |
|-------|--------|--------|
| Final compile | 25 pages, xelatex + biber + 2 × xelatex | PASS |
| Undefined references | 0 | PASS |
| Undefined citations | 0 | PASS |
| Overfull hbox | 1 (pre-existing, simulation table wrapped in `\resizebox`) | ACCEPTED |
| Attribution consistency (no "we propose" / "our framework") | 0 residuals after find-replace sweep | PASS |
| Round-by-round snapshots preserved | `RF pseudo_round{1,2,3,4_final}_biostat_rwe.pdf` | PASS |
| PAPER_IMPROVEMENT_LOG.md written | Yes | PASS |
| PAPER_IMPROVEMENT_STATE.json finalized | status=completed, last_score=7.5 | PASS |

## Open Questions / Blockers

- [ ] **GitHub repository URL placeholder** `[GitHub repository URL]` still in Software & Data Availability section. Must be filled before submission.
- [ ] **Bibliography `\emergencystretch 3em`** — needs visual verification that it renders cleanly in the submission PDF.
- [ ] **Calibration + sex-stratified C-index + MERF variance diagnostics** — would move score from 7.5 to 8.5. Reviewer called this "two SLURM days" of work on existing R fits. Decision needed: submit as-is or run the post-hoc analyses first.

## Next Steps

- [ ] Decide: submit as-is (7.5/10) or run post-hoc SLURM analyses to reach 8.5/10
- [ ] Fill in GitHub URL in Software & Data Availability
- [ ] If running SLURM: (1) IPCW Brier on existing CARRA fits via `pec`/`riskRegression`; (2) sex-stratified C-indices from 100 existing splits; (3) extract MERF variance trajectories from saved fit objects; (4) out-of-range pseudo-obs fraction (1 line of R)
- [ ] Verify companion deployment paper is actually planned before any re-insertion of the "companion study" language
