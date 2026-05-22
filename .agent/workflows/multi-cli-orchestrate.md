---
description: Run or preview a Codex + Claude + AGY orchestration workflow with configurable execution order. Trigger for natural requests like "review senior", "revisar com os 3", "usa os 3", "orquestra isso", "AGY primeiro", "Claude primeiro", "Codex primeiro", "corrigir ate low", or "validar com outro agente".
---

# Multi-CLI Orchestrate

Use this workflow to route a task through Codex, Claude, and AGY.

## Usage

```bash
ai-orchestrate --list
ai-orchestrate --task "$ARGUMENTS"
ai-orchestrate --preset adaptive --task "$ARGUMENTS"
ai-orchestrate --preset codex-first --execute --task "$ARGUMENTS"
ai-orchestrate --preset claude-first --execute --task "$ARGUMENTS"
ai-orchestrate --preset agy-first --execute --task "$ARGUMENTS"
ai-orchestrate --preset ui-heavy --execute --task "$ARGUMENTS"
ai-orchestrate --preset backend-critical --execute --task "$ARGUMENTS"
ai-orchestrate --preset migration-critical --execute --task "$ARGUMENTS"
ai-orchestrate --preset senior-code-review --execute --task "$ARGUMENTS"
ai-orchestrate --preset review-council --execute --task "$ARGUMENTS"
ai-orchestrate --from-run <run-dir> --preset codex-first --execute --auto-approve --task "$ARGUMENTS"
```

Default to dry-run unless the user explicitly asks to execute external CLIs.
Write steps stop before modification unless `--auto-approve` is present.
Use `--from-run` when approving a gated run.

Before executing, read local project rules and confirm the selected preset makes
sense for the task risk.
