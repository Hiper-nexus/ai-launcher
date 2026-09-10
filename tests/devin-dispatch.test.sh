#!/usr/bin/env bash

# Dispatch do Devin CLI (Cognition). Três pontos delicados, todos travados aqui:
#
# 1. O yolo do devin é '--permission-mode dangerous' (o default 'auto' só
#    auto-aprova leitura). Sem isso o launcher abriria o Devin pedindo
#    aprovação a cada tool.
#
# 2. O one-shot precisa ser '-p -- <texto>', com DOIS tokens. O -p/--print do
#    devin tem valor OPCIONAL e o clap não consome como valor um token que
#    começa com '-': sem o separador, qualquer prompt com hífen morre em
#    "error: unexpected argument". Por isso o devin não usa o launch() genérico.
#
# 3. Flags do devin antes do prompt viram flags DE VERDADE, não texto. Sem
#    isso 'ai dv --permission-mode auto "x"' pedia o modo mais seguro e
#    recebia 'dangerous', com o texto virando parte do prompt.
#
# Subcomandos (models/doctor/auth/update…) passam verbatim, sem flags de yolo.

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
        "$ROOT/ai" "$@" >/dev/null 2>&1
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

# O launcher tem de recusar sem nunca chegar a executar o devin.
assert_rejects() {
    : > "$CAPTURE_ARGS"
    if (
        cd "$ROOT"
        HOME="$TEST_HOME" \
        PATH="${FAKE_BIN}:$PATH" \
        CAPTURE_ARGS="$CAPTURE_ARGS" \
        "$ROOT/ai" "$@" >/dev/null 2>&1
    ); then
        fail "ai $*: devia ter falhado, mas saiu com sucesso"
    fi
    [[ ! -s "$CAPTURE_ARGS" ]] ||
        fail "ai $*: devin foi executado mesmo assim ($(tr '\n' '|' < "$CAPTURE_ARGS"))"
}

YOLO='--permission-mode|dangerous|--respect-workspace-trust|false|'

# Sem prompt: TUI, com o yolo e sem -p.
assert_args "$YOLO" devin
assert_args "$YOLO" dv

# Com prompt: '-p -- <texto>'.
assert_args "${YOLO}-p|--|refatora isso|" dv "refatora isso"
assert_args "${YOLO}-p|--|refatora isso|" devin "refatora isso"

# O '--' deixa o texto opaco pro clap: prompt com hífen chega intacto.
assert_args "${YOLO}-p|--|-c continua|"      dv -- "-c continua"
assert_args "${YOLO}-p|--|--model opus|"     dv -- "--model opus"
assert_args "${YOLO}-p|--|prompt; rm -rf /|" dv -- "prompt; rm -rf /"

# Prompt vazio abre a TUI — '$#' conta argumentos, não conteúdo.
assert_args "$YOLO" dv ""

# Flags do devin antes do prompt viram flags de verdade.
assert_args "${YOLO}--continue|"                  dv -c
assert_args "${YOLO}--continue|-p|--|continua|"   dv -c "continua"
assert_args "${YOLO}--resume|abc123|-p|--|segue|" dv -r abc123 "segue"
assert_args "${YOLO}--model|opus|-p|--|tarefa|"   dv --model opus "tarefa"
# O --permission-mode do usuário SUBSTITUI o default do launcher — o clap do
# devin recusa a flag repetida ("cannot be used multiple times"), então o
# 'dangerous' tem de sumir, não ficar na frente.
assert_args '--respect-workspace-trust|false|--permission-mode|auto|-p|--|x|' \
    dv --permission-mode auto "x"
# Idem na forma '=' (o drop é por nome antes do '=').
assert_args '--respect-workspace-trust|false|--permission-mode=smart|-p|--|x|' \
    dv --permission-mode=smart "x"
assert_args "${YOLO}--sandbox|-p|--|x|"          dv --sandbox "x"
# '-p' do usuário é absorvido: devin_launch já emite o '-p --'.
assert_args "${YOLO}-p|--|meu prompt|"           dv -p "meu prompt"

# Token com '-' desconhecido aborta em vez de virar texto do prompt.
assert_rejects dv -x "meu prompt"
assert_rejects dv -p2 "meu prompt"

# --via é do launcher e o devin não o suporta: recusar em vez de ignorar em
# silêncio (e gravar no histórico como se tivesse aplicado).
assert_rejects dv --via deepseek "refatora isso"

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
