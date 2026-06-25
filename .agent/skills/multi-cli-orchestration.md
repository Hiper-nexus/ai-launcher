---
name: multi-cli-orchestration
description: Coordinate Codex, GLM, Fugu, Claude, and AGY for senior code review and implementation, with configurable roster, parallel council, and local project profiles. Trigger for "review senior", "revisar com os 3", "usa os 3", "orquestra isso", "chama Claude e AGY", "AGY primeiro", "Claude primeiro", "Codex primeiro", "validar com outro agente", "tarefa complexa", "arquitetura critica", "migração", "pagamentos", "auth", "Supabase", "segurança", "corrigir ate low", "PR review", or "diff review".
---

# Multi-CLI Orchestration

Use this skill when the user wants multiple AI CLIs to review or implement
together, or when the user wants to change who executes first.

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
- `~/.ai-orchestration/runs/` and `~/.ai-orchestration/reports/`

## Agents (review roster)

| Agent  | Engine                              | Role                                  |
|--------|-------------------------------------|---------------------------------------|
| codex  | OpenAI Codex (gpt-5.x)              | implementer / finalizer / synthesizer |
| glm    | GLM/Z.ai via the `claude` binary    | independent senior reviewer           |
| fugu   | Sakana **Fugu Ultra** via `codex -p fugu` | independent senior reviewer       |
| claude | Anthropic Claude (native login)     | architecture / security / risk critic |
| agy    | Google Antigravity (runs under PTY) | scout / decomposer / edge-case review |
| gemini | Google Gemini CLI — **opt-in**      | reviewer (free tier discontinued by Google; auto-skipped) |

Default review roster: `codex glm fugu claude agy`. Override with
`ORCH_REVIEW_AGENTS` or `--agents "codex glm fugu"`.

## Presets

- `senior-code-review` / `review-council`: **parallel council** — every roster
  agent reviews the same diff independently (no anchoring), then **Codex
  synthesizes** a single deduplicated report. This is the default for review.
- `adaptive`: choose from project and task signals.
- `codex-first` / `claude-first` / `agy-first`: implementation chains (sequential relay).
- `ui-heavy`: UI/UX workflow.
- `backend-critical`: auth, tenant, webhook, queue, provider, security workflow.
- `migration-critical`: SQL/data remediation workflow.

## How to Run

Senior code review (parallel council, dry-run / read-only):

```bash
ai-orchestrate --preset senior-code-review --task "code review senior do diff atual"
ai-orchestrate --preset senior-code-review --agents "codex glm fugu" --task "<task>"
```

Implementation chain:

```bash
ai-orchestrate --preset <preset> --task "<task>"
ai-orchestrate --preset <preset> --execute --task "<task>"
ai-orchestrate --from-run <run-dir> --preset <preset> --execute --auto-approve --task "<task>"
```

Inspect presets/roster: `ai-orchestrate --list`

## Reliability (why each agent now works)

- **AGY** runs under a real PTY, fixing the `bubbletea: could not open TTY` crash.
- **Codex/Fugu** use `--output-last-message` + `model_reasoning_effort` (default
  `medium`) and `-s read-only` in review, so output is the final review (not a
  multi-MB transcript) and faster.
- **Claude/GLM** review legs are truly read-only (`--permission-mode plan`) and are
  serialized with each other (the `claude` binary has a global single-instance
  lock; two in parallel hung one). Other agents stay parallel.
- All prompts are passed via **stdin** where supported, avoiding `Argument list too long`.
- Each agent gets a per-agent **timeout** and **retry** (transient failures only);
  `run_cli` kills the child process group on SIGINT/SIGTERM.
- **Gemini** auto-skips cleanly on `IneligibleTierError` (Google discontinued the
  individual free tier — use `agy`/`glm`/`fugu` instead).
- One failing agent never blocks the council; the synthesizer notes who participated.

## Tuning env vars

`ORCH_REVIEW_AGENTS`, `ORCH_SKIP`, `ORCH_SYNTH`, `ORCH_PARALLEL`,
`ORCH_TIMEOUT` (+ per-agent `ORCH_TIMEOUT_CODEX/GLM/FUGU/CLAUDE/AGY/GEMINI`),
`ORCH_SYNTH_TIMEOUT`, `ORCH_RETRIES`, `ORCH_BACKOFF`, `ORCH_CODEX_EFFORT`,
`ORCH_CONTEXT_CHARS`, `ORCH_GLM_BASE_URL`, `ORCH_GLM_MODEL`, `ORCH_GEMINI_MODEL`.

## Safety

- Read `AGENTS.md`, `CLAUDE.md`, and project manifests before acting.
- Do not read `.env`, auth files, local databases, or secret stores.
- Review presets are read-only for every agent; only the implementer writes in
  implementation presets, and only past an approved write gate.
- For migrations, payments, auth, tenant isolation, queues, and providers, use a
  review gate before finalizing.
