# Session Log: 2026-03-29 — Simulation Sections Accuracy Fixes

**Goal:** Fix technical inaccuracies in §4.1 (Data Generation) and §4.2 (Simulation Scenarios) of comparisons/Paper/RF pseudo.tex, guided by code review of submit_comprehensive_comparison_array.sh, submit_by_method.sh, comprehensive_method_comparison.R, and functions.R.

**Approach:** Used auto-paper-improvement-loop with GPT-5.4 xhigh for accuracy-focused review against actual R implementation. Pre-identified 8 discrepancies before sending to GPT.

**GPT Review Score:** 4/10 (Not reproducible as written). 4 CRITICAL + 4 MAJOR issues.

## Changes Made

- [12:00] comparisons/Paper/RF pseudo.tex §4.1 — Fixed hazard equation: added w_i^last term (gap-time function, β₅=β₆=0 in production); corrected X_cor to use β₇/β₈ instead of β₅/β₆
- [12:00] comparisons/Paper/RF pseudo.tex §4.1 — Disclosed c=2 uses different generator (rate_cox_data_gen_interaction) with discrete risk-group terms; prior text described only c=0,1 T_j formulas
- [12:00] comparisons/Paper/RF pseudo.tex §4.1 — Fixed event simulation: clarified two independent type-specific gap-time loops merged, not a single combined process
- [12:00] comparisons/Paper/RF pseudo.tex §4.1 — Fixed censoring: disclosed per-(α,c,ρ) censor_max calibration lookup (range 0.10–100); not a single c_max
- [12:00] comparisons/Paper/RF pseudo.tex §4.2 — Fixed complexity encoding: (C₁,C₂,C₃,C₄)=(1,-1,1,-1)·c → Cⱼ=c for all j (uniform positive scaling); sign variation comes from functional form of T₂
- [12:00] comparisons/Paper/RF pseudo.tex §4.2 — Fixed beta vector: (1.5,1.0,1.2,1.5,0.5,0.3) [6-element] → (1.5,1.0,1.2,1.5,0,0,0.5,0.3) [8-element with correct index mapping]
- [12:00] comparisons/Paper/RF pseudo.tex §4.3 — Fixed scenario count: "37 scenarios" → "36 scenarios (3×3×2×2 full factorial)"

**Compilation:** Successful — 20 pages, 0 errors.

**Open questions / remaining issues:**
- GPT flagged that X_cor is not included in fitted model predictors (MAJOR); this is in §4.2 last paragraph and warrants a clarification
- Round 2 review pending
- [12:30] comparisons/Paper/RF pseudo.tex §4.1–4.2 — Round 2 fixes: named beta notation (β_Z/β_X/β_cor), c=2 T3 sign-flip corrected for both types, 'conditionally independent given Q_i' qualifier added
