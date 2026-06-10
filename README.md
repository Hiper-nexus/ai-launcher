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
ai conta        # Menu de contas Claude (troca sem logout, macOS)
ai conta save trabalho   # Salva a conta logada atual como "trabalho"
ai c --conta pessoal     # Troca para a conta "pessoal" e já lança o Claude
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

## Contas Claude (multi-conta sem logout — macOS)

Troque entre várias contas Claude (pessoal, trabalho, backup) sem o ciclo logout → browser → login. As credenciais OAuth de cada conta ficam salvas no **Keychain do macOS** (nunca em texto plano); metadados em `~/.local/share/ai-launcher/accounts/` com permissão `0600`.

```bash
ai conta add pessoal     # cadastra conta NOVA: login guiado, com rollback automático
ai conta save trabalho   # salva a conta logada atual como "trabalho"
ai conta ls              # lista contas — ● marca a ativa
ai conta status          # uso de cada conta (janela 5h / 7 dias) + horário de reset
ai conta use pessoal     # ativa a conta "pessoal" na hora
ai conta rm backup       # remove um backup salvo
ai c --conta trabalho    # troca de conta e já lança o Claude
ai conta                 # menu interativo (também é a opção 9 do menu principal)
```

**Auto-switch**: com 2+ contas salvas, `ai c` verifica a janela de 5h antes de lançar — se a conta ativa esgotou, troca automaticamente para outra com quota (fail-open: problema de rede nunca bloqueia o launch). Desligar: `AI_CONTA_AUTO_SWITCH=false`. Trocar mais cedo: `AI_CONTA_AUTO_THRESHOLD=95`.

Como funciona: o Claude Code guarda a credencial ativa no Keychain (`Claude Code-credentials`) e os metadados em `~/.claude.json`. O launcher fotografa a conta ativa antes de cada troca (refresh tokens rotacionam) e restaura a escolhida no slot ativo, atualizando o `oauthAccount` com escrita atômica e backup `.bak-ai-launcher`.

Avisos:

- Sessões `claude` já abertas continuam na conta anterior até serem reiniciadas.
- Se uma conta ficar semanas sem uso, o refresh token pode expirar no servidor — refaça `/login` nela e `ai conta save` de novo.
- Mecanismo não-oficial (mesma técnica de apps como o Claude Switcher): se a Anthropic mudar o formato do Keychain, ajuste o script.

## Features

- Menu interativo com versão e status de instalação
- Não exige `*_API_KEY`; o launcher delega autenticação para cada CLI
- Histórico de uso
- Passagem de prompt direto via linha de comando
- Flags configuráveis no topo do script
- Contas Claude múltiplas com troca sem logout (Keychain, macOS)
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
