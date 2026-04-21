---
name: review
description: Default review entry point. Routes by file type — .R → review-r (r-reviewer agent), .tex → review-paper (6-dimension referee review), research idea/content → research-review (interactive Codex MCP dialogue). Use this when you want a review but don't want to think about which skill to pick.
disable-model-invocation: true
argument-hint: "[file.R | file.tex | 'research idea or topic']"
allowed-tools: ["Read", "Glob", "Task", "Skill"]
---

# Review Dispatcher

Route to the correct reviewer based on what is being reviewed.

## Routing

Parse `$ARGUMENTS`:

### `.R` file or R script path
→ Run **`review-r`** with the same argument.
- Checks: code quality, reproducibility, domain correctness, figure standards
- Invokes the `r-reviewer` agent
- Output: `quality_reports/[script_name]_r_review.md`

### `.tex` file or LaTeX manuscript path
→ Run **`review-paper`** with the same argument.
- Checks: argument structure, statistical methodology, estimation approach, literature, writing, presentation
- Referee-style output with 3-5 "what a top reviewer would ask"
- Output: `quality_reports/paper_review_[name].md`

### Research idea, text, or no file argument
→ Run **`research-review`** with the same argument.
- Interactive Codex MCP dialogue (you respond to criticisms)
- Use when you want to discuss/negotiate, not just get a report

### No argument provided
Ask: "What would you like to review? Provide a filename (`.R` or `.tex`) or describe your research idea."

---

## Other review skills (use directly when you know what you need)

| Skill | When to use |
|-------|-------------|
| `auto-review-loop` | Autonomous: Codex reviews → Claude implements fixes → re-reviews (4 rounds, no interruption) |
| `auto-review-loop-llm` | Same loop, using any OpenAI-compatible API instead of Codex |
| `code-review:code-review` | PR review on GitHub — 5 agents, posts high-confidence issues |
| `plan-review-loop` | Iterates review → rewrite a plan until it passes criteria |
