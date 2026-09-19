#!/usr/bin/env bash

# ai x: Codex padrão com janela de 1M no provider oficial.
# Verifica flags -c de contexto, override do usuário, opt-out via env
# e ausência das flags em providers alternativos (--via).

set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

TEST_HOME="${TMP_DIR}/home"
CODEX_HOME="${TMP_DIR}/codex"
FAKE_BIN="${TMP_DIR}/bin"
CAPTURE_ARGS="${TMP_DIR}/codex-args"
mkdir -p "$TEST_HOME" "$CODEX_HOME" "$FAKE_BIN"

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
        CODEX_HOME="$CODEX_HOME" \
        PATH="${FAKE_BIN}:$PATH" \
        SAKANA_API_KEY="test-sakana-key" \
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

args_count() {
    local needle="$1" n=0 arg
    while IFS= read -r arg; do
        [[ "$arg" == "$needle" ]] && ((n++))
    done < "$CAPTURE_ARGS"
    echo "$n"
}

# 1. Padrão: x e codex saem com 1M, sem fixar modelo.
for cmd in x codex; do
    run_launcher "$cmd"
    args_have "model_context_window=1000000" ||
        fail "${cmd}: falta -c model_context_window=1000000"
    args_have "model_auto_compact_token_limit=900000" ||
        fail "${cmd}: falta -c model_auto_compact_token_limit=900000"
    args_have "--dangerously-bypass-approvals-and-sandbox" ||
        fail "${cmd}: flags padrão do Codex ausentes"
    args_have "-m" && fail "${cmd}: não deveria fixar modelo (-m)"
done

# 2. Override do usuário vence e não duplica.
run_launcher x -c model_context_window=500000
[[ "$(args_count 'model_context_window=500000')" == "1" ]] ||
    fail "override -c model_context_window=500000 não chegou (args: $(tr '\n' ' ' < "$CAPTURE_ARGS"))"
args_have "model_context_window=1000000" &&
    fail "override deveria suprimir o default 1000000"
args_have "model_auto_compact_token_limit=900000" ||
    fail "override de uma chave não deveria remover a outra"

# 3. Opt-out via env volta ao default do Codex.
: > "$CAPTURE_ARGS"
(
    cd "$ROOT"
    HOME="$TEST_HOME" \
    CODEX_HOME="$CODEX_HOME" \
    PATH="${FAKE_BIN}:$PATH" \
    CAPTURE_ARGS="$CAPTURE_ARGS" \
    AI_CODEX_CONTEXT_WINDOW="" \
    AI_CODEX_AUTOCOMPACT_LIMIT="" \
    "$ROOT/ai" x >/dev/null
)
args_have "model_context_window=1000000" &&
    fail "AI_CODEX_CONTEXT_WINDOW='' deveria desligar a flag"
args_have "model_auto_compact_token_limit=900000" &&
    fail "AI_CODEX_AUTOCOMPACT_LIMIT='' deveria desligar a flag"

# 4. Provider alternativo não recebe as flags (janela é do modelo).
run_launcher x --via fugu-ultra
args_have "model_context_window=1000000" &&
    fail "x --via fugu-ultra não deveria forçar model_context_window"
args_have "model_auto_compact_token_limit=900000" &&
    fail "x --via fugu-ultra não deveria forçar model_auto_compact_token_limit"

echo "OK: codex-default-1m"
