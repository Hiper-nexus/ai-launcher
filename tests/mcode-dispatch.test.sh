#!/usr/bin/env bash

# Dispatch do MiniMax Code (mcode). Pontos delicados: a TUI não tem flag de
# yolo — o --permission só existe no one-shot 'mcode exec' — e o exec aceita
# só --model (a TUI usa -m). Este teste trava as duas formas e garante que
# subcomandos nativos passem verbatim, sem virarem prompt.

set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

TEST_HOME="${TMP_DIR}/home"
FAKE_BIN="${TMP_DIR}/bin"
CAPTURE_ARGS="${TMP_DIR}/mcode-args"
mkdir -p "$TEST_HOME" "$FAKE_BIN"

cat > "${FAKE_BIN}/mcode" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
: "${CAPTURE_ARGS:?}"
printf '%s\n' "$@" > "$CAPTURE_ARGS"
SH
chmod +x "${FAKE_BIN}/mcode"

fail() { echo "FAIL: $*" >&2; exit 1; }

run_mc() {
    : > "$CAPTURE_ARGS"
    (
        cd "$ROOT"
        HOME="$TEST_HOME" \
        PATH="${FAKE_BIN}:$PATH" \
        CAPTURE_ARGS="$CAPTURE_ARGS" \
        "$ROOT/ai" "$@" >/dev/null
    )
    tr '\n' '|' < "$CAPTURE_ARGS"
}

assert_args() {
    local expected="$1"; shift
    local got
    got=$(run_mc "$@")
    [[ "$got" == "$expected" ]] ||
        fail "ai $*: esperado '${expected}', obtido '${got}'"
}

# Sem argumentos: TUI limpa (não existe yolo na TUI).
assert_args '|' mcode
assert_args '|' mmc
assert_args '|' minimax

# Com prompt: vira 'exec' e o --permission vem DEPOIS do subcomando.
assert_args 'exec|--permission|full|refatora isso|' mcode "refatora isso"
assert_args 'exec|--permission|full|refatora isso|' mmc "refatora isso"

# -m vira --model no exec (o exec não aceita -m).
assert_args 'exec|--permission|full|--model|minimax/MiniMax-M3|tarefa|' \
    mcode -m minimax/MiniMax-M3 "tarefa"

# Sem prompt, -m fica -m na TUI.
assert_args '-m|minimax/MiniMax-M3|' mcode -m minimax/MiniMax-M3

# -c vira --continue (nome que os dois modos aceitam).
assert_args '--continue|' mcode -c
assert_args 'exec|--permission|full|--continue|segue|' mcode -c "segue"

# Subcomandos passam verbatim: sem --permission e sem virar prompt.
assert_args 'login|--region|global|' mcode login --region global
assert_args 'provider|list|'         mcode provider list
assert_args 'update|'                mcode update
assert_args 'exec|review|'           mcode exec review

# Flags informativas idem — 'ai mcode --version' não pode virar prompt.
assert_args '--version|' mcode --version
assert_args '--help|'    mcode --help

# Painel ('ai mcode menu', o mesmo do item 20): cada opção cai no dispatch.
run_panel() {
    : > "$CAPTURE_ARGS"
    (
        cd "$ROOT"
        printf '%s\n' "$1" | HOME="$TEST_HOME" PATH="${FAKE_BIN}:$PATH" \
            CAPTURE_ARGS="$CAPTURE_ARGS" "$ROOT/ai" mcode menu >/dev/null
    )
    tr '\n' '|' < "$CAPTURE_ARGS"
}
[[ "$(run_panel 0)" == "" ]]                 || fail "painel 0 não deveria chamar o mcode"
[[ "$(run_panel 2)" == "--continue|" ]]      || fail "painel 2: $(run_panel 2)"
[[ "$(run_panel 4)" == "exec|review|" ]]     || fail "painel 4: $(run_panel 4)"
[[ "$(run_panel 5)" == "login|--region|global|" ]] || fail "painel 5: $(run_panel 5)"

echo "PASS: dispatch do MiniMax Code"
