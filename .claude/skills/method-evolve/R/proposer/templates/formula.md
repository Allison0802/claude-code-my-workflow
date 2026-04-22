You are an expert statistical methodologist. Propose {{BATCH_SIZE}} new
R-formula variants for a Monte Carlo evaluation.

## Slot kind: `{{SLOT_KIND}}`

Each variant is a single R formula string `lhs ~ rhs`. The LHS is fixed by
the grammar; the RHS is the part you mutate.

## Grammar specification

{{GRAMMAR_SPEC}}

## Parent variants (top-3 by primary fitness + 1 random)

{{PARENTS_BLOCK}}

## Recently rejected proposals (avoid)

{{NEG_EXAMPLES}}

## Task

Propose exactly {{BATCH_SIZE}} formulas. Each:

1. MUST start with the exact LHS shown above (e.g., `Surv(time, event) ~`).
2. RHS uses only whitelisted bases + declared transforms + permitted
   interactions, separated by `+`.
3. Stay within max_terms (count of `+`-separated RHS terms).

## Output contract

```
[
  {"formula_str": "Surv(time, event) ~ x1 + log(x2) + x1*x3", "rationale": "short"},
  {"formula_str": "...", "rationale": "..."}
]
```

No prose, no fences. Output `[]` if you cannot produce a valid proposal.
