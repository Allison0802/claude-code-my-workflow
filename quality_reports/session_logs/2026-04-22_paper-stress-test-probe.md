# Synchronous Agent Sanity Check — 2026-04-22

## Call
- tool: Agent
- mode: synchronous (run_in_background not set)
- subagent_type: general-purpose
- model: sonnet
- prompt (verbatim): "Reply with exactly the word READY, followed by a newline, and a second line containing the string SYNC_OK. Do not call any tools. Do not add anything else."

## Result
- tool result (verbatim): "READY\nSYNC_OK"
- contains READY: YES
- contains SYNC_OK: YES
- wall-clock: ~2.2 seconds

## Outcome
PASS

Reason: The synchronous Agent call returned the subagent's final output directly in its tool result, containing both required tokens (READY and SYNC_OK), confirming that the Agent tool primitive works correctly on this harness.

## Note on execution context
The Agent tool is a first-class built-in available to the orchestrating Claude Code session; it does not appear in deferred-tool lists (ToolSearch("select:Agent") correctly returns "No matching deferred tools found" — no schema fetch required before use).

The probe was run by the orchestrating Claude session (not by a subagent, since subagents cannot call Agent themselves). This matches the spec intent: the primitive being verified is the one the Moderator uses in the Phase 3 loop.

## Note on pre-amendment evidence
Before this formal probe, a different probe (`probe_counter`) was spawned during architectural planning with instructions to reply `READY`; it did so in its initial tool result. That early evidence was already sufficient to conclude that synchronous `Agent` works on this harness. The formal probe above supersedes it and is recorded here for audit completeness.

## 2026-04-23 Task 1.5 Changes

- [01:50] `.claude/skills/paper-stress-test/SKILL.md` -- Added `## Parsing contract` section (L41–L165) between `## Constants` and `## Defer-tool preamble`; provides canonical regexes for all 7 subagent output patterns (Reviewer question, judgment+decision, Lens 7 initial, Lens 7 confrontation, Author answer, classification triple, novelty-check report) plus reparse protocol and cross-reference table. Committed as a5c38d4.

## 2026-04-23 Task 1.6 Changes

- [02:25] `.claude/skills/paper-stress-test/tests/fixtures/0{1..7}_*.txt` -- Seven realistic fixtures, one per Parsing-contract pattern; variants 02/04/05 use `---FIXTURE_SEPARATOR---` to bundle alternative branches (FOLLOWUP/FINAL, CONFRONTATION/early-close, addressed/absent). Fixture 07 aligned to the actual `novelty-check` Phase D output format (`Score: X/10`, `Recommendation: PROCEED | PROCEED WITH CAUTION | ABANDON`) rather than the plan draft's `Overall score:` / `build-on` which would not match the SKILL.md Pattern 7 regex.
- [02:26] `.claude/skills/paper-stress-test/tests/test_parsing.sh` -- POSIX-sh wrapper around a python3 harness that applies each SKILL.md regex (Patterns 1–7) to its fixture with `re.DOTALL | re.MULTILINE` per the parsing contract and asserts an expected capture substring. Exit 0 iff all seven PASS. Current result: `all 7 patterns PASS`.

## 2026-04-23 Post-smoke cost caveat — FLAGGED

First end-to-end smoke run on Loe et al. 2025 (not the T19-pinned Wager & Athey — user's choice). Briefing and 9/9 lenses produced successfully, but the run exposed cost issues that warrant a follow-up before shipping this skill:

| Telemetry field | Value | Expected / budget | Verdict |
|-----------------|-------|-------------------|---------|
| `wall_clock_start` → file mtime | 02:47Z → 08:38Z (~5h 51m) | `wall_clock_budget_s = 1800` (30 min) | **BUDGET BLOWN ~11×.** However: the vast majority of this elapsed time was **idle while waiting for user plan confirmation** at Phase 2 Step 2.10 — not compute time. Root causes: (1) `wall_clock_start` was captured at Phase 0, so the confirmation wait is included in elapsed; (2) the `check_budgets_before_lens` gate was never called (bypassed or not implemented). Fixed in SKILL.md: `wall_clock_start` is now initialized `null` and set at Phase 3 start (after plan confirmation), and `--no-checkpoint` flag added to skip the wait. |
| `spawn_count` | 35 | budget 80 | Within budget ✓ |
| `moderator_own_context_est_chars` | 0 | should accumulate on every spawn | **Accumulator never fired.** The required `spawn_agent` wrapper (T11 Step 3.8.5) was bypassed in the live run — spawns went straight to `Agent(...)`. This means the moderator-context soft-abort (T10 Step 3.7.5) is effectively disarmed until the wrapper is threaded through every call site. |
| `compaction_history` | `[]` (empty) | none triggered for this run | Expected ✓ — single-paper depth-low run didn't cross 80000-char threshold. |
| `completed_at` | `null` | ISO timestamp set in Phase 5.3 | **Minor bug** — T13 Step 5.3 finalize didn't stamp `completed_at`. |
| `run_status` | `"complete"` | `"completed"` per schema in T3 and T13 | **Minor schema drift** — string mismatch; update either the docs or the runtime to match. |

**Follow-up tasks to land before the v1 ship:**

1. Audit every `Agent(...)` call site in SKILL.md and confirm routing through `spawn_agent` (or similar wrapper that increments `state.spawn_count` AND `state.moderator_own_context_est_chars`). Unrouted calls let runaway loops evade both hard ceilings.
2. Instrument `check_budgets_before_lens` with a user-visible log line on each call (e.g., `[budgets] spawns=N/80  wall=S/1800s  ctx=C/1_600_000`) so blown budgets are noticed during the run, not only after.
3. Fix Phase 5.3 to stamp `completed_at`; unify `run_status` enum (prefer `"completed"`).
4. ~~Token cost: at 35 Agent spawns with each spawn receiving the full running transcript + persona + lens context + tool-result round-trips, real token usage is almost certainly in the 400K–800K range. Empirical measurement per run is a prerequisite for deciding whether `spawn_budget=80` is actually the right ceiling.~~ **Deferred to v2** — token cost calibration and `spawn_budget` tuning are out of scope for v1 ship.

This caveat does NOT block pushing the branch or opening a PR; it documents a known issue to resolve before the skill is invoked routinely.
