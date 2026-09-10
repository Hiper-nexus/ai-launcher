#!/usr/bin/env bash

# Dispatch do Devin CLI (Cognition). Dois pontos delicados:
#
# 1. O yolo do devin é '--permission-mode dangerous' (o default 'auto' só
#    auto-aprova leitura). Sem isso o launcher abriria o Devin pedindo
#    aprovação a cada tool.
# 2. '-p/--print' é o one-shot headless e aceita o prompt inline ("-p 'msg'").
#    Ele NÃO consegue mostrar o prompt de workspace trust, então a flag
#    '--respect-workspace-trust false' precisa viajar junto — senão o one-shot
#    falha num diretório ainda não confiado pelo Devin.
#
# Subcomandos (models/doctor/auth/update…) têm de passar verbatim, sem flags
# de yolo e sem virarem prompt.

set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

TEST_HOME="${TMP_DIR}/home"
FAKE_BIN="${TMP_DIR}/bin"
CAPTURE_ARGS="${TMP_DIR}/devin-args"
mkdir -p "$TEST_HOME" "$FAKE_BIN"

cat > "${FAKE_BIN}/devin" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
: "${CAPTURE_ARGS:?}"
printf '%s\n' "$@" > "$CAPTURE_ARGS"
SH
chmod +x "${FAKE_BIN}/devin"

fail() { echo "FAIL: $*" >&2; exit 1; }

run_dv() {
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
    got=$(run_dv "$@")
    [[ "$got" == "$expected" ]] ||
        fail "ai $*: esperado '${expected}', obtido '${got}'"
}

# Sem prompt: TUI, com o yolo e sem -p.
assert_args '--permission-mode|dangerous|--respect-workspace-trust|false|' devin
assert_args '--permission-mode|dangerous|--respect-workspace-trust|false|' dv

# Com prompt: -p antes do texto, flags de yolo antes do -p.
assert_args '--permission-mode|dangerous|--respect-workspace-trust|false|-p|refatora isso|' \
    dv "refatora isso"
assert_args '--permission-mode|dangerous|--respect-workspace-trust|false|-p|refatora isso|' \
    devin "refatora isso"

# Subcomandos passam verbatim: sem flags de yolo e sem virar prompt.
assert_args 'models|'      dv models
assert_args 'doctor|'      dv doctor
assert_args 'auth|login|'  dv auth login
assert_args 'update|'      dv update
assert_args 'cloud|list|'  dv cloud list
assert_args 'ls|'          dv ls
assert_args 'setup|'       dv setup
# 'help' é subcomando do devin (aparece em Commands: do --help). Sem ele aqui,
# 'ai dv help' viraria um one-shot com o prompt "help" em vez de mostrar a ajuda.
assert_args 'help|'        dv help
assert_args 'help|cloud|'  dv help cloud

# Flags informativas idem — 'ai dv --version' não pode virar prompt.
assert_args '--version|' dv --version
assert_args '-V|'        dv -V
assert_args '--help|'    dv --help
# -v não existe no devin (só -V): passa verbatim para o clap reclamar, em vez
# de ser engolido como prompt.
assert_args '-v|'        dv -v

echo "PASS: dispatch do devin"
