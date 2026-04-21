# Patches

Local customizations against third-party submodules, saved here as `.patch`
files so they can be re-applied if the submodule is ever updated from upstream.

## How to apply a patch

```bash
# From the submodule root:
cd <submodule>
git apply --3way /path/to/patch.patch
```

## Index

| Date | Patch | Submodule | Purpose |
|------|-------|-----------|---------|
| 2026-04-21 | `2026-04-21_auto-claude-code-SKILL-fallback.patch` | `.cursor/skills/Auto-claude-code-research-in-sleep` | Add reviewer-subagent fallback to `skills/auto-paper-improvement-loop/SKILL.md` for when Codex MCP is unavailable. Mirrors the fallback work in the parent repo's own auto-paper-improvement-loop skill. |
