# Workflow Quick Reference

**Model:** Contractor (you direct, Claude orchestrates)

---

## The Loop

```
Your instruction
    ↓
[PLAN] (if multi-file or unclear) → Show plan → Your approval
    ↓
[EXECUTE] Implement, verify, done
    ↓
[REPORT] Summary + what's ready
    ↓
Repeat
```

---

## I Ask You When

- **Design forks:** "Option A (fast) vs. Option B (robust). Which?"
- **Code ambiguity:** "Spec unclear on X. Assume Y?"
- **Replication edge case:** "Just missed tolerance. Investigate?"
- **Scope question:** "Also refactor Y while here, or focus on X?"

---

## I Just Execute When

- Code fix is obvious (bug, pattern application)
- Verification (tolerance checks, tests, compilation)
- Documentation (logs, commits)
- Plotting (per established standards)
- Deployment (after you approve, I ship automatically)

---

## Quality Gates (No Exceptions)

| Score | Action |
|-------|--------|
| >= 80 | Ready to commit |
| < 80  | Fix blocking issues |

---

## Non-Negotiables

- **Paths:** `here::here()` for all R file paths; relative paths for LaTeX
- **Seeds:** `set.seed(YYYYMMDD)` once at top of every stochastic script
- **Color palette:** Okabe-Ito colorblind-friendly (see `r-code-conventions.md`)
- **Figures:** Publication-ready — 300 DPI, white background, `.pdf` for papers / `.png` for web
- **Figure theme:** `theme_publication()` with consistent fonts and sizing
- **Tolerances:** 1e-6 for point estimates; 1e-3 for standard errors

---

## Preferences

**Visual:** Polished, publication-ready. Clean axis labels, no chartjunk, colorblind-safe.
**Reporting:** Concise bullets; detail on request.
**Session logs:** Always (post-plan, incremental, end-of-session).
**Replication:** Strict — flag near-misses, never silently round.

---

## Exploration Mode

For experimental work, use the **Fast-Track** workflow:
- Work in `explorations/` folder
- 60/100 quality threshold (vs. 80/100 for production)
- No plan needed — just a research value check (2 min)
- See `.claude/rules/exploration-fast-track.md`

---

## Next Step

You provide task → I plan (if needed) → Your approval → Execute → Done.
