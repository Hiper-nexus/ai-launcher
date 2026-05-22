---
name: multi-cli-orchestration
description: Coordinate Codex, Claude, and AGY with configurable execution order and local project profiles. Trigger for "review senior", "revisar com os 3", "usa os 3", "orquestra isso", "chama Claude e AGY", "AGY primeiro", "Claude primeiro", "Codex primeiro", "validar com outro agente", "tarefa complexa", "arquitetura critica", "migração", "pagamentos", "auth", "Supabase", "segurança", "corrigir ate low", "PR review", or "diff review".
---

# Multi-CLI Orchestration

Use this skill when the user wants Codex, Claude, and AGY to work together, or
when the user wants to change who executes first.

Natural phrases that should trigger this workflow:

- "review senior", "revisar com os 3", "corrigir ate low", "validar com outro agente"
- "usa os 3", "orquestra isso", "chama Claude e AGY", "Codex + Claude + AGY"
- "AGY primeiro", "Claude primeiro", "Codex primeiro"
- architecture, migration, auth, payment, Supabase, tenant, webhook, queue, provider, or security work

Shared configuration:

- `~/.ai-orchestration/config.json`
- `~/.ai-orchestration/project-profiles.json`
- `~/.local/bin/ai-orchestrate`
- `~/.ai-orchestration/scripts/`
- `~/.ai-orchestration/templates/`
- `~/.ai-orchestration/runs/`
- `~/.ai-orchestration/reports/`

## Roles

- Codex: primary implementer, test runner, finalizer.
- Claude: architecture critic, product/security reviewer, risk planner.
- AGY: scout, task decomposer, independent reviewer.

## Presets

- `adaptive`: choose from project and task signals.
- `codex-first`: Codex plans/implements, AGY scouts, Claude reviews.
- `claude-first`: Claude plans, AGY cross-checks, Codex implements.
- `agy-first`: AGY decomposes, Claude shapes, Codex implements.
- `ui-heavy`: UI/UX workflow.
- `backend-critical`: auth, tenant, webhook, queue, provider, and security workflow.
- `migration-critical`: SQL/data remediation workflow.
- `senior-code-review`: Codex reviews first, AGY second, Claude third, then Codex synthesizes.
- `review-council`: compatibility preset using the same senior review order.

## How to Run

Dry-run:

```bash
ai-orchestrate --task "<task>"
ai-orchestrate --preset <preset> --task "<task>"
```

Execute:

```bash
ai-orchestrate --preset <preset> --execute --task "<task>"
ai-orchestrate --from-run <run-dir> --preset <preset> --execute --auto-approve --task "<task>"
```

Write steps stop at a decision gate unless `--auto-approve` is present.
Use `--from-run` when approving so write steps consume the outputs you reviewed.

Inspect local profile:

```bash
ai-orchestrate --list
```

## Safety

- Read `AGENTS.md`, `CLAUDE.md`, and project manifests before acting.
- Do not read `.env`, auth files, local databases, or secret stores.
- Advisory actors are read-only.
- Only the selected implementation actor may edit files.
- Do not cross a write gate without explicit approval.
- Resume approved gates with `--from-run` so implementation uses the reviewed outputs.
- For migrations, payments, auth, tenant isolation, queues, and providers, use a review gate before finalizing.
