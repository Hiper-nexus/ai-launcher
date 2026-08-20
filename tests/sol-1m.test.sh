#!/usr/bin/env bash

# ai sol: Codex com gpt-5.6-sol e janela de 1M por sessão.
# Verifica modelo, flags -c de contexto e a recusa de --via.

set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

TEST_HOME="${TMP_DIR}/home"
FAKE_BIN="${TMP_DIR}/bin"
CAPTURE_ARGS="${TMP_DIR}/codex-args"
mkdir -p "$TEST_HOME" "$FAKE_BIN"

cat > "${FAKE_BIN}/codex" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
: "${CAPTURE_ARGS:?}"
printf '%s\n' "$@" > "$CAPTURE_ARGS"
SH
chmod +x "${FAKE_BIN}/codex"

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

run_launcher() {
    : > "$CAPTURE_ARGS"
    (
        cd "$ROOT"
        HOME="$TEST_HOME" \
        PATH="${FAKE_BIN}:$PATH" \
        CAPTURE_ARGS="$CAPTURE_ARGS" \
        "$ROOT/ai" "$@" >/dev/null
    )
}

args_have() {
    local needle="$1" arg
    while IFS= read -r arg; do
        [[ "$arg" == "$needle" ]] && return 0
    done < "$CAPTURE_ARGS"
    return 1
}

assert_sol_invocation() {
    local command="$1"
    run_launcher "$command"

    args_have "-m" && args_have "gpt-5.6-sol" ||
        fail "${command}: esperado '-m gpt-5.6-sol' (args: $(tr '\n' ' ' < "$CAPTURE_ARGS"))"
    args_have "model_context_window=1000000" ||
        fail "${command}: falta -c model_context_window=1000000"
    args_have "model_auto_compact_token_limit=900000" ||
        fail "${command}: falta -c model_auto_compact_token_limit=900000"
    args_have "--dangerously-bypass-approvals-and-sandbox" ||
        fail "${command}: flags padrão do Codex ausentes"
}

assert_sol_invocation "sol"
assert_sol_invocation "x-1m"
assert_sol_invocation "x1m"

# --via não faz sentido aqui: a janela de 1M é do provider oficial.
: > "$CAPTURE_ARGS"
if (
    cd "$ROOT"
    HOME="$TEST_HOME" PATH="${FAKE_BIN}:$PATH" CAPTURE_ARGS="$CAPTURE_ARGS" \
    "$ROOT/ai" sol --via sakana >/dev/null 2>&1
); then
    fail "sol --via sakana: deveria falhar"
fi
[[ -s "$CAPTURE_ARGS" ]] && fail "sol --via sakana: codex não deveria ser invocado"

echo "OK: sol-1m"
