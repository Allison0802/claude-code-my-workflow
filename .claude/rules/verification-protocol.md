---
paths:
  - "Papers/**/*.tex"
  - "scripts/**/*.R"
  - "comparisons/**/*.R"
  - "Missing Types/**/*.R"
---

# Task Completion Verification Protocol

**At the end of EVERY task, Claude MUST verify the output works correctly.** This is non-negotiable.

## For LaTeX Manuscripts:
1. Compile with xelatex (3-pass + bibtex) and check for errors
2. Open the PDF to verify figures render
3. Check for overfull hbox warnings
4. Verify bibliography entries resolve

## For R Scripts:
1. Run `Rscript scripts/R/filename.R`
2. Verify output files (PDF, PNG, RDS) were created with non-zero size
3. Spot-check estimates for reasonable magnitude
4. Verify seed produces reproducible results (run twice if in doubt)

## For Simulation Code:
1. Run a small-scale test (e.g., n=100, B=10 reps) to verify code executes
2. Check output dimensions match expectations
3. Verify no NAs or Infs in results
4. Check that all scenarios/conditions produce output

## Common Pitfalls:
- **Missing packages**: Check `library()` calls resolve before running full simulation
- **Path issues**: Verify `here::here()` resolves correctly from the project root
- **Memory**: Large simulations may need chunked processing — check memory usage on small runs
- **Parallel RNG**: Verify `RNGkind("L'Ecuyer-CMRG")` is set before parallel code

## Verification Checklist:
```
[ ] Output file created successfully
[ ] No compilation/execution errors
[ ] Figures display correctly (white bg, readable labels)
[ ] Results are numerically reasonable
[ ] Reported results to user
```
