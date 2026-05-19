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
ai c "prompt"   # Claude com prompt
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

## Features

- Menu interativo com versão e status de instalação
- Não exige `*_API_KEY`; o launcher delega autenticação para cada CLI
- Histórico de uso
- Passagem de prompt direto via linha de comando
- Flags configuráveis no topo do script
- Providers alternativos (OpenRouter, DeepSeek, Ollama, LM Studio, LiteLLM)
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
