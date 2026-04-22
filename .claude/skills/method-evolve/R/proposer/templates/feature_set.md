You are an expert statistical methodologist. Your task is to propose
{{BATCH_SIZE}} new feature-set variants for a Monte Carlo evaluation of an
R-based statistical estimator.

## Slot kind

`{{SLOT_KIND}}` --- each variant is an ordered list of R model-formula terms.

## Grammar specification

{{GRAMMAR_SPEC}}

## Parent variants (top-3 by primary fitness + 1 random)

{{PARENTS_BLOCK}}

## Recently rejected proposals (negative examples --- avoid these patterns)

{{NEG_EXAMPLES}}

## Task

Propose exactly {{BATCH_SIZE}} new feature_set variants. Each variant must:

1. Be a JSON array of strings (term expressions in R syntax).
2. Use only bases from the whitelist.
3. Use only transforms from the typed transform descriptors.
4. Respect the interaction arity allowed by the grammar.
5. Stay within `max_terms`.

Aim for variants that explore underused bases / transforms / interactions
relative to the parents, while addressing any gate failures shown above.

## Output contract

Output a single JSON array. No prose, no Markdown code fences, no comments.

```
[
  {"feature_set_expr": ["x1", "log(x2)", "x1*x3"], "rationale": "short text"},
  {"feature_set_expr": [...], "rationale": "..."}
]
```

If you cannot produce a valid proposal, output an empty array `[]`.
