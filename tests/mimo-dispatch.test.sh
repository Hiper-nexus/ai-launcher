#!/usr/bin/env bash

# Dispatch do MiMoCode (Xiaomi MiMo). O ponto delicado: o one-shot do mimo é
# um SUBCOMANDO ('mimo run "msg"'), igual ao opencode — as flags de yolo
# (MIMO_FLAGS) não podem vir antes de 'run'. Este teste trava essa ordem e
# garante que subcomandos nativos passem verbatim, sem virarem prompt.

set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

TEST_HOME="${TMP_DIR}/home"
FAKE_BIN="${TMP_DIR}/bin"
CAPTURE_ARGS="${TMP_DIR}/mimo-args"
mkdir -p "$TEST_HOME" "$FAKE_BIN"

cat > "${FAKE_BIN}/mimo" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
: "${CAPTURE_ARGS:?}"
printf '%s\n' "$@" > "$CAPTURE_ARGS"
SH
chmod +x "${FAKE_BIN}/mimo"

fail() { echo "FAIL: $*" >&2; exit 1; }

run_mi() {
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
    got=$(run_mi "$@")
    [[ "$got" == "$expected" ]] ||
        fail "ai $*: esperado '${expected}', obtido '${got}'"
}

# Sem argumentos: TUI com o yolo do MiMoCode. Aqui as flags PODEM vir soltas.
assert_args '--dangerously-skip-permissions|' mimo
assert_args '--dangerously-skip-permissions|' mi
assert_args '--dangerously-skip-permissions|' mimocode

# Com prompt: vira 'run' e o yolo tem de vir DEPOIS do subcomando.
assert_args 'run|--dangerously-skip-permissions|refatora isso|' mi "refatora isso"
assert_args 'run|--dangerously-skip-permissions|refatora isso|' mimo "refatora isso"

# -m é traduzido para o -m do mimo, depois do run e do yolo.
assert_args 'run|--dangerously-skip-permissions|-m|xiaomi/mimo-v2.5|tarefa|' \
    mi -m xiaomi/mimo-v2.5 "tarefa"

# --agent/--session viajam junto, sem engolir o prompt.
assert_args 'run|--dangerously-skip-permissions|--agent|build|tarefa|' \
    mi --agent build "tarefa"

# Sem prompt, -m vale para a TUI (aí sim junto do yolo).
assert_args '--dangerously-skip-permissions|-m|xiaomi/mimo-v2.5|' \
    mi -m xiaomi/mimo-v2.5

# -c (continue) viaja com a TUI, sem virar prompt.
assert_args '--dangerously-skip-permissions|-c|' mi -c

# Subcomandos passam verbatim: sem yolo e sem virar prompt.
# (providers tem alias auth — o CLI 0.1.14 não tem 'account'.)
assert_args 'providers|'      mi providers
assert_args 'auth|'           mi auth
assert_args 'models|'         mi models
assert_args 'upgrade|'        mi upgrade
assert_args 'run|hello|'      mi run hello

# Flags informativas idem — 'ai mi --version' não pode virar prompt.
assert_args '--version|' mi --version
assert_args '--help|'    mi --help

echo "PASS: dispatch do MiMoCode"
