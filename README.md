# AI CLI Launcher

Lançador interativo para CLIs de IA com flags pré-configuradas. Nunca mais esqueça aquele comando gigante.

## Instalação

```bash
curl -fsSL https://raw.githubusercontent.com/cleofasvolarehost/ai-launcher/main/install.sh | bash
```

Compatível com o Bash padrão do macOS (`3.2`) e com Linux moderno. Não precisa instalar Bash via Homebrew.

Ou manualmente:

```bash
curl -fsSL https://raw.githubusercontent.com/cleofasvolarehost/ai-launcher/main/ai -o ~/.local/bin/ai
chmod +x ~/.local/bin/ai
```

## Uso

```bash
ai              # Menu interativo com status de cada CLI
ai c            # Claude Code direto
ai x            # Codex direto
ai g            # Gemini direto
ai o            # Orquestração Codex + AGY + Claude
ai trio "prompt" # Alias curto para orquestração
ai review       # Alias curto para code review senior
ai c "prompt"   # Claude com prompt
ai o "prompt"   # Dry-run adaptativo da orquestração
ai o review     # Dry-run do code review senior: Codex -> AGY -> Claude -> síntese
ai --history    # Ver histórico de uso
ai --config     # Editar flags
ai --help       # Ajuda
```

## CLIs suportadas

| CLI | Atalho | Flag padrão |
|-----|--------|-------------|
| Claude Code | `ai c` | `--dangerously-skip-permissions` |
| Codex | `ai x` | `--dangerously-bypass-approvals-and-sandbox` |
| Gemini | `ai g` | `--yolo` |
| Antigravity | `ai a` | _(nenhuma)_ |
| Multi-CLI Orchestration | `ai o`, `ai trio`, `ai review` | `ai-orchestrate` |

## Orquestração Multi-CLI

O atalho `ai o` integra a camada `~/.ai-orchestration`, que roteia tarefas entre Codex, AGY e Claude conforme o projeto atual.

```bash
ai o                                      # Lista perfil detectado e presets
ai trio "mapear pagamentos"               # Alias curto para orquestração
ai review                                 # Dry-run do senior review do diff atual
ai review --execute                       # Executa senior review do diff atual
ai o "implementar fix aprovado"           # Dry-run adaptativo
ai o --preset agy-first --task "mapear pagamentos"
ai o --preset codex-first --execute --task "analisar fix"
ai o --from-run ~/.ai-orchestration/runs/<run> --execute --auto-approve
ai o review                               # Dry-run do senior review do diff atual
ai o review --execute                     # Executa senior review do diff atual
ai o status                               # Status da camada de orquestração
ai o collect                              # Gera report do último run
```

Dentro do Codex, Claude ou AGY, você não precisa decorar o nome técnico da skill. Frases como "review senior", "revisar com os 3", "usa os 3", "orquestra isso", "AGY primeiro", "Claude primeiro", "validar com outro agente" e "corrigir ate low" foram adicionadas como gatilhos naturais para a orquestração.

Presets principais:

- `adaptive`
- `senior-code-review`
- `codex-first`
- `agy-first`
- `claude-first`
- `ui-heavy`
- `backend-critical`
- `migration-critical`

## Features

- Menu interativo com versão e status de instalação
- Não exige `*_API_KEY`; o launcher delega autenticação para cada CLI
- Histórico de uso
- Passagem de prompt direto via linha de comando
- Flags configuráveis no topo do script
- Providers alternativos (OpenRouter, DeepSeek, Ollama, LM Studio, LiteLLM)
- Orquestração Codex + AGY + Claude com presets e gate antes de escrita
- Picker de repos conhecidos quando lançado fora de um repo git
- Funciona em Linux e no macOS padrão

## Pré-requisitos

Instale as CLIs que quiser usar:

```bash
npm install -g @anthropic-ai/claude-code   # Claude
npm install -g @openai/codex               # Codex
npm install -g @google/gemini-cli           # Gemini
curl -fsSL https://antigravity.google/cli/install.sh | bash  # Antigravity
```

Depois, autentique cada ferramenta usando o fluxo nativo dela (`claude`, `codex` e `gemini`). O launcher não valida nem exige variáveis como `ANTHROPIC_API_KEY`, `OPENAI_API_KEY` ou `GEMINI_API_KEY`.

## Personalização

Rode `ai --config` ou edite `~/.local/bin/ai` — as flags ficam no topo do arquivo.

## Licença

MIT
