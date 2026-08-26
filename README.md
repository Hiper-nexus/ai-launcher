# AI CLI Launcher

Lançador interativo para CLIs de IA com flags pré-configuradas. Nunca mais esqueça aquele comando gigante.

## Instalação

```bash
curl -fsSL https://raw.githubusercontent.com/Hiper-nexus/ai-launcher/main/install.sh | bash
```

Compatível com o Bash padrão do macOS (`3.2`) e com Linux moderno. Não precisa instalar Bash via Homebrew.

Ou manualmente:

```bash
curl -fsSL https://raw.githubusercontent.com/Hiper-nexus/ai-launcher/main/ai -o ~/.local/bin/ai
chmod +x ~/.local/bin/ai
```

## Uso

```bash
ai              # Menu interativo com status de cada CLI
ai c            # Claude Code direto
ai glm          # GLM 5.3 (Z.ai) via Claude Code — /model oferece o 5.3 Flash
ai gf           # sessão inteira no GLM 5.3 Flash (aliases: glm-flash, zf, flash)
ai ds           # DeepSeek V4-Flash via Claude Code
ai ds-pro       # DeepSeek V4-Pro (GA) via Claude Code
ai x            # Codex direto
ai sol          # Codex GPT-5.6 Sol com janela de 1M de contexto (aliases: x-1m, x1m)
ai fugu         # Codex via Sakana Fugu
ai claude-fugu  # Claude Code via endpoint Anthropic-compatible da Sakana
ai fugu -c model_reasoning_effort=xhigh  # Fugu com raciocínio profundo
ai fugu-ultra   # Fugu Ultra (alias da versão atual: V1.1)
ai fugu-ultra -c model_reasoning_effort=max  # máximo disponível no Ultra V1.1
ai fugu-ultra-v1.0  # Fugu Ultra V1.0
ai fugu-ultra-v1.1  # Fugu Ultra V1.1
ai fugu-cyber   # Fugu Cyber — orquestração p/ segurança (acesso sob formulário)
ai g            # Gemini direto
ai k            # Kimi Code direto
ai cu           # Cursor Agent direto
ai omp          # omp (oh-my-pi) direto — 60+ providers num só agente
ai omp models   # Providers/modelos que o omp enxerga hoje
ai ol           # Ollama Cloud (roda em ollama.com, não na sua máquina)
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
| GLM/Z.ai | `ai glm` | Claude Code via provider `glm` — **GLM 5.3** nos slots sonnet/opus e **GLM 5.3 Flash** no haiku (troque no `/model` sem sair da sessão). Os modelCodes carregam o sufixo `[1m]` (mecanismo do próprio Claude Code para janela de 1M em modelos não reconhecidos — o client faz strip antes de chamar a API) |
| GLM Flash | `ai gf`, `ai glm-flash` | Mesmo provider `glm` — **GLM 5.3 Flash** (também 1M) em **todos** os slots |
| Muse Spark (Meta AI) | `ai ms` | CLI própria (REPL/one-shot) via `api.meta.ai`; `ai ms claude` abre no Claude Code (yolo); `ai ms model` escolhe o modelo para os dois caminhos |
| Codex | `ai x` | `--dangerously-bypass-approvals-and-sandbox` |
| Codex Sol 1M | `ai sol` | idem + `-m gpt-5.6-sol -c model_context_window=1000000 -c model_auto_compact_token_limit=900000` |
| Sakana Fugu | `ai fugu`, `ai fugu-ultra[-v1.x]`, `ai fugu-cyber`, `ai claude-fugu` | Codex profile `fugu` ou endpoint Anthropic-compatible no Claude Code |
| Gemini | `ai g` | `--yolo` |
| Kimi Code | `ai k` | `--yolo` |
| Grok (xAI) | `ai gr` | `--always-approve --permission-mode bypassPermissions` |
| Qoder | `ai q` | `--dangerously-skip-permissions` |
| Cursor Agent | `ai cu` | `--yolo --sandbox disabled --approve-mcps --trust` |
| omp (oh-my-pi) | `ai omp`, `ai o` | `--yolo` — agente único com 60+ providers; `-m` troca de modelo |
| Antigravity | `ai a` | _(nenhuma)_ |
| Ollama Cloud | `ai ol` | roda em `ollama.com`, modelo `minimax-m3` |
| HF Endpoint (dedicado) | `ai hf` | seu modelo uncensored, servido por vLLM na Hugging Face |
| Featherless | `ai fl` | catálogo uncensored via API (21 mil+ modelos, plano pago) |
| Qwen (Alibaba) | `ai qw` | Qwen-Max via Model Studio — CLI própria **ou** dentro do Claude Code |
| Prime Agent | `ai prime`, `ai pa` | sessão persistente (sem one-shot); subcomandos e `--resume` passam direto |

## omp (oh-my-pi)

Agente de terminal com harness próprio (LSP, DAP, subagents, plan mode, hashline
edits) e **60+ providers num binário só** — em vez de uma CLI por provider, você
troca de modelo com `/model` dentro da sessão ou com `-m` na linha de comando.

```bash
ai omp                       # REPL no modo yolo
ai o                         # atalho curto
ai omp "refatora esse hook"  # one-shot (modo print)
ai omp -m glm-5.2 "tarefa"   # outro modelo (fuzzy: "opus", "glm-5.2", "zai/glm-5.2")
ai omp --via glm "tarefa"    # prende num provider (glm→zai, qwen→alibaba-token-plan…)
ai omp -c                    # continua a última sessão
ai omp models                # providers/modelos disponíveis agora
ai omp usage                 # uso e limites de cada conta autenticada
```

Instalação (uma vez por máquina):

```bash
brew install can1357/tap/omp     # ou: curl -fsSL https://omp.sh/install | sh
brew upgrade can1357/tap/omp     # atualizar
```

### Máquina nova: `ai omp tune`

```bash
ai omp tune          # afinação + credenciais
ai omp tune --dry    # mostra o que faria, sem gravar
ai omp tune config   # só as settings
ai omp tune env      # só as keys
```

Duas metades com destinos diferentes:

- **Afinação** — vive neste repo (array `OMP_TUNE` no script). O `config.yml` do
  omp só tem roles de modelo e flags de comportamento, nenhum segredo, então
  versionar é seguro e a mesma afinação roda em qualquer máquina.
- **Credenciais** — saem do `providers.conf` local (chmod 600) para
  `~/.omp/agent/.env`, também 600. Nunca passam pelo git.

É idempotente, preserva variáveis que você escreveu à mão no `.env`, e uma chave
que não exista na versão instalada do omp é reportada e pulada em vez de abortar
o resto. `ai omp setup` continua abrindo o wizard do próprio omp.

O que a afinação liga, e por quê:

| chave | por quê |
|---|---|
| `lsp.diagnosticsOnEdit` | por padrão o LSP só reporta em `write`; o agente **edita** muito mais do que cria arquivo |
| `checkpoint.enabled` | expõe `checkpoint`/`rewind` — undo de turno |
| `features.unexpectedStopDetection` | reprompta quando ele diz "vou continuar" e para |
| `retry.fallbackChains` | com vários providers ligados, um 429 cai na cadeia em vez de parar |
| `task.isolation.mode: auto` | subagents editam em paralelo em clone CoW, sem conflito |
| `task.enableLsp` | subagent escrevia código sem diagnostics |
| `bashInterceptor.enabled` | bloqueia `cat`/`sed -i` e força as ferramentas próprias |
| `memory.backend: mnemopi` | pipeline no role `smol`; o backend `local` usa o `default` (caro) |
| `bash.patterns` | 14 regras `deny` — o modo yolo do omp ignora o aviso de comando crítico |

### Roteamento de modelo por folga de cota

`modelRoles` é a tabela de roteamento: o omp troca de modelo **sozinho, no meio da
missão**, conforme a função. Cada role tem uma frequência de chamada diferente, e é
isso — não só capacidade bruta — que decide onde cada modelo entra:

| role | quando dispara | frequência | critério |
|---|---|---|---|
| `default` | turno normal | alta | o mais forte, na assinatura mais folgada |
| `slow` | raciocínio profundo | baixa | o mais forte, sem teto de effort |
| `plan` | plan mode | 1x por missão | cabe um modelo forte de cota escassa |
| `smol` | fan-out de subagent, memória, títulos | **muito alta** | cota ociosa; effort baixo |
| `advisor` | revisão de cada turno | alta | bom revisor, conta pouco usada |
| `commit` | mensagem de commit | baixa | o mais barato que existir |
| `vision` | imagens | baixa | precisa aceitar imagem |

Rode `ai omp usage` antes de decidir: ele mostra o percentual consumido de cada conta.
Um role de frequência alta apontado para a assinatura mais gasta é o erro clássico —
e o inverso (cota diária ociosa absorvendo o fan-out) é dinheiro achado no chão.

`retry.fallbackChains` cobre o resto: quando o primário bate limite, o turno **termina**
no próximo da cadeia em vez de morrer no 429.

### Providers por API key

O omp lê `~/.omp/agent/.env` (chmod 600) antes de qualquer lookup de provider.
As keys que o launcher já guarda em `providers.conf` mapeiam assim:

| Slot no launcher | Variável no `.env` do omp | Provider no omp |
|------------------|---------------------------|-----------------|
| `glm` | `ZAI_API_KEY` | `zai` (GLM Coding Plan) |
| `sakana` | `SAKANA_API_KEY` | `sakana` (Fugu) |
| `deepseek` | `DEEPSEEK_API_KEY` | `deepseek` |
| `qwen` | `ALIBABA_TOKEN_PLAN_API_KEY` | `alibaba-token-plan` |
| `muse-spark` | `META_API_KEY` | `meta` (Muse Spark) |

Precedência: env já exportado > `<cwd>/.env` > `~/.omp/agent/.env` > `~/.omp/.env` > `~/.env`.

### Providers por OAuth

**Normalmente você não precisa fazer nada.** O omp lê as credenciais que as
outras CLIs já gravaram no disco (`~/.codex`, `~/.cursor`, `~/.antigravity`,
`~/.kimi`, `~/.grok`), então Codex, Cursor, Antigravity, Kimi e SuperGrok
aparecem em `ai omp usage` sem um único login. Confira antes de logar de novo.

Se algum não aparecer, entre com `/login <provider>` **dentro** da sessão do omp
(abre o browser). Cada provider é independente:

| CLI equivalente | Comando no omp |
|-----------------|----------------|
| Claude Code | `/login anthropic` |
| Codex (ChatGPT) | `/login openai-codex` |
| Gemini | `/login google-gemini-cli` |
| Antigravity | `/login google-antigravity` |
| Kimi Code | `/login kimi-code` |
| Grok / SuperGrok | `/login xai-oauth` |
| Cursor | `/login cursor` |
| GitHub Copilot | `/login github-copilot` |
| Qwen Portal | `/login qwen-portal` |

Anthropic aceita **várias contas**: rode `/login anthropic` uma vez por conta e o
omp faz rodízio com backoff por credencial (`ai omp usage` mostra o saldo de cada uma).

## Ollama

Por padrão o `ai ol` usa o **Ollama Cloud**: a inferência acontece nos servidores da Ollama, não na sua máquina. Não precisa de GPU, de daemon local nem do binário `ollama` — só de uma API key e do `python3`.

```bash
ai ol key                    # salva a API key (https://ollama.com/settings/keys)
ai ol                        # chat interativo no modelo padrão (minimax-m3)
ai ol "resume esse stack trace"   # one-shot
ai ol -m glm-5.2             # escolhe outro modelo cloud na hora
ai ol ls                     # lista os modelos servidos pelo cloud
ai ol local qwen3.5:9b       # roda na sua GPU (exige o binário ollama)
ai ol login                  # login por browser, habilita o REPL nativo 'ollama run'
```

No REPL: `/limpar` zera o contexto, `/sair` encerra.

Defaults por env var: `AI_OLLAMA_CLOUD_MODEL` (cloud) e `AI_OLLAMA_LOCAL_MODEL` (local). A key fica em `providers.conf` com `chmod 600`; `OLLAMA_API_KEY` no ambiente tem prioridade.

**Cloud x local — o que roda onde:** o Ollama Cloud serve apenas os modelos oficiais da library marcados com a tag `cloud` (18 no momento: `minimax-m3`, `glm-5.2`, `kimi-k3`, `qwen3.5:397b`, `gpt-oss:120b`, `deepseek-v4-pro`…). Modelos de comunidade — os que ficam num namespace de usuário, como `AI-TAVS/Qwen3.6-27B-Uncensored` — são **apenas artefatos de download**: a Ollama não roda inferência deles, e pedi-los na API do cloud devolve `404 model not found`. Para esses, use `ai ol local` (ou hospede o GGUF você mesmo num serviço de GPU).

## HF Endpoint (modelo dedicado uncensored)

`ai hf` fala com um **Inference Endpoint dedicado** seu na Hugging Face, servido por vLLM (API compatível com OpenAI). Diferente do Ollama Cloud (catálogo fixo, tudo alinhado), aqui **você escolhe qualquer peso do Hub** — inclusive modelos abliterated/uncensored — e o endpoint é só seu, sem fila compartilhada.

```bash
ai hf endpoint <url>         # salva a URL do endpoint (1x por máquina)
ai hf key                    # salva o token HF (1x por máquina)
ai hf                        # chat interativo (REPL)
ai hf "auditar esse binário" # one-shot
ai hf codex                  # abre o Codex usando este modelo
ai hf status                 # estado do endpoint / réplicas
ai hf menu                   # painel com o resumo de uso
```

**Modelo atual:** `thisnick/Llama-3.3-70B-Instruct-abliterated-FP8-Dynamic` — 70B sem censura, arquitetura Llama (100% suportada no vLLM), FP8, **não-thinking** (responde direto, sem despejar raciocínio). Bom em análise/engenharia reversa (identifica XOR, hashes, desofusca e reescreve código legível) e não recusa tarefas legítimas de RE que modelos alinhados recusariam.

**Via principal — `ai hf` (chat/RE):** cole o código ofuscado ou o dump do binário e receba a reconstrução legível. Rápido (~4-5s), sem censura, contexto de 32K.

**Limitações descobertas em produção (HF Inference Endpoints + vLLM):**
- **Multi-GPU não funciona** — deploys com `tensor-parallel` (x2, x4) falham em `make_async_mp_client`. Só **single-GPU (x1, 96 GB)** sobe. Isso limita o modelo ao que cabe em 96 GB e o contexto a ~32K com um 70B.
- **`ai hf codex` não funciona com o 70B** — o prompt de sistema do Codex (skills + tools + MCP) sozinho passa de 32K, estourando o contexto. O comando existe (`wire_api="responses"`, provider efêmero via `-c`, URL nunca gravada em disco), mas exigiria um modelo menor pra sobrar contexto — ao custo de inteligência. Para RE, **prefira o `ai hf` puro**.

**Segurança:** este repositório é público, então a URL do endpoint **não** fica hardcoded no script — ela é infra privada. Configure-a por máquina com `ai hf endpoint <url>` (fica em `providers.conf`, `chmod 600`) ou via `export AI_HF_ENDPOINT_URL=<url>`. Só o nome do modelo (público no Hub) vem como default. Em **outro Mac**: `ai hf endpoint <url>` + `ai hf key`. Ordem de busca do token: env (`HF_TOKEN`) → `providers.conf` → `~/.cache/huggingface/token` (de um `huggingface-cli login` anterior). Ordem da URL: env (`AI_HF_ENDPOINT_URL`) → `providers.conf`.

O endpoint usa **scale-to-zero**: dorme quando ocioso e acorda na primeira chamada (cold start ~1-2 min, tratado automaticamente pelo cliente).

**Respostas diretas:** o modelo é *thinking* e por padrão o cliente manda `enable_thinking: false` — resposta objetiva, sem despejar o raciocínio. Para religar o raciocínio (útil em problemas difíceis): `AI_HF_THINKING=1 ai hf`. Quando ligado, o raciocínio é exibido mas **não** entra no histórico do REPL (cada turno reenvia só a resposta final).

## Featherless (catálogo uncensored via API)

`ai fl` fala com o [Featherless](https://featherless.ai) — 21 mil+ modelos abliterated/uncensored do HuggingFace via API OpenAI-compatible, plano pago mensal, **não loga** nada. Contexto 32K.

```bash
ai fl key                    # salva a API key (1x por máquina)
ai fl "desofusca esse código: <cola>"   # RE one-shot
ai fl                        # chat contínuo
ai fl -m zetasepic/Qwen2.5-72B-Instruct-abliterated   # troca de modelo
ai fl ls coder               # lista modelos coder do plano
```

Modelo default: `huihui-ai/Qwen2.5-Coder-32B-Instruct-abliterated` (o melhor testado pra engenharia reversa — reconhece algoritmos de hash pelo nome, desofusca e reescreve legível, não recusa). Ajuste com `AI_FL_MODEL`. O cliente passa `User-Agent` de browser (o Featherless fica atrás de Cloudflare) e faz retry automático quando o modelo está lotado (`capacity_exhausted`, pois é compartilhado).

**HF vs Featherless:** o HF (`ai hf`) é dedicado e pay-per-hour (mais barato para uso esporádico, contexto até 128K na H200); o Featherless é flat mensal, compartilhado, com muito mais variedade de modelos. Ambos 32K por padrão. Para RE pontual, qualquer um serve; escolha por custo de uso.

## Qwen (Alibaba Model Studio — duas opções)

O Qwen-Max direto pela API da Alibaba (não é o Qoder). Requer uma key do [Model Studio](https://modelstudio.console.alibabacloud.com) — salve com `ai qw key`. Duas formas de usar o mesmo modelo:

```bash
ai qw            # Opção 1: Qwen Code CLI (a CLI própria do Qwen, fork do Gemini CLI)
ai qw claude     # Opção 2: Claude Code usando o Qwen-Max como backend
```

- **Opção 1 (`ai qw`)** — usa o endpoint OpenAI-compatible (`compatible-mode/v1`). Config: `AI_QWEN_BASE_URL` (default Singapura intl), `AI_QWEN_MODEL` (default `qwen3-max-latest`; fixe `qwen3.8-max` pra travar a versão).
- **Opção 2 (`ai qw claude`)** — usa o endpoint **Anthropic-compatible** (`/apps/anthropic`), o mesmo mecanismo do GLM. O Coding Plan tem URL fixa; o pay-as-you-go (Model Studio) inclui seu **WorkspaceId** na URL e serve o Max — configure com `ai qw claude-url <url>`.

A key vai só pro `providers.conf` local (chmod 600, slot `dashscope`), nunca pro repo.

> **Cursor Agent** — instale com `curl https://cursor.com/install -fsS | bash`. O instalador
> cria dois symlinks: `~/.local/bin/agent` (primário) e `~/.local/bin/cursor-agent` (legado),
> **sobrescrevendo** um `agent` pré-existente — o Grok Build usa esse mesmo nome. O launcher
> invoca `cursor-agent` justamente para não depender do nome disputado; se você usa o Grok
> por `agent`, restaure com `ln -sf ~/.grok/bin/agent ~/.local/bin/agent` após instalar.

## Prime Agent (sessão persistente)

`ai prime` (ou `ai pa`) abre o **Prime Agent** — agente de terminal com **sessão
persistente**: o contexto continua rodando em segundo plano e você anexa ou retoma
quando quiser. Não aceita prompt one-shot; login e prompts acontecem **dentro** da TUI.

```bash
ai prime                      # abre a TUI de sessão persistente
ai prime agents               # lista sessões e agentes
ai prime attach <agent>       # anexa numa sessão em andamento
ai prime --resume <path|id>   # retoma uma sessão salva
ai prime status               # estado do serviço/agentes
ai prime doctor --fix         # diagnostica e repara o serviço
ai prime update               # atualiza o Prime Agent
ai prime shutdown             # encerra o serviço
ai prime schedule             # agenda tarefas recorrentes
```

Login e configuração acontecem **dentro** da TUI com `/login` (abre o browser).

Instalação (uma vez por máquina):

```bash
curl -fsSL https://app.primeintellect.ai/prime-agent/install.sh | sh
```

> Subcomandos (`agents`, `attach`, `status`, `doctor`, `update`, `shutdown`,
> `schedule`) e flags informativas (`--resume`, `--version`, `--help`) passam
> **diretos** para o CLI. Sem subcomando, o launcher abre a TUI.

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

## Codex GPT-5.6 Sol (janela de 1M)

O Codex limita o contexto por padrão (ajustado pela OpenAI para custo/desempenho), mas o `gpt-5.6-sol` documenta janela de 1.050.000 tokens. O `ai sol` ativa 1M **só na sessão lançada**, sem tocar no `~/.codex/config.toml`:

```bash
ai sol                   # Codex com gpt-5.6-sol + contexto de 1M
ai sol "tarefa gigante"  # one-shot com prompt
ai sol --conta trabalho  # troca de conta Codex e já lança
```

Equivale a `codex -m gpt-5.6-sol -c model_context_window=1000000 -c model_auto_compact_token_limit=900000` — a compactação automática do histórico começa em 900k, deixando folga antes do teto. Ajustes por env: `AI_CODEX_SOL_MODEL`, `AI_CODEX_SOL_CONTEXT_WINDOW`, `AI_CODEX_SOL_AUTOCOMPACT_LIMIT`.

Para tornar 1M o **padrão permanente** do Codex (aí sim editando config), adicione no topo do `~/.codex/config.toml`, antes de qualquer `[seção]`:

```toml
model = "gpt-5.6-sol"
model_context_window = 1000000
model_auto_compact_token_limit = 900000
```

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
- Providers alternativos (GLM/Z.ai, Muse Spark, Sakana Fugu, OpenRouter, DeepSeek, Ollama, LM Studio, LiteLLM)
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
curl -fsSL https://app.primeintellect.ai/prime-agent/install.sh | sh  # Prime Agent
```

Depois, autentique cada ferramenta usando o fluxo nativo dela (`claude`, `codex` e `gemini`). O launcher não valida nem exige variáveis como `ANTHROPIC_API_KEY`, `OPENAI_API_KEY` ou `GEMINI_API_KEY`.

## Sakana Fugu no Codex

O launcher instala o perfil Fugu do Codex e usa a API compatível com Responses da Sakana.

Modelos suportados:

| Model ID | Reasoning | Descrição |
|---|---|---|
| `fugu` | `high`, `xhigh` | Modelo Fugu padrão. |
| `fugu-ultra-v1.0` | `high`, `xhigh` | Fugu Ultra V1.0, também conhecido como `fugu-ultra-20260615`. |
| `fugu-ultra-v1.1` | `high`, `xhigh`, `max` | Fugu Ultra V1.1. O comando `ai fugu-ultra` resolve para esta versão. |
| `fugu-cyber` | `high`, `xhigh` | Orquestração para segurança (21/07/2026). **Sem variante versionada** e com acesso liberado sob formulário. |

```bash
ai p add sakana                 # salva a SAKANA_API_KEY e instala o perfil
ai fugu                         # abre Codex com model fugu
ai claude-fugu                  # abre Claude Code via Sakana
ai fugu -c model_reasoning_effort=xhigh  # usa o novo nível xhigh
ai fugu-ultra "tarefa pesada"   # alias -> fugu-ultra-v1.1
ai fugu-ultra -c model_reasoning_effort=max "tarefa máxima"
ai fugu-ultra-v1.0 "compat"     # abre Fugu Ultra V1.0
ai fugu-ultra-v1.1 "pesada"     # abre Fugu Ultra V1.1
ai fugu-ultra-20260615 "compat" # alias histórico -> fugu-ultra-v1.0
ai fugu-cyber "audita isso"     # Fugu Cyber (alias: ai sakana-cyber)
ai x --via sakana               # equivalente via Codex
ai x --via fugu-ultra           # alias -> Fugu Ultra V1.1
ai x --via fugu-ultra-v1.0      # Codex via Fugu Ultra V1.0
ai x --via fugu-cyber           # Codex via Fugu Cyber
codex-fugu                      # wrapper direto criado em ~/.local/bin
```

**Fugu Cyber precisa de liberação manual.** Sem o formulário aprovado a API
responde `403 permission_error` na primeira mensagem — já dentro do Codex, onde
sai como erro solto. O launcher avisa antes de abrir e mostra o link do
formulário. Atenção também ao nome: **não existe `fugu-cyber-v1.0`** — esse ID
devolve `404 Model not found`. O Cyber é publicado sem variante versionada,
diferente do Ultra.

Arquivos criados pelo setup:

- `${CODEX_HOME:-~/.codex}/fugu.json`
- `${CODEX_HOME:-~/.codex}/fugu.config.toml`
- `${HOME}/.local/bin/codex-fugu`
- bloco `[model_providers.sakana]` em `${CODEX_HOME:-~/.codex}/config.toml`

## Personalização

Rode `ai --config` ou edite `~/.local/bin/ai` — as flags ficam no topo do arquivo.

## Licença

MIT
