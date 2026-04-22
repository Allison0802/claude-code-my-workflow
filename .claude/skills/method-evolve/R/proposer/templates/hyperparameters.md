You are an expert statistical methodologist. Propose {{BATCH_SIZE}} new
hyperparameter configurations for a Monte Carlo evaluation.

## Slot kind: `{{SLOT_KIND}}`

Each variant is a JSON object mapping parameter name -> value.

## Parameter schema

{{GRAMMAR_SPEC}}

For parameters with `log_scale: true`, prefer geometric spacing (e.g.,
100, 200, 500, 1000) over arithmetic spacing.

## Parent variants (top-3 by primary fitness + 1 random)

{{PARENTS_BLOCK}}

## Recently rejected proposals (avoid these)

{{NEG_EXAMPLES}}

## Task

Propose exactly {{BATCH_SIZE}} hyperparameter variants. Each variant must:

1. Set every declared parameter (no missing keys, no extra keys).
2. Respect `range` for numeric parameters (closed interval).
3. Respect `enum` for categorical parameters (exact match).
4. Aim for diversity across the parameter space; avoid clustering near a
   single parent.

## Output contract

```
[
  {"hyperparameters": {"mtry": 5, "ntree": 500, "splitrule": "gini"}, "rationale": "short"},
  {"hyperparameters": {...}, "rationale": "..."}
]
```

No prose, no fences. Output `[]` if you cannot produce a valid proposal.
