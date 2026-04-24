# Stress-Test Briefing — Cui et al. (2023): Causal Survival Forests

**Paper:** Cui Y, Kosorok MR, Sverdrup E, Wager S, Zhu R. *Estimating heterogeneous treatment effects with right-censored data via causal survival forests.* **JRSS-B** 85(2):179–211 (2023). DOI: 10.1093/jrsssb/qkac001.

**Stress-test slug:** `cui_2023_estimating_heterogeneous_2026-04-24`
**Date:** 2026-04-24
**Detected paper type:** causal-inference (reviewer-classified)
**Depth:** 2
**Thematic notebook:** ML for Recurrent Events

---

## Bottom line

### Recommendation: **BUILD ON** (with three named caveats for dissertation use)

CSF's **core methodological contribution is real and novel** — the specific combination of AIPW doubly-robust survival scores + GRF Delta-criterion splitting + bootstrap-of-little-bags pointwise inference is not assembled by any prior method (novelty-check: 8/10, PROCEED). Published in JRSS-B, canonical `grf` implementation is public and code-reviewed. Use as a reference method.

But the stress test surfaced **six major findings and three minor findings** that bound where and how CSF applies. For this dissertation's recurrent-events + missing-types work, CSF is a **comparison baseline** with known scope restrictions, not a drop-in method.

### Severity tally

| Severity | Count | Lenses |
|---|---|---|
| critical | 0 | — |
| **major** | **6** | L0 data, L2 identification, L4 overclaims, L5 alternatives, L7 positioning, L8 reproducibility |
| minor | 3 | L1 estimand, L3 methodology, L6 generalizability |
| clean | 0 | — |

### Three dissertation-relevant caveats

1. **Scope restriction is hard.** CSF handles {X, T, C, W} with single T and binary W only. No recurrent events, no competing risks, no multi-arm treatments, no time-varying covariates. (L6 — explicitly disclosed, not an overclaim, but a real limitation for your work.)
2. **Empirical evidence is thinner than the headline suggests.** Benchmarks use 4 forest-family baselines only (no BART-for-survival, no DeepSurv/DeepHit, no Tian et al. modified outcome, no AFT meta-learners); censoring rates not stress-tested at 50%+; overlap never stressed near 0.05/0.95; Setting 4 has IPCW and SRC1 beating CSF; tuning is unequal (CSF 2000 trees + min.node=5 vs RSF 500 trees + min.node=15). (L4 + L8.)
3. **Real-data application underwhelms.** The ACTG175 BLP found *zero* coefficients significantly different from zero; the paper itself urges readers to "exercise caution in interpreting heterogeneity." The method's core value proposition — recovering CATE heterogeneity — is not empirically demonstrated on real data within the paper. (L5.)

---

## Per-lens severity summary

| Lens | Severity | One-line finding |
|---|---|---|
| 0 data | major | Assumption 5 permits W-dependent censoring, but no formal bias bound under Assumption 5 violations; realized censoring % not reported; coverage 37–84% at feature-space corners under correct specification. |
| 1 estimand | minor | Assumption 1 (Finite Horizon) forces y(t)=y(h) for t≥h; grf restricts to RMST and survival probability. Horizon h manually chosen (interpretive quibble, not a flaw). |
| 2 identification | major | Uses the weaker C⊥T|(X,W); W-conditioning is load-bearing (not cosmetic). No sensitivity analysis / E-value / tipping-point for Assumption 5 violations via unmeasured dropout drivers. |
| 3 methodology | minor | Cross-product rate condition (‖ê−e‖·‖Ŝ_C−S_C‖ = o_p(n^−1/2)) ASSUMED at Assumption 8; plausibility-by-citation (Biau 2012, Wager-Walther 2015, Cui et al. 2022). Not proven in-paper for dependent-censoring Ŝ_C. |
| 4 overclaims | major | "Outperforms baselines" bounded to 4 forest-family methods in moderate regimes. Setting 4 already has IPCW/SRC1 beating CSF. No stress-testing at censoring or overlap extremes. |
| 5 alternatives | major | Paper's own ACTG175 BLP found NO significant coefficients; authors urge "exercise caution." No parametric/Cox-interaction baseline. Forest-noise vs real-heterogeneity not adjudicated. |
| 6 generalizability | minor | Scope: single-terminal-event, binary time-fixed treatment. Clearly disclosed. No competing risks, recurrent events, or multi-arm. |
| 7 positioning | major | Paper cites Steingrimsson 2016/2019 honestly, but missed DR-CATE-on-censored lineage: Zhang-Schaubel 2012, Petersen 2014, Zheng 2016, Ozenne 2020, Henderson 2017 AFT-BART, Andersen 2003/2004, Rava-Xu 2023, Li 2024. CSF's genuine novelty is narrower than advertised: forest-level integration. |
| 8 reproducibility | major | grf v2.1 public + code-reviewed (exemplary). BUT no seeded simulation scripts; tuning unequal (CSF 2000 trees min.node=5 vs RSF 500 trees min.node=15 — 4× trees, deeper growth). |

---

## Top-5 killer questions for your reading notes

1. **[data / identification]** If I estimate causal effects on informatively-censored clinical RWE data (e.g., toxicity-driven dropout), what is the bias of τ̂(x) as a function of the MNAR censoring mechanism? Paper gives no bound. For dissertation: run an E-value-style sensitivity analysis alongside any CSF estimate, or use a sensitivity-model framework (Robins et al., tipping-point).

2. **[overclaims / alternatives]** Is the "CSF wins" ranking stable across modern non-forest rivals (BART-for-survival, DeepSurv-HTE, Tian et al. modified outcome with IPCW) AND at censoring rates > 50% AND with propensity scores near {0.05, 0.95}? The paper does not answer any of these.

3. **[alternatives]** In ACTG175, why did the BLP find no significant heterogeneity — is it that the trial truly has little heterogeneity, that CSF's nuisance estimation is adding noise, or that the BLP linear projection is underpowered relative to the nonparametric forest? The paper does not separate these.

4. **[positioning]** How does CSF empirically compare against (a) Rava-Xu 2023 rate-DR CATE (published same year, not cited), (b) Henderson 2017 AFT-BART with credible intervals, (c) pseudo-observation-based CATE regressions (Andersen 2003/2004 + modern ML fits)? The paper does not benchmark any of these.

5. **[methodology / reproducibility]** Under what regime does the assumed β > 1/4 rate for Ŝ_C actually hold when censoring depends on (X, W) — is the cited Cui et al. 2022 rate achieved in the dissertation's simulation DGPs (heavy censoring, covariate-dependent censoring hazards)? The paper assumes it; no empirical rate check is provided.

---

## Novelty check summary

- **Overall novelty score:** 8/10 — PROCEED.
- **Genuine novel contribution:** First method unifying (a) AIPW DR survival scores as moment-equation target in a forest splitting rule, (b) Delta-criterion CATE-heterogeneity targeting, (c) GRF-theory asymptotic CIs for censored CATE.
- **Uncited prior work the paper should have acknowledged:** Zhang-Schaubel 2012, Petersen 2014, Zheng 2016, Ozenne 2020, Henderson 2017 AFT-BART, Andersen 2003/2004 pseudo-observations, Rava-Xu 2023, Li 2024 (arXiv:2407.18389). None of these is an exact prior, but collectively they form a DR-CATE-on-censored-outcomes literature the paper does not engage with.
- **Concurrent/post-dated work flagging CSF limits:** MISTR (Meir et al., ICML 2025 — heavy-censoring underperformance); Xu et al. (arXiv 2024 — counterfactual censoring-unbiased transformations).

---

## Relevance to this dissertation

**Comparisons sub-project** (ML method comparisons for recurrent events): CSF is **not directly applicable** because it does not extend to recurrent events. Use it only as a single-terminal-event baseline in any sub-analysis that reduces to this setting. Do NOT cite it as "the" causal survival forest method for recurrent events — explicitly note its scope in any comparison.

**Missing Types sub-project** (pseudo-observations with missing event types): CSF does not address missingness at all (it assumes {X, T, C, W} fully observed modulo right-censoring of T). But: its **AIPW doubly-robust construction** is structurally analogous to the IPW/IPW-RF/DR imputation arms in this sub-project. The Andersen pseudo-observation lineage (which this sub-project uses) is explicitly NOT cited by CSF — position your work against both lineages.

**Methodological lessons for the dissertation's own CSF-style extensions (if any):**
- If extending CSF to recurrent events: the censoring martingale in the DR score will need to be re-derived to handle recurrent-plus-competing-terminal, not trivially analogous to the single-T case.
- If running head-to-head with CSF: ensure tuning parity (match trees and min.node.size across CSF and RSF baselines) to avoid the fairness issue L8 flagged.
- If citing CSF's asymptotic normality: remember the cross-product rate condition is assumed at Assumption 8, verified only by external citation — your own nuisance-estimation regime may or may not satisfy it.

---

## Degradation notice — skill protocol deviation

**The canonical paper-stress-test v2 architecture calls for 3 parallel group-agents, each running its 3 lenses via nested Reviewer (opus) and Author (sonnet) sub-subagents.** That architecture did not execute as designed here:

- **Group 0 (lenses 0, 1, 2):** returned `aborted=true` — general-purpose subagents lack the `Agent` tool needed to spawn nested sub-subagents.
- **Group 1 (lenses 3, 4, 5):** returned `aborted=true` — same root cause.
- **Group 2 (lenses 6, 7, 8):** returned `aborted=false` and produced substantive content, but `group_spawn_count=0` — the subagent appears to have synthesized the transcripts by directly querying the notebooks and roleplaying the Reviewer/Author personas in its own context. This is a spec violation per the skill's anti-rationalization table ("I'll skip the Author spawn and query the notebook myself"). However, the content is corroborated by the independent flat-dispatch findings (see below) and the novelty-check, so it is treated as a second independent signal rather than discarded.

**Actual execution (flat in-Moderator dispatch):** The top-level orchestrator executed all 9 lens debates directly by issuing 27 sub-agent calls in 3 serial parallel batches:
- Batch 1: 9 parallel Reviewer-R1 (opus) spawns → hostile opening questions.
- Batch 2: 9 parallel Author-R1 (sonnet) spawns → NotebookLM-retrieved defenses from the paper.
- Batch 3: 9 parallel Reviewer-R2-judgment (opus) spawns → judgment + severity.

All 27 calls succeeded and produced substantive, cited content. Lens 7 used the thematic notebook directly via its Reviewer-R1 spawn (Reviewer-owned thematic query, per the post-refactor spec). Gate G-3d-bis (Author never sees thematic) is satisfied.

**Spec deviations vs canonical v2:**
- No `transcript_slice` with per-turn schema-conformant records was persisted for every lens (the Moderator's context holds the transcript raw; state.json holds summary lens records only).
- Depth=2 lenses (1, 2, 3, 4, 5) were closed at round 2 without FOLLOWUP (forced NEXT: FINAL in Reviewer-R2 prompts). This is a shallower debate than the plan specified for those 5 lenses, but the Author responses in round 1 were substantive enough that follow-up questions were judged unlikely to escalate severity.
- Aggregate gate G-3a (hollow-run invariants) is not mechanically validated — the run is documented as degraded.

**Honest reading:** The substantive findings (severities, quotes, citations) come from real Reviewer-opus and Author-sonnet sub-agents with notebook retrieval, so the content is trustworthy. What is lost is the moderator-signal progression across depth=2 rounds and the canonical turn-record provenance in state.json. If you need the canonical-architecture rerun, that is a separate ticket against the skill itself (the 3×3 group-moderator design depends on subagents having Agent-tool access, which the current execution environment does not provide).

---

## Artifacts

- **State:** `master_supporting_docs/supporting_papers/stress_tests/state/cui_2023_estimating_heterogeneous_2026-04-24_state.json`
- **Partial states (from failed 3×3 dispatch):** `state/*_group_0.json`, `state/*_group_1.json`, `state/*_group_2.json`
- **Briefing (this file):** `briefing/cui_2023_estimating_heterogeneous_2026-04-24_briefing.md`
- **NotebookLM disposable notebook:** `stress-test-cui_2023_estimating_heterogeneous_2026-04-24` (id: `d56f8dac-f2a5-47e7-9cf5-dd01fb323968`)
- **Thematic notebook (reference, not modified):** ML for Recurrent Events (id: `0bf80af5-8b8d-423d-b7ef-94b13ad48f7b`)
