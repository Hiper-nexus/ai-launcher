#!/usr/bin/env bash

# ai mint / macaron / venti / mint-codex: Macaron V1 (Mind Lab / Mint Recursive).
# Testa Claude Code com endpoint Anthropic do Macaron, Codex via responses,
# modelo padrão macaron-v1-coding-venti, override por AI_MACARON_MODEL e
# menu interativo (opção 5).

set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

TEST_HOME="${TMP_DIR}/home"
FAKE_BIN="${TMP_DIR}/bin"
CAPTURE_ENV="${TMP_DIR}/claude-env"
CAPTURE_CODEX="${TMP_DIR}/codex-args"
mkdir -p "$TEST_HOME" "$FAKE_BIN" "${TEST_HOME}/.local/share/ai-launcher" "${TEST_HOME}/.codex"

# Key de teste
printf 'macaron=sk-teste-macaron-123\n' > "${TEST_HOME}/.local/share/ai-launcher/providers.conf"
chmod 600 "${TEST_HOME}/.local/share/ai-launcher/providers.conf"

cat > "${FAKE_BIN}/claude" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
: "${CAPTURE_ENV:?}"
{
    printf 'ANTHROPIC_BASE_URL=%s\n'               "${ANTHROPIC_BASE_URL:-}"
    printf 'ANTHROPIC_MODEL=%s\n'                  "${ANTHROPIC_MODEL:-}"
    printf 'ANTHROPIC_AUTH_TOKEN=%s\n'             "${ANTHROPIC_AUTH_TOKEN:-}"
    printf 'ANTHROPIC_DEFAULT_HAIKU_MODEL=%s\n'    "${ANTHROPIC_DEFAULT_HAIKU_MODEL:-}"
    printf 'ANTHROPIC_DEFAULT_SONNET_MODEL=%s\n'   "${ANTHROPIC_DEFAULT_SONNET_MODEL:-}"
    printf 'ANTHROPIC_DEFAULT_OPUS_MODEL=%s\n'     "${ANTHROPIC_DEFAULT_OPUS_MODEL:-}"
    printf 'ANTHROPIC_DEFAULT_FABLE_MODEL=%s\n'    "${ANTHROPIC_DEFAULT_FABLE_MODEL:-}"
    printf 'CLAUDE_CODE_SUBAGENT_MODEL=%s\n'       "${CLAUDE_CODE_SUBAGENT_MODEL:-}"
    printf 'CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=%s\n' "${CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC:-}"
    printf '_CLAUDE_CODE_ASSUME_FIRST_PARTY_BASE_URL=%s\n' "${_CLAUDE_CODE_ASSUME_FIRST_PARTY_BASE_URL:-}"
} > "$CAPTURE_ENV"
SH
chmod +x "${FAKE_BIN}/claude"

cat > "${FAKE_BIN}/codex" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
: "${CAPTURE_CODEX:?}"
{
    printf 'MACARON_API_KEY=%s\n' "${MACARON_API_KEY:-}"
    printf 'ARGS=%s\n' "$*"
} > "$CAPTURE_CODEX"
SH
chmod +x "${FAKE_BIN}/codex"

fail() { echo "FAIL: $*" >&2; exit 1; }

run_launcher() {
    : > "$CAPTURE_ENV"
    (
        cd "$ROOT"
        HOME="$TEST_HOME" \
        PATH="${FAKE_BIN}:$PATH" \
        CAPTURE_ENV="$CAPTURE_ENV" \
        CAPTURE_CODEX="$CAPTURE_CODEX" \
        "$ROOT/ai" "$@" >/dev/null </dev/null
    )
}

env_is() {
    local key="$1" expected="$2" got
    got=$(grep "^${key}=" "$CAPTURE_ENV" | cut -d= -f2-)
    [[ "$got" == "$expected" ]] ||
        fail "${key}: esperado '${expected}', obtido '${got}'"
}

# 1. ai mint abre Claude Code apontando para mint.macaron.im
run_launcher mint
env_is "ANTHROPIC_BASE_URL" "https://mint.macaron.im"
env_is "ANTHROPIC_MODEL" "macaron-v1-coding-venti"
env_is "ANTHROPIC_AUTH_TOKEN" "sk-teste-macaron-123"
env_is "ANTHROPIC_DEFAULT_HAIKU_MODEL" "macaron-v1-coding-venti"
env_is "ANTHROPIC_DEFAULT_SONNET_MODEL" "macaron-v1-coding-venti"
env_is "ANTHROPIC_DEFAULT_OPUS_MODEL" "macaron-v1-coding-venti"
env_is "ANTHROPIC_DEFAULT_FABLE_MODEL" "macaron-v1-coding-venti"
env_is "CLAUDE_CODE_SUBAGENT_MODEL" "macaron-v1-coding-venti"
env_is "_CLAUDE_CODE_ASSUME_FIRST_PARTY_BASE_URL" "1"

# 2. Aliases macaron e venti funcionam igual
run_launcher macaron
env_is "ANTHROPIC_BASE_URL" "https://mint.macaron.im"
env_is "ANTHROPIC_MODEL" "macaron-v1-coding-venti"

run_launcher venti
env_is "ANTHROPIC_BASE_URL" "https://mint.macaron.im"
env_is "ANTHROPIC_MODEL" "macaron-v1-coding-venti"

# 3. Override de modelo via AI_MACARON_MODEL
(
    cd "$ROOT"
    HOME="$TEST_HOME" \
    PATH="${FAKE_BIN}:$PATH" \
    CAPTURE_ENV="$CAPTURE_ENV" \
    AI_MACARON_MODEL="macaron-v1-venti" \
    "$ROOT/ai" mint >/dev/null </dev/null
)
env_is "ANTHROPIC_MODEL" "macaron-v1-venti"

# 4. ai mint-codex lança Codex com macaron provider e env_key
: > "$CAPTURE_CODEX"
(
    cd "$ROOT"
    HOME="$TEST_HOME" \
    PATH="${FAKE_BIN}:$PATH" \
    CAPTURE_CODEX="$CAPTURE_CODEX" \
    "$ROOT/ai" mint-codex >/dev/null </dev/null
)
codex_key=$(grep "^MACARON_API_KEY=" "$CAPTURE_CODEX" | cut -d= -f2-)
[[ "$codex_key" == "sk-teste-macaron-123" ]] || fail "Codex MACARON_API_KEY esperado 'sk-teste-macaron-123', obtido '$codex_key'"

codex_args=$(grep "^ARGS=" "$CAPTURE_CODEX" | cut -d= -f2-)
[[ "$codex_args" == *"model_provider=macaron"* ]] || fail "Codex ARGS esperado conter 'model_provider=macaron', obtido '$codex_args'"
[[ "$codex_args" == *"-m macaron-v1-coding-venti"* ]] || fail "Codex ARGS esperado conter '-m macaron-v1-coding-venti', obtido '$codex_args'"

# 5. Verifica se config.toml do Codex recebeu [model_providers.macaron]
grep -q '^\[model_providers\.macaron\]' "${TEST_HOME}/.codex/config.toml" || fail "model_providers.macaron não gravado em config.toml"

# 6. Menu interativo: digitar '5' escolhe Macaron V1 no Claude Code
: > "$CAPTURE_ENV"
python3 - <<PY
import os, pty, subprocess, time

master, slave = pty.openpty()
env = os.environ.copy()
env["HOME"] = "$TEST_HOME"
env["PATH"] = "$FAKE_BIN:" + env.get("PATH", "")
env["CAPTURE_ENV"] = "$CAPTURE_ENV"
env["CAPTURE_CODEX"] = "$CAPTURE_CODEX"

proc = subprocess.Popen(
    ["$ROOT/ai"],
    stdin=slave,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    env=env,
    cwd="$ROOT"
)
os.close(slave)
# Escreve '5\n' no pty
time.sleep(0.3)
os.write(master, b"5\n")
try:
    proc.wait(timeout=5)
except subprocess.TimeoutExpired:
    proc.kill()
os.close(master)
PY
env_is "ANTHROPIC_BASE_URL" "https://mint.macaron.im"
env_is "ANTHROPIC_MODEL" "macaron-v1-coding-venti"

echo "PASS: macaron-dispatch (Claude Code, Codex, aliases, override, menu 5)"
