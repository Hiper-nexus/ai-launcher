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
ai g            # Gemini direto
ai k            # Kimi Code direto
ai cu           # Cursor Agent direto
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
| GLM/Z.ai | `ai glm` | Claude Code via provider `glm` |
| Muse Spark (Meta AI) | `ai ms` | CLI própria (REPL/one-shot) via `api.meta.ai`; `ai ms claude` abre no Claude Code (yolo); `ai ms model` escolhe o modelo para os dois caminhos |
| Codex | `ai x` | `--dangerously-bypass-approvals-and-sandbox` |
| Sakana Fugu | `ai fugu`, `ai fugu-ultra[-v1.x]` | Codex profile `fugu` |
| Gemini | `ai g` | `--yolo` |
| Kimi Code | `ai k` | `--yolo` |
| Grok (xAI) | `ai gr` | `--always-approve --permission-mode bypassPermissions` |
| Qoder | `ai q` | `--dangerously-skip-permissions` |
| Cursor Agent | `ai cu` | `--yolo --sandbox disabled --approve-mcps --trust` |
| Antigravity | `ai a` | _(nenhuma)_ |
| Ollama Cloud | `ai ol` | roda em `ollama.com`, modelo `minimax-m3` |
| HF Endpoint (dedicado) | `ai hf` | seu modelo uncensored, servido por vLLM na Hugging Face |
| Featherless | `ai fl` | catálogo uncensored via API (21 mil+ modelos, plano pago) |
| Qwen (Alibaba) | `ai qw` | Qwen-Max via Model Studio — CLI própria **ou** dentro do Claude Code |

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

```bash
ai p add sakana                 # salva a SAKANA_API_KEY e instala o perfil
ai fugu                         # abre Codex com model fugu
ai fugu-ultra "tarefa pesada"   # alias -> fugu-ultra-v1.1
ai fugu-ultra-v1.0 "compat"     # abre Fugu Ultra V1.0
ai fugu-ultra-v1.1 "pesada"     # abre Fugu Ultra V1.1
ai fugu-ultra-20260615 "compat" # alias histórico -> fugu-ultra-v1.0
ai x --via sakana               # equivalente via Codex
ai x --via fugu-ultra           # alias -> Fugu Ultra V1.1
ai x --via fugu-ultra-v1.0      # Codex via Fugu Ultra V1.0
codex-fugu                      # wrapper direto criado em ~/.local/bin
```

Arquivos criados pelo setup:

- `${CODEX_HOME:-~/.codex}/fugu.json`
- `${CODEX_HOME:-~/.codex}/fugu.config.toml`
- `${HOME}/.local/bin/codex-fugu`
- bloco `[model_providers.sakana]` em `${CODEX_HOME:-~/.codex}/config.toml`

## Personalização

Rode `ai --config` ou edite `~/.local/bin/ai` — as flags ficam no topo do arquivo.

## Licença

MIT
