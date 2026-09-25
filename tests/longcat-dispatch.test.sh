#!/usr/bin/env bash

# ai longcat: Claude Code roteado pela LongCat API Platform (Meituan).
#
# Os pontos delicados, todos testados direto contra a API em 25/09/2026:
#   - o endpoint Anthropic SÓ aceita a key como Bearer (ANTHROPIC_AUTH_TOKEN);
#     via x-api-key (ANTHROPIC_API_KEY) volta 401 missing_api_key;
#   - o id do modelo é case-sensitive (longcat-2.5-preview → 400);
#   - o sufixo [1m] é REJEITADO no wire (400 Unsupported model), mas o Claude
#     Code faz o strip antes de chamar — o sufixo só existe do lado do client,
#     para ele enxergar a janela de 1M em vez de assumir ~200k.
# Este teste trava base_url, os slots, a janela de compact, o teto de output
# da doc oficial, o destino 2.0 e as duas entradas do menu (32 e 'longcat').

set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

TEST_HOME="${TMP_DIR}/home"
FAKE_BIN="${TMP_DIR}/bin"
CAPTURE_ENV="${TMP_DIR}/claude-env"
mkdir -p "$TEST_HOME" "$FAKE_BIN" "${TEST_HOME}/.local/share/ai-launcher"

# Key falsa: sem ela o provider_setup_env para e pede a key no terminal.
printf 'longcat=ak_chave-de-teste\n' > "${TEST_HOME}/.local/share/ai-launcher/providers.conf"
chmod 600 "${TEST_HOME}/.local/share/ai-launcher/providers.conf"

cat > "${FAKE_BIN}/claude" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
: "${CAPTURE_ENV:?}"
{
    printf 'ANTHROPIC_BASE_URL=%s\n'               "${ANTHROPIC_BASE_URL:-}"
    printf 'ANTHROPIC_MODEL=%s\n'                  "${ANTHROPIC_MODEL:-}"
    printf 'ANTHROPIC_DEFAULT_HAIKU_MODEL=%s\n'    "${ANTHROPIC_DEFAULT_HAIKU_MODEL:-}"
    printf 'ANTHROPIC_DEFAULT_SONNET_MODEL=%s\n'   "${ANTHROPIC_DEFAULT_SONNET_MODEL:-}"
    printf 'ANTHROPIC_DEFAULT_OPUS_MODEL=%s\n'     "${ANTHROPIC_DEFAULT_OPUS_MODEL:-}"
    printf 'ANTHROPIC_DEFAULT_FABLE_MODEL=%s\n'    "${ANTHROPIC_DEFAULT_FABLE_MODEL:-}"
    printf 'CLAUDE_CODE_SUBAGENT_MODEL=%s\n'       "${CLAUDE_CODE_SUBAGENT_MODEL:-}"
    printf 'CLAUDE_CODE_AUTO_COMPACT_WINDOW=%s\n'  "${CLAUDE_CODE_AUTO_COMPACT_WINDOW:-}"
    printf 'CLAUDE_CODE_MAX_OUTPUT_TOKENS=%s\n'    "${CLAUDE_CODE_MAX_OUTPUT_TOKENS:-}"
    printf 'CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=%s\n' "${CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC:-}"
    printf 'ANTHROPIC_AUTH_TOKEN=%s\n'             "${ANTHROPIC_AUTH_TOKEN:-}"
    printf 'ANTHROPIC_API_KEY=%s\n'                "${ANTHROPIC_API_KEY:-}"
    printf 'ARGS=%s\n'                             "$*"
} > "$CAPTURE_ENV"
SH
chmod +x "${FAKE_BIN}/claude"

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "  ok: $*"; }

run_launcher() {
    : > "$CAPTURE_ENV"
    (
        cd "$ROOT"
        HOME="$TEST_HOME" \
        PATH="${FAKE_BIN}:$PATH" \
        CAPTURE_ENV="$CAPTURE_ENV" \
        "$ROOT/ai" "$@" >/dev/null </dev/null
    )
}

env_is() {
    local key="$1" expected="$2" got
    got=$(grep "^${key}=" "$CAPTURE_ENV" | cut -d= -f2-)
    [[ "$got" == "$expected" ]] ||
        fail "${key}: esperado '${expected}', obtido '${got}'"
}

# Tudo que o destino 2.5 precisa ter, seja pela CLI ou pelo menu.
assert_longcat_25() {
    env_is ANTHROPIC_BASE_URL             "https://api.longcat.ai/anthropic"
    env_is ANTHROPIC_MODEL                "LongCat-2.5-Preview[1m]"
    env_is ANTHROPIC_DEFAULT_SONNET_MODEL "LongCat-2.5-Preview[1m]"
    env_is ANTHROPIC_DEFAULT_OPUS_MODEL   "LongCat-2.5-Preview[1m]"
    env_is ANTHROPIC_DEFAULT_HAIKU_MODEL  "LongCat-2.5-Preview[1m]"
    env_is CLAUDE_CODE_SUBAGENT_MODEL     "LongCat-2.5-Preview[1m]"
    # O slot Fable deixa o 2.0 alcançável pelo /model sem sair da sessão.
    env_is ANTHROPIC_DEFAULT_FABLE_MODEL  "LongCat-2.0[1m]"
    env_is CLAUDE_CODE_AUTO_COMPACT_WINDOW "1000000"
    # Teto de output da doc oficial (longcat.ai/platform/docs/claude-code).
    env_is CLAUDE_CODE_MAX_OUTPUT_TOKENS  "131072"
    env_is CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC "1"
    # Bearer only: a key vai no AUTH_TOKEN e o API_KEY não pode sobrar.
    env_is ANTHROPIC_AUTH_TOKEN "ak_chave-de-teste"
    env_is ANTHROPIC_API_KEY    ""
}

echo "── 1. aliases da CLI levam ao LongCat 2.5 Preview"
for alias_cmd in longcat lc longcat-2.5 lc25; do
    # Um ANTHROPIC_API_KEY herdado do shell faria o client mandar x-api-key.
    ( export ANTHROPIC_API_KEY="sk-ant-herdada"; run_launcher "$alias_cmd" )
    assert_longcat_25
done
ok "longcat / lc / longcat-2.5 / lc25"

echo "── 2. prompt passa adiante para o Claude"
run_launcher longcat "explique este repo"
grep -q '^ARGS=.*explique este repo' "$CAPTURE_ENV" ||
    fail "prompt não chegou ao claude: $(grep '^ARGS=' "$CAPTURE_ENV")"
ok "prompt one-shot"

echo "── 3. destino LongCat 2.0 em todos os slots"
for alias_cmd in longcat-2 lc2; do
    run_launcher "$alias_cmd"
    env_is ANTHROPIC_BASE_URL             "https://api.longcat.ai/anthropic"
    env_is ANTHROPIC_MODEL                "LongCat-2.0[1m]"
    env_is ANTHROPIC_DEFAULT_SONNET_MODEL "LongCat-2.0[1m]"
    env_is ANTHROPIC_DEFAULT_OPUS_MODEL   "LongCat-2.0[1m]"
    env_is ANTHROPIC_DEFAULT_HAIKU_MODEL  "LongCat-2.0[1m]"
    env_is ANTHROPIC_DEFAULT_FABLE_MODEL  "LongCat-2.0[1m]"
    env_is CLAUDE_CODE_SUBAGENT_MODEL     "LongCat-2.0[1m]"
done
ok "longcat-2 / lc2"

echo "── 4. override por env var"
( export AI_LONGCAT_MODEL="LongCat-2.0"; run_launcher longcat )
env_is ANTHROPIC_MODEL "LongCat-2.0"
env_is CLAUDE_CODE_SUBAGENT_MODEL "LongCat-2.0"
ok "AI_LONGCAT_MODEL"

echo "── 5. menu: '32' abre o painel, '1' lança o 2.5; 'longcat' no prompt também"
# Espera o TEXTO do prompt antes de digitar: resposta que chega antes do read()
# se perde no pty (era o flake do version-cache).
run_menu_pty() {
    : > "$CAPTURE_ENV"
    TEST_HOME="$TEST_HOME" FAKE_BIN="$FAKE_BIN" CAPTURE_ENV="$CAPTURE_ENV" ROOT="$ROOT" \
    python3 - "$@" <<'PY'
import os, pty, subprocess, sys, time, select

steps = sys.argv[1:]  # pares: <texto esperado> <resposta>
master, slave = pty.openpty()
env = os.environ.copy()
env["HOME"] = os.environ["TEST_HOME"]
env["PATH"] = os.environ["FAKE_BIN"] + ":" + env.get("PATH", "")
proc = subprocess.Popen([os.environ["ROOT"] + "/ai"], stdin=slave, stdout=slave,
                        stderr=slave, env=env, cwd=os.environ["ROOT"])
os.close(slave)
buf = b""
def wait_for(text, timeout=20):
    global buf
    end = time.time() + timeout
    while time.time() < end:
        if text.encode() in buf:
            return True
        r, _, _ = select.select([master], [], [], 0.2)
        if r:
            try:
                buf += os.read(master, 65536)
            except OSError:
                return text.encode() in buf
    return False
for i in range(0, len(steps), 2):
    expect, answer = steps[i], steps[i + 1]
    if not wait_for(expect):
        proc.kill()
        sys.exit("prompt não apareceu: %r\n--- saída ---\n%s" % (expect, buf.decode(errors="replace")[-1500:]))
    buf = b""
    os.write(master, (answer + "\n").encode())
try:
    proc.wait(timeout=20)
except subprocess.TimeoutExpired:
    proc.kill()
    sys.exit("launcher não terminou depois da escolha")
PY
}

run_menu_pty "Escolha [1-36/0]" "32" "Escolha [1-4/0]" "1"
assert_longcat_25
ok "menu 32 → painel → 1 (2.5 Preview)"

run_menu_pty "Escolha [1-36/0]" "32" "Escolha [1-4/0]" "2"
env_is ANTHROPIC_MODEL "LongCat-2.0[1m]"
ok "menu 32 → painel → 2 (2.0)"

run_menu_pty "Escolha [1-36/0]" "longcat" "Escolha [1-4/0]" "1"
assert_longcat_25
ok "alias 'longcat' no prompt do menu"

echo "PASS: longcat-dispatch (CLI, aliases, 2.0, override, menu 32)"
