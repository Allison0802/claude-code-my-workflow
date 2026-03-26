# Session Log: 2026-03-16 -- Literature Survey: Recurrent Multi-Type Events + ML

**Status:** COMPLETED

## Objective
Conduct a thorough literature survey on "survival probability prediction for recurrent events with multiple event types (not competing risks) using machine learning methods" for PhD dissertation context-setting and gap identification.

## Changes Made

| File | Change | Reason | Quality Score |
|------|--------|--------|---|
| `quality_reports/session_logs/2026-03-16_lit-survey-recurrent-multi-type-ml.md` | Created session log | Track lit survey session | N/A |

## Design Decisions

| Decision | Alternatives Considered | Rationale |
|----------|------------------------|-----------|
| 10 parallel search dimensions | Single broad query | Cover ML, statistical, and domain-specific angles exhaustively |
| Fetch full content for 5 key papers | Rely on search snippets only | Verify contribution scope (ML vs stats, prediction vs estimation, single vs multi-type) |

## Incremental Work Log

**Session start:** Ran 10 WebSearch queries across: recurrent+ML, random forest survival, multi-type modeling, landmark, pseudo-obs, deep learning, RSF+terminal event, frailty+multitype, gap time, MERF.

**Round 2:** Targeted follow-up searches on: C-index evaluation, global/episode-specific prediction (JASA 2025), Bayesian dynamic models, survival stacking, TransformerLSR, dynamicLM, cyclic recurrent events.

**Full-text fetch:** Verified contribution scope for: (1) RF+pseudo-obs for recurrent events (Biostatistics 2025), (2) Dynamic risk model for multitype recurrent events (AJE 2023), (3) RecForest (BMC 2025), (4) Global/episode-specific prediction (JASA 2025), (5) TransformerLSR (AI in Medicine 2024), (6) Bayesian semiparametric joint dynamic model (arXiv 2024/2025).

**Key finding confirmed:** No paper simultaneously combines (a) multiple NON-competing recurrent event types + (b) ML prediction methods + (c) formal evaluation via type-specific C-index or calibration metrics. This is the primary structural gap.

## Learnings & Corrections

- [LEARN:lit-survey] RecForest (2025) handles recurrent events + terminal event via Ghosh-Lin marginal model, NOT multiple simultaneous event types.
- [LEARN:lit-survey] The multi-type recurrent event statistical literature (Ghosh & Lin 2003, Ghosh 2004, multiRec 2023, Bayesian dynamic models 2024-2025) is rich but overwhelmingly frequentist parametric/semiparametric with no ML prediction papers.
- [LEARN:lit-survey] TransformerLSR (2024) is the closest deep learning paper to the target gap but treats recurrent events as a single process (not multiple types) and is not validated for type-specific prediction.
- [LEARN:lit-survey] The pseudo-observation + RF approach for recurrent events (Biostatistics 2025) is the most direct precursor to the dissertation work but handles single event type only.

## Verification Results

| Check | Result | Status |
|-------|--------|--------|
| All 10 search dimensions covered | Yes | PASS |
| Key papers verified via full-text fetch | 6 papers fetched | PASS |
| Gap identification grounded in literature | Confirmed structural gap | PASS |

## Open Questions / Blockers

- [ ] Check whether any unpublished arXiv preprints address multi-type + ML prediction (search was limited to indexed results)
- [ ] Confirm whether Ghosh & Lin (2003) marginal rates model for multi-type has been extended to prediction (beyond estimation)
- [ ] Consider reaching out to authors of multiRec (2023) or Bayesian dynamic model (2025) about prediction focus

## Next Steps

- [ ] Incorporate landscape map into dissertation Chapter 1 (Introduction/Related Work)
- [ ] Use gap map to sharpen dissertation contribution statement
- [ ] Add key citations to Bibliography_base.bib

- [23:45] CLAUDE.md (parent + subprojects) — cataloged all skills/agents; expanded Skills Quick Reference in parent with 30+ entries organized by category; added project-specific Skills & Agents sections to comparisons/CLAUDE.md and Missing Types/CLAUDE.md; identified relevant claude-scientific-skills (scikit-survival, statistical-analysis, pymc, pubmed-database, openalex-database); marked dormant slide skills
