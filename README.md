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
ai fugu         # Codex via Sakana Fugu
ai fugu-ultra   # Fugu Ultra (alias da versão atual: V1.1)
ai fugu-ultra-v1.0  # Fugu Ultra V1.0
ai fugu-ultra-v1.1  # Fugu Ultra V1.1
ai fugu-cyber   # Fugu Cyber (alias da versão atual: V1.0)
ai fugu-cyber-v1.0  # Fugu Cyber V1.0
ai g            # Gemini direto
ai k            # Kimi Code direto
ai cu           # Cursor Agent direto
ai c "prompt"   # Claude com prompt
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
| GLM/Z.ai | `ai glm` | Claude Code via provider `glm` |
| Codex | `ai x` | `--dangerously-bypass-approvals-and-sandbox` |
| Sakana Fugu | `ai fugu`, `ai fugu-ultra[-v1.x]`, `ai fugu-cyber[-v1.0]` | Codex profile `fugu` |
| Gemini | `ai g` | `--yolo` |
| Kimi Code | `ai k` | `--yolo` |
| Grok (xAI) | `ai gr` | `--always-approve --permission-mode bypassPermissions` |
| Qoder | `ai q` | `--dangerously-skip-permissions` |
| Cursor Agent | `ai cu` | `--yolo --sandbox disabled --approve-mcps --trust` |
| Antigravity | `ai a` | _(nenhuma)_ |

> **Cursor Agent** — instale com `curl https://cursor.com/install -fsS | bash`. O instalador
> cria dois symlinks: `~/.local/bin/agent` (primário) e `~/.local/bin/cursor-agent` (legado),
> **sobrescrevendo** um `agent` pré-existente — o Grok Build usa esse mesmo nome. O launcher
> invoca `cursor-agent` justamente para não depender do nome disputado; se você usa o Grok
> por `agent`, restaure com `ln -sf ~/.grok/bin/agent ~/.local/bin/agent` após instalar.

## Codex Security (scanner da OpenAI)

Não é um agente interativo como as CLIs acima — é um scanner de vulnerabilidades com
subcomandos próprios, então tem um atalho separado que **repassa argumentos verbatim**:

```bash
ai sec                             # = codex-security scan .  (repo atual)
ai sec login                       # autentica (ChatGPT ou OPENAI_API_KEY)
ai sec scan . --diff origin/main   # escaneia só o diff contra uma base
ai sec scan . --mode deep          # scan profundo
ai sec scans list                  # lista scans salvos
ai sec patch                       # aplica correção de findings
ai sec export --format sarif       # exporta findings (CSV/JSON/SARIF)
```

Instalação: `npm install -g @openai/codex-security` (requer Node 22+ e Python 3.10+).

O runtime do plugin exige **Python 3.10+**, mas o `python3` do macOS costuma ser 3.9. Nos
comandos `scan`/`bulk-scan` o launcher detecta isso e injeta `--python` apontando para o
primeiro interpretador compatível do PATH (`python3.14` → `python3.10`). Se você passar
`--python` explicitamente, o seu vence — nada é duplicado. Outros subcomandos não recebem
a flag, que só existe no scan.

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

### Contas Codex (mesmos recursos)

O Codex CLI tem o conjunto espelhado, com o prefixo `x`:

```bash
ai xconta add pessoal    # cadastra conta Codex nova (login guiado)
ai xconta ls             # lista contas Codex
ai xconta status         # uso de cada conta (janela 5h / semanal do ChatGPT)
ai xconta use trabalho   # ativa a conta Codex "trabalho"
ai x --conta pessoal     # troca e já lança o Codex
```

A sessão do Codex fica em `~/.codex/auth.json` (modo arquivo — exige `cli_auth_credentials_store = "file"` no `~/.codex/config.toml`). Tokens salvos são **renovados automaticamente** ao consultar o uso, mantendo as sessões vivas. Auto-switch funciona igual ao do Claude.

### Notas técnicas

- **Cache de uso** (`usage-cache.json`, TTL 120s): o endpoint de uso tem rate limit; o launcher reusa leituras recentes para `status` e auto-switch ficarem rápidos e não serem bloqueados. Ajuste: `AI_USAGE_CACHE_TTL=60`.
- **Conta ativa do Claude**: o launcher nunca renova o token OAuth da conta ativa (o Claude Code é o dono e o rotaciona) — apenas os backups inativos são renovados, evitando conflito. Por isso `ai conta add` não usa `logout` (que revogaria o backup recém-salvo).
- **Paridade com o Claude Switcher (Symbioose)**: troca Claude + Codex, estado separado por provider, uso ao vivo, auto-switch por provider, backups no Keychain. O que fica de fora é o ícone persistente na barra de menu (isso é um app nativo; aqui o equivalente é `ai conta status` sob demanda).

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
- Providers alternativos (GLM/Z.ai, Sakana Fugu, OpenRouter, DeepSeek, Ollama, LM Studio, LiteLLM)
- Picker de repos conhecidos quando lançado fora de um repo git
- Funciona em Linux e no macOS padrão

## Pré-requisitos

Instale as CLIs que quiser usar:

```bash
npm install -g @anthropic-ai/claude-code   # Claude
npm install -g @openai/codex               # Codex
npm install -g @google/gemini-cli           # Gemini
curl -fsSL https://code.kimi.com/kimi-code/install.sh | bash  # Kimi Code
curl -fsSL https://antigravity.google/cli/install.sh | bash  # Antigravity
```

Depois, autentique cada ferramenta usando o fluxo nativo dela (`claude`, `codex` e `gemini`). O launcher não valida nem exige variáveis como `ANTHROPIC_API_KEY`, `OPENAI_API_KEY` ou `GEMINI_API_KEY`.

## Sakana Fugu no Codex

O launcher instala o perfil Fugu do Codex e usa a API compatível com Responses da Sakana.

Modelos suportados:

| Model ID | Descrição |
|---|---|
| `fugu` | Modelo Fugu padrão. |
| `fugu-ultra` | Alias estável da versão atual do Fugu Ultra (`fugu-ultra-v1.1`). |
| `fugu-ultra-v1.0` | Fugu Ultra V1.0, também conhecido como `fugu-ultra-20260615`. |
| `fugu-ultra-v1.1` | Fugu Ultra V1.1. |
| `fugu-cyber` | Alias estável do Fugu Cyber (`fugu-cyber-v1.0`). |
| `fugu-cyber-v1.0` | Fugu Cyber V1.0. |

Fugu Cyber exige acesso aprovado no pay-as-you-go billing da Sakana.

```bash
ai p add sakana                 # salva a SAKANA_API_KEY e instala o perfil
ai fugu                         # abre Codex com model fugu
ai fugu-ultra "tarefa pesada"   # alias -> fugu-ultra-v1.1
ai fugu-ultra-v1.0 "compat"     # abre Fugu Ultra V1.0
ai fugu-ultra-v1.1 "pesada"     # abre Fugu Ultra V1.1
ai fugu-ultra-20260615 "compat" # alias histórico -> fugu-ultra-v1.0
ai fugu-cyber "auditar auth"    # alias -> fugu-cyber-v1.0
ai fugu-cyber-v1.0 "auditar"    # abre Fugu Cyber V1.0
ai x --via sakana               # equivalente via Codex
ai x --via fugu-ultra           # alias -> Fugu Ultra V1.1
ai x --via fugu-ultra-v1.0      # Codex via Fugu Ultra V1.0
ai x --via fugu-cyber           # alias -> Fugu Cyber V1.0
codex-fugu                      # wrapper direto criado em ~/.local/bin
codex-fugu-cyber                # wrapper direto para Fugu Cyber
```

Arquivos criados pelo setup:

- `${CODEX_HOME:-~/.codex}/fugu.json`
- `${CODEX_HOME:-~/.codex}/fugu.config.toml`
- `${HOME}/.local/bin/codex-fugu`
- `${HOME}/.local/bin/codex-fugu-cyber`
- bloco `[model_providers.sakana]` em `${CODEX_HOME:-~/.codex}/config.toml`

## Personalização

Rode `ai --config` ou edite `~/.local/bin/ai` — as flags ficam no topo do arquivo.

## Licença

MIT
