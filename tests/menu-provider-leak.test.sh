#!/usr/bin/env bash

# Rota de provider pinada em config GLOBAL sequestrando o menu.
#
# Dois arquivos fora do launcher podem prender toda sessão num provider:
#   ~/.claude/settings.json  → bloco "env" (o Claude Code aplica por conta
#                              própria, vence o ambiente do processo pai)
#   ~/.codex/config.toml     → `model`/`model_provider` no topo do arquivo
#
# Com eles pinados no Macaron, o "Claude Code" do menu abria Macaron e o
# "Codex" abria Macaron — em silêncio. Estes testes travam o conserto.

set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

TEST_HOME="${TMP_DIR}/home"
CODEX_HOME="${TMP_DIR}/codex"
FAKE_BIN="${TMP_DIR}/bin"
CAPTURE="${TMP_DIR}/capture"
mkdir -p "${TEST_HOME}/.claude" "$CODEX_HOME" "$FAKE_BIN"

for cli in claude codex; do
    cat > "${FAKE_BIN}/${cli}" <<SH
#!/usr/bin/env bash
{
  echo "CMD=${cli}"
  echo "ARGS=\$*"
  echo "BASE=\${ANTHROPIC_BASE_URL:-}"
  echo "MODEL=\${ANTHROPIC_MODEL:-}"
  echo "SUBAGENT=\${CLAUDE_CODE_SUBAGENT_MODEL:-}"
} > "$CAPTURE"
SH
    chmod +x "${FAKE_BIN}/${cli}"
done

fail() { echo "FAIL: $*" >&2; exit 1; }

seed_polluted_state() {
    cat > "${TEST_HOME}/.claude/settings.json" <<'JSON'
{
  "env": {
    "ANTHROPIC_BASE_URL": "https://mint.macaron.im",
    "ANTHROPIC_AUTH_TOKEN": "sk-token-secreto",
    "ANTHROPIC_MODEL": "macaron-v1-coding-venti",
    "CLAUDE_CODE_SUBAGENT_MODEL": "macaron-v1-coding-venti",
    "IS_SANDBOX": "1"
  },
  "model": "opus[1m]",
  "permissions": { "deny": ["Bash(rm -rf /)"] }
}
JSON
    cat > "${CODEX_HOME}/config.toml" <<'TOML'
model = "macaron-v1-coding-venti"
model_provider = "macaron"
model_reasoning_effort = "high"

[mcp_servers.demo]
command = "echo"
TOML
}

run_launcher() {
    : > "$CAPTURE"
    (
        cd "$ROOT"
        HOME="$TEST_HOME" \
        CODEX_HOME="$CODEX_HOME" \
        PATH="${FAKE_BIN}:$PATH" \
        SAKANA_API_KEY="test-sakana-key" \
        MACARON_API_KEY="test-macaron-key" \
        bash ./ai "$@" >/dev/null 2>&1
    )
}

# ── 1. Claude nativo não pode herdar a rota do settings.json ──────────
seed_polluted_state
run_launcher c
captured=$(cat "$CAPTURE")
[[ "$captured" == *"CMD=claude"* ]] || fail "ai c não chamou o claude: ${captured}"
[[ "$captured" != *"mint.macaron.im"* ]] || fail "ai c saiu pelo Macaron: ${captured}"
[[ "$captured" != *"macaron-v1-coding-venti"* ]] || fail "ai c herdou modelo Macaron: ${captured}"

# ── 2. o resto do settings.json sobrevive ao conserto ─────────────────
settings=$(cat "${TEST_HOME}/.claude/settings.json")
[[ "$settings" != *"mint.macaron.im"* ]] || fail "rota de provider continuou no settings.json"
[[ "$settings" != *"sk-token-secreto"* ]] || fail "token continuou no settings.json"
[[ "$settings" == *'"IS_SANDBOX"'* ]]    || fail "env não-provider foi perdido"
[[ "$settings" == *"rm -rf /"* ]]        || fail "permissions foram perdidas"
[[ "$settings" == *"opus[1m]"* ]]        || fail "model do usuário foi perdido"
[[ -f "${TEST_HOME}/.claude/settings.json.ai-launcher.bak" ]] || fail "backup não foi criado"
perms=$(stat -f '%Lp' "${TEST_HOME}/.claude/settings.json.ai-launcher.bak" 2>/dev/null \
        || stat -c '%a' "${TEST_HOME}/.claude/settings.json.ai-launcher.bak" 2>/dev/null)
[[ "$perms" == "600" ]] || fail "backup com token nasceu ${perms}, esperado 600"

# idempotente: rodar de novo não quebra nem reescreve o backup
run_launcher c
[[ "$(cat "$CAPTURE")" == *"CMD=claude"* ]] || fail "segunda execução do ai c falhou"

# ── 3. Codex oficial não pode sair pelo provider pinado no config.toml ─
seed_polluted_state
run_launcher x
captured=$(cat "$CAPTURE")
[[ "$captured" == *"CMD=codex"* ]] || fail "ai x não chamou o codex: ${captured}"
[[ "$captured" == *"model_provider=openai"* ]] || fail "ai x não fixou o provider oficial: ${captured}"
[[ "$captured" != *"-p fugu"* ]] || fail "ai x entrou no perfil do Fugu: ${captured}"

config=$(cat "${CODEX_HOME}/config.toml")
[[ "$config" != *'model_provider = "macaron"'* ]]        || fail "default macaron ficou no config.toml"
[[ "$config" != *'model = "macaron-v1-coding-venti"'* ]] || fail "model macaron ficou no config.toml"
[[ "$config" == *"[mcp_servers.demo]"* ]]                || fail "config.toml perdeu os mcp_servers"
[[ "$config" == *"model_reasoning_effort"* ]]            || fail "config.toml perdeu chaves não relacionadas"

# ── 4. config.toml de terceiros não pode ser tocado ───────────────────
cat > "${CODEX_HOME}/config.toml" <<'TOML'
model = "gpt-5-codex"
model_provider = "meu-provider-custom"
TOML
antes=$(cat "${CODEX_HOME}/config.toml")
run_launcher x
[[ "$(cat "${CODEX_HOME}/config.toml")" == "$antes" ]] \
    || fail "launcher mexeu em config.toml de provider que não é dele"

# ── 5. o Fugu continua sendo o Fugu ───────────────────────────────────
seed_polluted_state
run_launcher fugu
captured=$(cat "$CAPTURE")
[[ "$captured" == *"CMD=codex"* ]] || fail "ai fugu não chamou o codex: ${captured}"
[[ "$captured" == *"-p fugu"* ]]   || fail "ai fugu perdeu o perfil: ${captured}"

# ── 6. ordem do menu: cada grupo começa pela CLI nativa ───────────────
# (1 = Claude, 7 = Codex; o usuário lê o cabeçalho do grupo e escolhe o 1º)
grep -Eq '^menu_row +1 +"\$C_CLAUDE" +"Claude Code"' "${ROOT}/ai" \
    || fail "menu 1 deixou de ser o Claude Code"
grep -Eq '^menu_row +7 +"\$C_CODEX" +"Codex"' "${ROOT}/ai" \
    || fail "menu 7 deixou de ser o Codex"
grep -Eq '^menu_row +8 +"\$C_SAKANA" +"Sakana Fugu"' "${ROOT}/ai" \
    || fail "menu 8 deixou de ser o Sakana Fugu"
grep -q '    7|codex|x)' "${ROOT}/ai" || fail "dispatch do 7 não é o Codex"
grep -q '    8|sakana|fugu)' "${ROOT}/ai" || fail "dispatch do 8 não é o Fugu"

echo "PASS"
