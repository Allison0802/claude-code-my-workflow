# Missing Types / IPW — illustrative example (NOT shipped, NOT smoke-tested)

This folder contains a project-flavored example config for using `method-evolve`
to search over IPW propensity feature sets in the Missing Types sub-project. It
is *not* exercised by the skill's smoke test and is not required for the skill
to run anywhere — it exists only to illustrate how a realistic, statistically
non-trivial config looks end-to-end.

The `templates/prereq_ibs.R.patch` patch adds an integrated pseudo-Brier (IBS)
column to a sub-project evaluator. Apply it via:

  /method-evolve prereq --config-path examples/missing_types_ipw/config.yaml

For the skill's actual smoke test (zero external dependencies), see
`examples/synthetic_cox/`.
