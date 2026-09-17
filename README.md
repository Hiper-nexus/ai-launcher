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

### Windows

O launcher roda sobre o **Git Bash** (Git for Windows), que já traz Bash 5.x. No Git Bash, a instalação manual acima funciona igual. Depois crie o atalho para chamar `ai` do PowerShell e do CMD:

```bat
@echo off
"C:\Program Files\Git\bin\bash.exe" "%USERPROFILE%\.local\bin\ai" %*
```

Salve como `%USERPROFILE%\.local\bin\ai.cmd` e garanta que essa pasta está no `PATH` do usuário.

> **Não clone o repositório com `core.autocrlf=true`** (o padrão do Git for Windows) sem o `.gitattributes` deste repo. Com CRLF o Bash não reconhece o terminador de heredoc, e o `ai` usa dezenas deles.

O que muda no Windows está descrito em [Windows: o que é diferente](#windows-o-que-é-diferente).

## Uso

```bash
ai              # Menu interativo com status de cada CLI
ai c            # Claude Code direto
ai glm          # GLM 5.3 (Z.ai) via Claude Code — /model oferece o 5.3 Flash
ai gf           # sessão inteira no GLM 5.3 Flash (aliases: glm-flash, zf, flash)
ai ds           # DeepSeek V4.1 Flash (GA, model ID: deepseek-flash) via Claude Code
ai ds-pro       # DeepSeek V4-Pro (GA) via Claude Code
ai ds-v41       # DeepSeek V4.1 Flash — alias do ai ds
ai x            # Codex direto
ai sol          # Codex GPT-5.6 Sol com janela de 1M de contexto (aliases: x-1m, x1m)
ai fugu         # Codex via Sakana Fugu Ultra V2.0
ai claude-fugu  # Claude Code via endpoint Anthropic-compatible da Sakana
ai fugu -c model_reasoning_effort=xhigh  # Ultra V2.0 com raciocínio profundo
ai fugu-ultra   # Fugu Ultra V2.0
ai fugu-max     # Fugu Max V1.0
ai fugu-ultra -c model_reasoning_effort=max  # máximo disponível no Ultra V2.0
ai fugu-ultra-v2.0  # Fugu Ultra V2.0 explícito
ai fugu-ultra-v1.0  # Fugu Ultra V1.0
ai fugu-ultra-v1.1  # Fugu Ultra V1.1
ai g            # Gemini direto
ai k            # Kimi Code direto
ai cu           # Cursor Agent direto
ai dv           # Devin CLI (Cognition) — modo dangerous (auto-aprova tudo)
ai dv "prompt"  # Devin one-shot (modo print)
ai omp          # omp (oh-my-pi) direto — 60+ providers num só agente
ai omp models   # Providers/modelos que o omp enxerga hoje
ai ol           # Ollama Cloud (roda em ollama.com, não na sua máquina)
ai ab           # GLM-5.3 sem censura (Abliteration.ai) — chat ou one-shot
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
| Sakana Fugu | `ai fugu`, `ai fugu-ultra`, `ai fugu-max`, `ai fugu-ultra-v1.x`, `ai claude-fugu` | Ultra V2.0 por padrão no perfil Codex `fugu` ou no endpoint Anthropic-compatible |
| Gemini | `ai g` | `--yolo` |
| Kimi Code | `ai k` | `--auto` (never-ask; o `--yolo` do kimi ainda pede yes em ação arriscada/plano) |
| Grok (xAI) | `ai gr` | `--always-approve --permission-mode bypassPermissions` |
| Qoder | `ai q` | `--dangerously-skip-permissions` |
| Cursor Agent | `ai cu` | `--yolo --sandbox disabled --approve-mcps --trust` |
| omp (oh-my-pi) | `ai omp`, `ai o` | `--yolo` — agente único com 60+ providers; `-m` troca de modelo |
| Antigravity | `ai a` | _(nenhuma)_ |
| Ollama Cloud | `ai ol` | roda em `ollama.com`, modelo `minimax-m3` |
| HF Endpoint (dedicado) | `ai hf` | seu modelo uncensored, servido por vLLM na Hugging Face |
| Featherless | `ai fl` | catálogo uncensored via API (21 mil+ modelos, plano pago) |
| Abliteration.ai | `ai ab` | GLM-5.3 hospedado, abliterated (sem censura) — chat, one-shot ou Claude Code (`ai ab claude`) |
| Qwen (Alibaba) | `ai qw` | Qwen-Max via Model Studio — CLI própria (`--yolo`) **ou** dentro do Claude Code |
| Prime Agent | `ai prime`, `ai pa` | sessão persistente (sem one-shot); subcomandos e `--resume` passam direto |
| Devin CLI | `ai dv`, `ai devin` | `--permission-mode dangerous --respect-workspace-trust false` |

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

## Abliteration.ai (GLM-5.3 hospedado, sem censura)

`ai ab` fala com o [Abliteration.ai](https://abliteration.ai) — o **GLM-5.3 com a direção de recusa removida nos pesos** (abliteration), servido atrás de uma API OpenAI-compatible. Diferente do HF/Featherless (modelos menores, 32K), aqui é um modelo frontier hospedado: billing por token, sem retenção de prompts.

```bash
ai ab key                    # salva a key ak_... (https://abliteration.ai, 1x por máquina)
ai ab                        # chat interativo no GLM-5.3 uncensored
ai ab "audita esse dump"     # one-shot
ai ab -m abliterated-model   # variante multimodal (aceita imagem/vídeo)
ai ab claude                 # Claude Code INTEIRO em cima do GLM-5.3 sem censura
```

**Modo Claude (`ai ab claude`)** — mesmo esquema do `ai glm`: o Claude Code vira só o harness e todo o raciocínio roda no GLM-5.3 abliterated, via endpoint Anthropic-compatible da abliteration.ai (`ANTHROPIC_BASE_URL`/`ANTHROPIC_AUTH_TOKEN` exportados só na sessão, nada gravado em `~/.claude`). O slot haiku (tarefas de fundo) usa o `abliterated-model`, mais barato — ajuste com `AI_AB_HAIKU_MODEL`. A compactação automática segue a recomendação oficial de 240K para o contexto de 256K (`AI_AB_AUTOCOMPACT_WINDOW`). Setup manual/documentação: [docs.abliteration.ai/integrations/claude-code](https://docs.abliteration.ai/integrations/claude-code).

Modelos: `abliterated-model-large-v2` (GLM-5.3, default), `abliterated-model-large` (GLM-5.2) e `abliterated-model` (multimodal). Thinking desligado por padrão; `AI_AB_THINKING=1` religa (no large-v2 o raciocínio não desliga, roda em low). Ajustes: `AI_AB_MODEL`, `AI_AB_HOST`. A key fica no `providers.conf` (chmod 600, slot `abliteration`); `ABLITERATION_API_KEY` no ambiente tem prioridade.

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

## Devin CLI (Cognition)

`ai dv` (ou `ai devin`) abre o **Devin CLI** — agente da Cognition que roda tanto
no terminal quanto na nuvem. Sem prompt ele abre a TUI; com prompt ele roda em
modo print (one-shot).

```bash
ai dv                          # TUI do Devin, modo dangerous
ai dv "corrige esse teste"     # one-shot (modo print)
ai dv models                   # modelos disponíveis na sua conta
ai dv doctor                   # diagnostica a config local
ai dv auth login               # autentica (ou faça login dentro da TUI)
ai dv update                   # atualiza o binário
ai dv cloud list               # recursos do Devin Cloud
```

Instalação (uma vez por máquina):

```bash
curl -fsSL https://cli.devin.ai/install.sh | bash
```

O binário vai para `~/.local/bin/devin` (versões ficam em
`~/.local/share/devin/cli/_versions/`, com um symlink `current`). O
auto-update nativo é `ai dv update`.

**Flags padrão:** `--permission-mode dangerous --respect-workspace-trust false`

- `--permission-mode dangerous` é o yolo do Devin: o default é `auto`, que só
  auto-aprova ferramentas de leitura — sem isso ele pediria aprovação a cada
  escrita. Os degraus são `auto` → `accept-edits` → `smart` → `dangerous`.
- `--respect-workspace-trust false` existe porque o modo print (`-p`) **não
  consegue** exibir o prompt de confiança do diretório e falha num repo ainda
  não confiado. Como o launcher já é yolo por padrão e entra no seu próprio
  repo, a checagem é pulada. Remova essa flag de `DEVIN_FLAGS` em `ai` se
  quiser o prompt de trust do Devin.

> Subcomandos (`auth`, `mcp`, `models`, `doctor`, `rules`, `skills`, `plugins`,
> `cloud`, `desktop`, `list`, `ls`, `rm`, `ssh`, `forward`, `update`, `version`,
> `migrate`, `sandbox`, `setup`, `uninstall`, `acp`, `help`) e flags informativas
> (`--version`, `--help`) passam **diretos** para o CLI, sem as flags de yolo.

> `--via <provider>` é recusado: o Devin tem login e catálogo de modelos
> próprios (`ai dv auth login`, `ai dv models`).

### Flags antes do prompt

Estas flags são reconhecidas **antes** do prompt e viram flags de verdade —
não texto do prompt:

```bash
ai dv -c "continua de onde paramos"    # retoma a última sessão (-r <id> também)
ai dv --model opus "tarefa pesada"     # troca o modelo
ai dv --permission-mode accept-edits "revisa isso"
ai dv --sandbox "roda os testes"
```

`--model` e `--permission-mode` **substituem** o default do launcher em vez de
somar: o clap do Devin recusa a flag repetida (`cannot be used multiple times`),
então `ai dv --permission-mode auto` roda em `auto` de verdade — o `dangerous`
sai do caminho.

Qualquer flag com `-` que o launcher não conheça **aborta** em vez de virar
prompt, para você não pedir o modo mais seguro e receber o mais perigoso sem
aviso. Se o seu prompt é que começa com `-`, separe com `--`:

```bash
ai dv -- "-c é um parâmetro do meu script?"
```

Tudo que sobra vira o prompt e é enviado como `-p -- "<texto>"`. O `--` é
necessário porque o `-p` do Devin tem valor **opcional** e o clap não consome
como valor um token que começa com hífen — sem ele, um prompt com `-` morre em
`error: unexpected argument`.

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

## Contas Claude (multi-conta sem logout)

Troque entre várias contas Claude (pessoal, trabalho, backup) sem o ciclo logout → browser → login.

Onde as credenciais OAuth ficam guardadas depende da plataforma:

| | Cofre | Slot ativo |
|---|---|---|
| **macOS** | Keychain (nunca em texto plano) | item `Claude Code-credentials` no Keychain |
| **Windows** | arquivo em `~/.local/share/ai-launcher/accounts/`, ACL restrita ao dono | `~/.claude/.credentials.json` |

No Windows não existe cofre equivalente utilizável por linha de comando — o `cmdkey` guarda credencial mas não devolve o segredo em claro. A proteção é a ACL, que é a mesma que o próprio Claude Code usa lá: ele grava `~/.claude/.credentials.json` em texto puro (e, de fábrica, legível por outras contas da máquina).

```bash
ai conta add pessoal     # cadastra conta NOVA: login guiado, com rollback automático
ai conta save trabalho   # salva a conta logada atual como "trabalho"
ai conta ls              # lista contas — ● marca a ativa
ai conta status          # uso de cada conta (janela 5h / 7 dias) + horário de reset
ai conta use pessoal     # ativa a conta "pessoal" na hora
ai conta rm backup       # remove um backup salvo
ai c --conta trabalho    # troca de conta e já lança o Claude
ai conta                 # menu interativo (também é a opção 32 do menu principal)
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

## Roteamento por linguagem natural (Jev / TypeSafe)

Escolhe a CLI a partir de uma frase, em vez de você lembrar do alias.

```bash
ai ask "refatorar um repo grande sem gastar muito"   # → deepseek, e já lança
ai ask --force "..."        # ignora o threshold de confiança
ai "revisar PR grande"      # frase solta também roteia (só com key configurada)
ai jev key                  # salva a API key do TypeSafe
ai jev status               # key, modelo e confiança mínima
```

Como funciona: o pedido é um `choice` — "qual destas 24 CLIs serve para esta
frase?" — enviado ao [Jev](https://docs.typesafe.ai), o modelo System One da
TypeSafe. Ele não gera texto: devolve a opção escolhida, a distribuição de
probabilidade e um `confidence`.

Três propriedades que valem saber:

- **O pior caso é o comportamento antigo.** Se o Jev não responder, devolver
  `nenhum`, ou vier com confiança abaixo de `AI_JEV_MIN_CONFIDENCE` (default
  `0.55`), o launcher não lança nada e você segue no fluxo de sempre. O
  fallback implícito só existe se houver key configurada — sem key, `ai ocde`
  continua sendo "opção desconhecida".
- **Argumento que começa com `-` nunca vira chamada de rede**, para typo de
  flag não gastar requisição.
- **É barato**: input a $0,042/1M e output grátis. Uma rota manda ~600 tokens
  de estado, ou seja ~$0,000025 por chamada.

Configuração:

| Variável | Default | Para quê |
|---|---|---|
| `TYPESAFE_API_KEY` | — | key (ou use `ai jev key`, que grava em `providers.conf`) |
| `AI_JEV_MIN_CONFIDENCE` | `0.55` | abaixo disso não lança |
| `AI_JEV_MODEL` | `jev-latest` | fixe uma versão se calibrou threshold nela |
| `AI_JEV_HOST` | `https://api.typesafe.ai` | endpoint |

O threshold default é um chute conservador. O certo é calibrar com uso real —
a documentação da TypeSafe é explícita que confidence resume a distribuição da
resposta, não autoriza agir. Use `ai ask --force` para ver a decisão crua e
ajustar `AI_JEV_MIN_CONFIDENCE`.

### Jev como servidor MCP (para usar fora do `ai`)

O `ai ask` vive no launcher — se você abrir o Cursor ou o Gemini direto, ele não
existe lá. O `mcp/jev-server.py` resolve isso: expõe o mesmo roteamento como uma
tool MCP, e aí **qualquer CLI que fale MCP** ganha a capacidade.

```bash
python3 /caminho/para/ai-launcher/mcp/jev-server.py    # o cliente MCP sobe isso
```

Sem dependências (só a stdlib — o repo já exige python3) e com **uma única
tool**, de propósito: cada tool de MCP é carregada no contexto a cada turno.
Uma tool custa ~300 tokens por sessão; oito custariam ~4 mil.

> ⚠️ **Isto adiciona ~300 tokens de contexto por sessão em CADA CLI onde for
> configurado.** Configure só onde você de fato usa a CLI fora do `ai`.

O servidor **lê o criteria de destinos do próprio script `ai`** em runtime
(`AI_LAUNCHER_PATH`, default `~/.local/bin/ai`). Não existe segunda lista para
sair de sincronia: mexeu no `ai`, o MCP acompanha. Se o launcher sumir ou for
antigo demais, ele falha com mensagem explícita em vez de rotear com lista vazia.

### A key NÃO vai no config da CLI

O servidor resolve a key em duas etapas: `TYPESAFE_API_KEY` no ambiente (útil
para testar) e, se não houver, o slot `typesafe` do `providers.conf` do launcher
(`chmod 600`). Grave a sua uma única vez:

```bash
ai jev key
```

Isso importa porque configurar o Jev em cinco CLIs com a key inline criaria
**cinco cópias em texto plano** do mesmo segredo. Já existe um lugar para ela,
com permissão restrita — o mesmo problema que o launcher resolveu para os
outros providers. Sem key nenhuma no config, funciona inclusive quando a CLI é
aberta por uma GUI que não herda o ambiente do shell (Cursor, por exemplo).

Config por CLI — **nada de `env` com a key**:

**Claude Code**

```bash
claude mcp add jev -s user -- python3 /caminho/para/ai-launcher/mcp/jev-server.py
```

**Cursor** — em `~/.cursor/mcp.json`; **Gemini CLI** — em `~/.gemini/settings.json`;
**Qoder** — em `~/.qoder/settings.json`. Os três usam a mesma forma:

```json
{ "mcpServers": { "jev": {
    "command": "python3",
    "args": ["/caminho/para/ai-launcher/mcp/jev-server.py"] } } }
```

**opencode** — em `~/.config/opencode/opencode.json`, com `command` como array:

```json
{ "mcp": { "jev": {
    "type": "local",
    "command": ["python3", "/caminho/para/ai-launcher/mcp/jev-server.py"],
    "enabled": true } } }
```

**Codex** — em `~/.codex/config.toml`:

```toml
[mcp_servers.jev]
command = "python3"
args = ["/caminho/para/ai-launcher/mcp/jev-server.py"]
```

> **No Windows, troque `python3` por `python`.** O nome `python3` ali é o App
> Execution Alias da Microsoft Store: ele existe no PATH mesmo sem Python
> instalado e só falha ao ser executado, então o cliente MCP mostraria o
> servidor como configurado e ele nunca subiria. Use o caminho completo do
> interpretador se tiver mais de um Python. O caminho do script também pode
> ser escrito em formato Windows (`C:\Users\voce\ai-launcher\mcp\jev-server.py`).

## Agente de browser com Jev (`ai jb`)

O `ai ask` usa o Jev para **escolher** uma CLI. Este usa o Jev para **decidir
cada passo dentro de um navegador**: qual elemento clicar, qual operação, qual
valor, e done/blocked/erro/irreversível — tudo numa requisição só. Quem clica é
o Playwright; o Jev decide o que clicar.

```bash
ai jb              # sobe o Chrome isolado e abre o inspetor em http://127.0.0.1:8766
```

É a integração do [browser-use/jev-ultrafast](https://github.com/browser-use/jev-ultrafast)
(MIT, projeto de terceiros). **O launcher não instala nada** — ele só orquestra
o que já está no disco e, se não estiver, imprime as instruções de instalação.

### Por que um Chrome separado

O `ai jb` sobe um Chrome **com perfil descartável** em vez de usar o seu
navegador do dia a dia. Isso é deliberado: habilitar depuração remota no seu
Chrome normal expõe todas as sessões logadas — email, GitHub, banco — a
qualquer processo que alcance aquela porta. Um perfil novo não tem login
nenhum, então o agente não tem o que vazar.

#### A cadeia de confiança do CDP (e três erros que ela corrige)

A primeira versão **autenticava o browser pela resposta dele**: perguntava na
porta "você é o Chrome?" e acreditava na string. Qualquer processo local
escreve `Browser: Chrome` — passava. O conserto não é validar melhor a
resposta, é **não perguntar para quem não se conhece**. A confiança vem de
fatos que o atacante não fabrica:

1. **Nós lançamos o processo, com `--remote-debugging-port=0`** (o Chrome
   sorteia a porta), e ele diz na **própria stderr** qual URL está servindo.
   Não há como injetar no stderr de um filho que você mesmo criou.
2. **Quem escuta aquela porta tem que ser um processo com o NOSSO
   `--user-data-dir` no argv, do usuário atual.** Identidade verificada no
   processo, não em texto que ele devolve.
3. **O perfil fica sob `$HOME`, não em `/tmp`.** `/tmp` é compartilhado e
   previsível: outro usuário local podia plantar um symlink e o Chrome
   escreveria o perfil inteiro no alvo do link. É recusado se for symlink ou
   se não pertencer a você. (Essa era exatamente a classe de bug que o cache
   de versões deste launcher já tinha tido.)

Sem o item 2, um processo que chegasse primeiro devolvia a URL dele e o agente
passava a dirigir um browser de terceiro — lendo conteúdo de página forjado.

| Variável | Default | Para quê |
|---|---|---|
| `AI_JEV_BROWSER_DIR` | `~/dev/jev-ultrafast` | onde o projeto está clonado |
| `AI_JEV_BROWSER_PROFILE` | `~/.cache/jev-chrome-profile` | perfil descartável |
| `AI_JEV_CHROME` | detectado por plataforma | binário do Chrome, quando não está onde o instalador oficial deixa |

#### No Windows

A cadeia de confiança é a mesma — o que muda são as fontes, porque as do
Unix não existem lá:

| Passo | Unix | Windows |
|---|---|---|
| achar o Chrome | `/Applications/Google Chrome.app` | `%LOCALAPPDATA%` e `Program Files` (`Google\Chrome\Application\chrome.exe`) |
| quem escuta a porta | `lsof` | `netstat -ano` |
| argv e dono do processo | `ps -p` | `Get-CimInstance Win32_Process` |

O `ps` do Git Bash **não** serve aqui: ele enxerga só os processos MSYS,
enquanto o PID que o `netstat` devolve é do Windows — numeração diferente.
`kill -0` tem o mesmo problema. Por isso vida, argv e dono saem todos do CIM.

O perfil vai para o Chrome em caminho do Windows (`C:\...`), e é essa string
que reaparece no argv; a comparação normaliza caixa e barras dos dois lados,
então ela é sobre o **diretório**, não sobre a grafia. O perfil também recebe
ACL restrita ao dono, e não só `chmod 700` — que no NTFS não faz nada.

Instale o `uv` com `winget install --id=astral-sh.uv` (o `brew install uv` da
mensagem antiga não existe no Windows).

### Limitações (do próprio projeto, é MVP)

Shadow roots, iframes, canvas, uploads, abas em pop-up e scroll aninhado ficam
de fora. Escolher `DONE` **não verifica** o resultado — precisa de conferência
independente. E numa página lenta (Wikipedia, por exemplo) a recuperação de
`StalePage` pode estourar em vez de retentar.

## Features

- Menu interativo com versão e status de instalação
- Não exige `*_API_KEY`; o launcher delega autenticação para cada CLI
- Histórico de uso
- Passagem de prompt direto via linha de comando
- Flags configuráveis no topo do script
- Contas Claude múltiplas com troca sem logout (Keychain, macOS)
- Providers alternativos (GLM/Z.ai, Muse Spark, Sakana Fugu, OpenRouter, DeepSeek, Ollama, LM Studio, LiteLLM)
- Roteamento por linguagem natural via Jev/TypeSafe (`ai ask`)
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
curl -fsSL https://cli.devin.ai/install.sh | bash                     # Devin CLI
```

No Windows os comandos são outros — nenhum `brew`, e os instaladores `curl | bash` resolvem binário de Linux. Rode no **PowerShell**:

```powershell
irm https://antigravity.google/cli/install.ps1 | iex            # Antigravity
irm https://static.devin.ai/cli/setup.ps1 | iex                 # Devin CLI
irm 'https://cursor.com/install?win32=true' | iex               # Cursor Agent
irm https://dev.meta.ai/install.ps1 | iex                       # Muse Code (nativo)
winget install Ollama.Ollama                                    # Ollama
```

E no npm (igual nas três plataformas):

```bash
npm install -g @moonshot-ai/kimi-code        # Kimi Code
npm install -g @xai-official/grok            # Grok
npm install -g @qoder-ai/qodercli            # Qoder
npm install -g @vegamo/deepcode-cli          # Deep Code
npm install -g @oh-my-pi/pi-coding-agent     # omp (oh-my-pi)
npm install -g opencode-ai                   # opencode
```

Não precisa decorar: quando uma CLI falta, o launcher imprime o comando certo **para a plataforma em que você está** (`cli_install_hint`).

Duas CLIs não têm build nativo Windows:

- **Prime Agent** — o release não publica binário Windows, mas o `.tgz` do mesmo release é Node puro: `npm install -g <tarball do release>` (veja [releases](https://github.com/PrimeIntellect-ai/prime-agent/releases)).

Muse Code tinha essa limitação até 09/2026 e agora é nativo (x64 e ARM64, sem admin) — está no bloco PowerShell acima.

Depois, autentique cada ferramenta usando o fluxo nativo dela (`claude`, `codex` e `gemini`). O launcher não valida nem exige variáveis como `ANTHROPIC_API_KEY`, `OPENAI_API_KEY` ou `GEMINI_API_KEY`.

## Sakana Fugu no Codex

O launcher instala o perfil Fugu do Codex e usa a API compatível com Responses da Sakana.

Modelos suportados:

| Model ID | Reasoning | Descrição |
|---|---|---|
| `fugu-ultra-v2.0` | `high`, `xhigh`, `max` | Modelo padrão do launcher. `ai fugu` e `ai fugu-ultra` usam esta versão. |
| `fugu-max-v1.0` | `high`, `xhigh`, `max` | Opção de melhor custo-benefício, disponível como `ai fugu-max`. |
| `fugu-ultra-v1.0` | `high`, `xhigh` | Fugu Ultra V1.0, também conhecido como `fugu-ultra-20260615`. |
| `fugu-ultra-v1.1` | `high`, `xhigh`, `max` | Fugu Ultra V1.1 mantido para compatibilidade. |

```bash
ai p add sakana                 # salva a SAKANA_API_KEY e instala o perfil
ai fugu                         # abre Codex com Fugu Ultra V2.0
ai claude-fugu                  # abre Claude Code via Sakana
ai fugu -c model_reasoning_effort=xhigh  # usa raciocínio profundo no Ultra V2.0
ai fugu-ultra "tarefa pesada"   # alias -> fugu-ultra-v2.0
ai fugu-ultra -c model_reasoning_effort=max "tarefa máxima"
ai fugu-max "tarefa econômica"  # abre Fugu Max V1.0
ai fugu-ultra-v2.0 "pesada"     # abre Fugu Ultra V2.0 explicitamente
ai fugu-ultra-v1.0 "compat"     # abre Fugu Ultra V1.0
ai fugu-ultra-v1.1 "pesada"     # abre Fugu Ultra V1.1
ai fugu-ultra-20260615 "compat" # alias histórico -> fugu-ultra-v1.0
ai x --via sakana               # equivalente via Codex
ai x --via fugu-ultra           # alias -> Fugu Ultra V2.0
ai x --via fugu-max             # Codex via Fugu Max V1.0
ai x --via fugu-ultra-v1.0      # Codex via Fugu Ultra V1.0
codex-fugu                      # wrapper direto criado em ~/.local/bin
```

Arquivos criados pelo setup:

- `${CODEX_HOME:-~/.codex}/fugu.json`
- `${CODEX_HOME:-~/.codex}/fugu.config.toml`
- `${HOME}/.local/bin/codex-fugu`
- bloco `[model_providers.sakana]` em `${CODEX_HOME:-~/.codex}/config.toml`

## Windows: o que é diferente

O launcher nasceu para macOS/Linux. No Git Bash, quatro suposições POSIX falham
— e falhavam **em silêncio**, que é o pior modo: o comando retorna 0 e o efeito
não acontece. A camada de plataforma (`ai_os`, `secure_file`, `ai_python`,
`win_bin_path`, `secret_*`) existe para isso.

**Permissão de arquivo.** `chmod 600` no NTFS é decorativo: o Git Bash aceita,
devolve 0, e o `stat` continua 644 com a ACL herdada valendo. Numa máquina real
isso deixava o `providers.conf` — o arquivo com todas as API keys — acessível a
grupos que herdavam a pasta. `secure_file()` fecha a ACL com
`icacls /inheritance:r` além do `chmod`.

**Python.** `command -v python3` é verdadeiro mesmo sem Python instalado: o App
Execution Alias da Microsoft Store fica no `PATH` e só falha ao executar (exit
49). Os guards por presença aprovavam e o erro estourava depois, dentro do
heredoc. `ai_python()` testa execução e aceita `python`/`py`, que é como o
Python real costuma se chamar no Windows.

**Detecção de CLI.** `command -v` só resolve executável POSIX e `.exe`. CLI cujo
instalador cria apenas wrapper `.cmd`/`.ps1` — `cursor-agent` é o caso — ficava
marcada como ausente no menu mesmo instalada e funcionando. As instaladas por
npm escapavam por acidente, porque o npm cria os três nomes.

A coluna de versão não acompanha: ler a versão de um `.cmd` exigiria
`cmd.exe`/`powershell.exe`, e programa de console do Windows escreve direto no
handle do console, fora do alcance da redireção que o preload paralelo usa —
isso embaralha o menu inteiro. A CLI aparece instalada, só sem número de versão.
É uma troca deliberada; não "conserte" chamando `cmd.exe` ali.

**Encoding do Python.** No Windows o Python escreve no encoding da locale
(`cp1252` em máquina pt-BR), então qualquer `print` com acento ou seta —
`réplicas:`, `confiança →` — morria com `UnicodeEncodeError` no meio do
comando. O wrapper `python3()` trava `PYTHONIOENCODING=utf-8`, o que cobre os
~40 pontos onde o launcher chama Python de uma vez. O servidor MCP faz o
equivalente no próprio arquivo (`reconfigure`), porque lá o problema é na
**leitura**: um pedido com acento chegava como `UnicodeDecodeError`.

**Processos e portas.** Não há `lsof`, e o `ps` do Git Bash enxerga só os
processos MSYS — enquanto os PIDs do sistema são do Windows. Quem precisa
disso é a cadeia de confiança do [`ai jb`](#no-windows): `ai_pid_na_porta()`
usa `netstat -ano` e `ai_win_proc_info()` tira argv e dono do CIM.

**Cofre de credenciais.** Ver [Contas Claude](#contas-claude-multi-conta-sem-logout).

### Rodando os testes

```bash
bash tests/run-all.sh                     # a suíte inteira
bash tests/platform-windows.test.sh       # só a camada de plataforma
bash tests/secret-store.test.sh
```

Dois arquivos se **pulam** conforme o ambiente, e dizem por quê ao pular:
`platform-windows` fora do Windows, e `version-cache` onde não há como alocar
um pty (o menu exige TTY; o Windows não tem `script(1)`, e o `winpty` do Git
Bash não cria pty sem um console anexado — em CI, por exemplo).

`tests/helpers/platform.sh` extrai a camada do próprio `ai` em vez de duplicá-la
— o launcher é distribuído como arquivo único e não pode sourcear um `lib/`. Use
`assert_secret_file` em vez de comparar `stat`: no NTFS o modo POSIX não diz nada
sobre quem consegue ler o arquivo.

## Personalização

Rode `ai --config` ou edite `~/.local/bin/ai` — as flags ficam no topo do arquivo.

## Licença

MIT
