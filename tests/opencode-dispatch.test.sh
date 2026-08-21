#!/usr/bin/env bash

# Dispatch do opencode. O ponto delicado: o one-shot do opencode é um
# SUBCOMANDO ('opencode run "msg"'), e as flags globais — inclusive --auto —
# NÃO são aceitas antes dele: 'opencode --auto run ...' faz o yargs cuspir o
# help. Por isso o opencode não usa o launch() genérico, que sempre põe as
# flags antes do prompt-flag. Este teste trava essa ordem.

set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

TEST_HOME="${TMP_DIR}/home"
FAKE_BIN="${TMP_DIR}/bin"
CAPTURE_ARGS="${TMP_DIR}/opencode-args"
mkdir -p "$TEST_HOME" "$FAKE_BIN"

cat > "${FAKE_BIN}/opencode" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
: "${CAPTURE_ARGS:?}"
printf '%s\n' "$@" > "$CAPTURE_ARGS"
SH
chmod +x "${FAKE_BIN}/opencode"

fail() { echo "FAIL: $*" >&2; exit 1; }

run_oc() {
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
    got=$(run_oc "$@")
    [[ "$got" == "$expected" ]] ||
        fail "ai $*: esperado '${expected}', obtido '${got}'"
}

# Sem argumentos: TUI com o yolo do opencode. Aqui --auto PODE vir solto.
assert_args '--auto|' opencode
assert_args '--auto|' oc

# Com prompt: vira 'run' e o --auto tem de vir DEPOIS do subcomando.
assert_args 'run|--auto|refatora isso|' oc "refatora isso"
assert_args 'run|--auto|refatora isso|' opencode "refatora isso"

# -m é traduzido para o -m do opencode, depois do run e do --auto.
assert_args 'run|--auto|-m|opencode/claude-sonnet-5|tarefa|' \
    oc -m opencode/claude-sonnet-5 "tarefa"

# --agent/--variant viajam junto, sem engolir o prompt.
assert_args 'run|--auto|--variant|high|tarefa|' oc --variant high "tarefa"

# Sem prompt, -m vale para a TUI (aí sim antes, que é onde o opencode aceita).
assert_args '--auto|-m|opencode/big-pickle|' oc -m opencode/big-pickle

# Subcomandos passam verbatim: sem --auto e sem virar prompt.
assert_args 'auth|list|'  oc auth list
assert_args 'models|'     oc models
assert_args 'upgrade|'    oc upgrade

# Flags informativas idem — 'ai oc --version' não pode virar prompt.
assert_args '--version|' oc --version
assert_args '--help|'    oc --help

echo "PASS: dispatch do opencode"
