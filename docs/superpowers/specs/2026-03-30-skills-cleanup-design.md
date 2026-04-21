# Skills Cleanup Design
**Date:** 2026-03-30
**Status:** APPROVED
**Scope:** `.claude/skills/` in the Research project root

---

## Problem

The `.claude/skills/` directory accumulated 164 skills from multiple sources, most unrelated to ML methods for survival analysis dissertation work:

- ~70 LLM-specific skills (quantization, fine-tuning, serving, LLM agents)
- ~16 document-skills bundle duplicates (already available globally from plugin)
- ~18 miscellaneous irrelevant extras (humanizer, 20-ml-paper-writing, etc.)
- 9 dormant slide-workflow skills (marked dormant in CLAUDE.md but not archived)
- 5 project-specific skills with stale descriptions (lecture-focused, econometrics-framed)

**Goal:** Reduce to ~64 focused skills; add 2 missing auto-claude skills; fix 5 stale skill descriptions.

---

## Authoritative Source

Auto-claude-code-research skills are sourced from:
```
Research/Auto-claude-code-research-in-sleep/skills/
```
*(47 skills — this is the canonical reference, not `~/Auto-claude-code-research-in-sleep/`)*

---

## Actions

### 1. Add 2 missing auto-claude skills

Copy from `Research/Auto-claude-code-research-in-sleep/skills/` → `.claude/skills/`:
- `semantic-scholar`
- `vast-gpu`

### 2. Archive 9 dormant slide skills → `.claude/skills/_DORMANT/`

Do not delete — CLAUDE.md says reactivate for defense/job talk.

| Skill | Why dormant |
|-------|-------------|
| `translate-to-quarto` | Beamer→Quarto translation, slides inactive |
| `create-lecture` | Beamer lecture creation, slides inactive |
| `slide-excellence` | Slide review pipeline, slides inactive |
| `qa-quarto` | Quarto vs Beamer QA, slides inactive |
| `pedagogy-review` | Pedagogical review of slides, slides inactive |
| `extract-tikz` | TikZ→SVG for Quarto, slides inactive |
| `deploy` | GitHub Pages deployment of slides, slides inactive |
| `visual-audit` | Visual layout audit of slides, slides inactive |
| `devils-advocate` | Slide deck pedagogical challenges, slides inactive |

### 3. Delete ~104 irrelevant skills

#### 3a. LLM-specific (~70 skills)
Quantization, serving, fine-tuning, LLM models, LLM orchestration, LLM interpretability, LLM safety, NLP/vision/audio tools, vector databases, GPU-cloud-for-LLMs, LLM evaluation:

```
gptq awq gguf hqq bitsandbytes
vllm sglang tensorrt-llm llama-cpp
deepspeed accelerate trl-fine-tuning llama-factory axolotl unsloth peft
openrlhf grpo-rl-training simpo torchtitan megatron-core pytorch-fsdp2 moe-training
mamba rwkv nanogpt llava blip-2
langchain llamaindex dspy guidance outlines instructor crewai autogpt langsmith phoenix
transformer-lens nnsight saelens pyvene
llamaguard prompt-guard constitutional-ai nemo-guardrails nemo-curator nemo-evaluator
lm-evaluation-harness bigcode-evaluation-harness
sentence-transformers sentencepiece huggingface-tokenizers whisper
stable-diffusion segment-anything clip audiocraft
chroma faiss pinecone qdrant
modal lambda-labs skypilot
long-context flash-attention speculative-decoding litgpt miles
model-merging model-pruning knowledge-distillation slime verl
```

#### 3b. Document-skills bundle duplicates (~16 skills)
Available globally from `document-skills@anthropic-agent-skills` plugin — project-local copies are redundant:

```
algorithmic-art brand-guidelines canvas-design doc-coauthoring docx
frontend-design internal-comms mcp-builder pdf pptx
skill-creator slack-gif-creator theme-factory web-artifacts-builder
webapp-testing xlsx
```

#### 3c. Miscellaneous irrelevant extras (~2 skills)
```
20-ml-paper-writing humanizer
```

### 4. Fix 5 project-specific skills

| Skill | Problem | Fix |
|-------|---------|-----|
| `compile-latex` | Description says "Use when compiling lecture slides"; Step 1 hardcodes `Slides/` | Update description to cover manuscripts; add `Papers/` compilation path alongside `Slides/` |
| `proofread` | Description says "lecture files"; scans only `Slides/` and `Quarto/` | Update description to "manuscripts and documents"; add `Papers/*.tex` scan target |
| `validate-bib` | Scan targets list only `Slides/*.tex` and `Quarto/*.qmd` | Add `Papers/*.tex` to the Files to scan section |
| `review-paper` | Dimensions 2 & 3 use econometrics framing: "Identification Strategy" (DiD/IV/RDD), "Econometric Specification" | Rename to "Statistical Methodology" and "Estimation Approach"; replace causal-inference econometrics examples with survival analysis / biostatistics framing |
| `data-analysis` | Panel-data econometrics workflow (`fixest`, "regress wages on education", CPS data) | Reframe as R analysis for survival/simulation data: replace `fixest`→`survival`/`tidyverse`, update example to simulation output analysis, remove econometrics-specific guidance |

---

## Outcome

| Category | Count |
|----------|-------|
| Project-specific skills (incl. 5 fixed) | 11 |
| Auto-claude-code-research skills (incl. 2 added) | 47 |
| General ML skills (non-LLM): `mlflow` `weights-and-biases` `pytorch-lightning` `tensorboard` `ray-train` `ray-data` | 6 |
| **Total active** | **~64** |
| Archived to `_DORMANT/` | 9 |
| Deleted | ~104 |

---

## Verification

After cleanup:
1. `ls .claude/skills/ | wc -l` should be ~65 (64 active + `_DORMANT/` dir)
2. All 47 auto-claude skills present (run from project root): `comm -23 <(ls Auto-claude-code-research-in-sleep/skills/ | sort) <(ls .claude/skills/ | grep -v _DORMANT | sort)` → empty
3. No LLM framework skills remain: `ls .claude/skills/ | grep -E "vllm|llamaindex|deepspeed|trl"` → empty
4. `_DORMANT/` contains exactly 9 slide skills
5. All 5 fixed skills have updated descriptions matching biostatistics/manuscript scope

---

## Notes

- `formula-derivation` and `proof-writer` appear in both auto-claude and project — auto-claude version takes precedence; verify content matches before overwriting
- Document-skills bundle skills remain available globally via `~/.claude/skills/` from the installed plugin — no functionality lost by removing project-local copies
- `vast-gpu` is a GPU rental skill from auto-claude; keep but note it's for cloud GPU, not SLURM — not the primary execution environment for this project
