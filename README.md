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
ai glm review   # Senior review multi-CLI usando GLM na perna Claude
ai fugu review  # Senior review multi-CLI usando Fugu na perna Codex
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
| GLM/Z.ai | `ai glm`, `ai glm review` | Claude Code via provider `glm` |
| Codex | `ai x` | `--dangerously-bypass-approvals-and-sandbox` |
| Sakana Fugu | `ai fugu`, `ai fugu-ultra`, `ai fugu review` | Codex profile `fugu` |
| Gemini | `ai g` | `--yolo` |
| Antigravity | `ai a` | _(nenhuma)_ |
| Multi-CLI Orchestration | `ai o`, `ai trio`, `ai review` | `ai-orchestrate` |

## Orquestração Multi-CLI

O atalho `ai o` integra a camada `~/.ai-orchestration`. O **senior review** roda
como um **council paralelo**: Codex, GLM, Fugu, Claude e AGY revisam o mesmo diff
de forma independente (sem se ancorar uns nos outros) e o **Codex sintetiza** um
relatório único e deduplicado. Tarefas de implementação continuam em cadeia
sequencial conforme o preset.

Roster padrão de review: `codex glm fugu claude agy`. Personalize com
`--agents "codex glm fugu"` ou `ORCH_REVIEW_AGENTS`. O Gemini é opt-in (o Google
descontinuou o free tier individual — `IneligibleTierError` — e é auto-pulado).

```bash
ai o                                      # Lista perfil detectado e presets
ai trio "mapear pagamentos"               # Alias curto para orquestração
ai review                                 # Council paralelo: codex+glm+fugu+claude+agy → síntese codex
ai o --preset senior-code-review --agents "codex glm fugu" --task "..."  # roster custom
ai review --via glm                       # (compat) força a perna Claude via GLM/Z.ai
ai review --via fugu                      # (compat) força a perna Codex via Sakana Fugu
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

A orquestração é robusta contra travas:

- **AGY** roda sob **PTY** (corrige o crash `bubbletea: could not open TTY`).
- **Codex/Fugu** usam `--output-last-message` + `model_reasoning_effort` (a saída
  é a revisão final, não um transcript de vários MB) e `-s read-only` em review.
- **Claude/GLM** rodam **read-only** de verdade em review (`--permission-mode plan`)
  e são **serializados entre si** (o binário `claude` tem trava global de
  instância — rodar dois em paralelo travava um). Os demais seguem paralelos.
- Prompts vão por **stdin** (evita `Argument list too long`); cada agente tem
  **timeout + retry** próprios e o `run_cli` mata o process group em SIGINT/SIGTERM.
- Um agente que falha nunca trava o council; a síntese diz quem participou.

Ajustes úteis:

```bash
ORCH_REVIEW_AGENTS="codex glm fugu claude agy"  # roster do council
ORCH_TIMEOUT=600                 # timeout padrão por agente (s)
ORCH_TIMEOUT_AGY=900             # timeout específico do AGY
ORCH_TIMEOUT_GLM=600             # timeout específico do GLM
ORCH_SYNTH_TIMEOUT=600           # timeout da síntese final
ORCH_RETRIES=1                   # retries por agente em falha transitória
ORCH_CODEX_EFFORT=medium         # reasoning effort do codex (low|medium|high)
ORCH_FUGU_EFFORT=high            # effort do fugu (Sakana só aceita high|xhigh|max)
ORCH_FUGU_MODEL=fugu-ultra       # Fugu Ultra por padrão (mais poderoso)
ORCH_CONTEXT_CHARS=12000         # limite de contexto (cadeia/relay)
ORCH_SKIP="gemini"               # pula agente problemático temporariamente
ORCH_SYNTH=glm                   # troca o sintetizador (codex|glm|fugu|claude|none)
```

Rode `ai install-skills` depois de atualizar o launcher para reinstalar as skills de review com guardrails anti-loop em Codex, Claude, AGY e Gemini.

O AGY recebe o repo atual explicitamente com `--add-dir <repo-root>` no atalho `ai a`, na orquestração e na skill instalada. Isso evita o caso em que o AGY abre sem enxergar os arquivos do projeto.

GLM e Fugu já participam do council por padrão. Os atalhos abaixo continuam
existindo para *forçar* uma única perna a usar o provider (modo compat):

```bash
ai glm review                 # força a perna Claude do council via GLM/Z.ai
ai fugu review                # força a perna Codex do council via Sakana Fugu
ai fugu-ultra review          # idem com Fugu Ultra
ai review --via glm
ai review --via fugu
```

> Gemini: o Google descontinuou o CLI free-tier individual (`IneligibleTierError`)
> e direciona para o Antigravity (`agy`). Por isso o Gemini fica fora do roster
> padrão e é auto-pulado; use `agy`, `glm` ou `fugu` no lugar.

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

## Sakana Fugu no Codex

O launcher instala o perfil Fugu do Codex e usa a API compatível com Responses da Sakana.

```bash
ai p add sakana                 # salva a SAKANA_API_KEY e instala o perfil
ai fugu                         # abre Codex com model fugu
ai fugu-ultra "tarefa pesada"   # abre Codex com model fugu-ultra
ai x --via sakana               # equivalente via Codex
ai x --via fugu-ultra           # Codex via Sakana Fugu Ultra
codex-fugu                      # wrapper direto criado em ~/.local/bin
```

Arquivos criados pelo setup:

- `${CODEX_HOME:-~/.codex}/fugu.json`
- `${CODEX_HOME:-~/.codex}/fugu.config.toml`
- bloco `[model_providers.sakana]` em `${CODEX_HOME:-~/.codex}/config.toml`

## Personalização

Rode `ai --config` ou edite `~/.local/bin/ai` — as flags ficam no topo do arquivo.

## Licença

MIT
