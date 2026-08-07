#!/usr/bin/env bash

# Dispatch do omp (oh-my-pi): o launcher precisa distinguir três casos que se
# parecem na linha de comando — subcomando do omp (passthrough puro), flag
# conhecida do omp (repassada) e prompt (vai depois do -p). Errar isso faz
# 'ai omp --version' virar uma sessão com o prompt "--version".

set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

TEST_HOME="${TMP_DIR}/home"
FAKE_BIN="${TMP_DIR}/bin"
CAPTURE_ARGS="${TMP_DIR}/omp-args"
mkdir -p "$TEST_HOME" "$FAKE_BIN"

cat > "${FAKE_BIN}/omp" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
: "${CAPTURE_ARGS:?}"
printf '%s\n' "$@" > "$CAPTURE_ARGS"
SH
chmod +x "${FAKE_BIN}/omp"

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

# Roda o launcher e devolve os argumentos capturados numa única linha,
# separados por espaço (basta para comparar; nenhum arg do teste tem espaço
# além do prompt, que é o último).
run_omp() {
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
    got=$(run_omp "$@")
    [[ "$got" == "$expected" ]] ||
        fail "ai $*: esperado '${expected}', obtido '${got}'"
}

# Prompt simples: yolo + modo print.
assert_args '--yolo|-p|refatora isso|' omp "refatora isso"

# Atalho curto usa o mesmo caminho.
assert_args '--yolo|-p|refatora isso|' o "refatora isso"

# -m/--model é traduzido para --model do omp, antes do prompt.
assert_args '--yolo|--model|glm-5.2|-p|tarefa|' omp -m glm-5.2 "tarefa"

# Flags com valor conhecidas do omp são repassadas na ordem.
assert_args '--yolo|--thinking|high|-p|tarefa|' omp --thinking high "tarefa"

# Flags booleanas conhecidas não engolem o prompt.
assert_args '--yolo|--advisor|-p|tarefa|' omp --advisor "tarefa"

# --flag=valor desconhecida é repassada em vez de virar prompt.
assert_args '--yolo|--max-time=10m|-p|tarefa|' omp --max-time=10m "tarefa"

# --via usa os nomes de provider do launcher, traduzidos para os ids do omp,
# e leva junto o modelo default do slot (senão o omp escolheria sozinho entre
# os N modelos do provider e o --via daria resultado diferente do resto do
# launcher, que sempre fixa o modelo).
assert_args '--yolo|--provider|zai|--model|glm-5.2|-p|tarefa|' \
    omp --via glm "tarefa"
assert_args '--yolo|--provider|alibaba-token-plan|--model|qwen3.8-max|-p|tarefa|' \
    omp --via qwen "tarefa"
assert_args '--yolo|--provider|sakana|--model|fugu|-p|tarefa|' \
    omp --via fugu "tarefa"
assert_args '--yolo|--provider|meta|--model|muse-spark-1.2|-p|tarefa|' \
    omp --via muse-spark "tarefa"

# -m explícito ganha do default do provider: um único --model chega no omp.
assert_args '--yolo|--model|glm-4.7|--provider|zai|-p|tarefa|' \
    omp --via glm -m glm-4.7 "tarefa"

# Slot sem modelo default no launcher passa só o provider.
assert_args '--yolo|--provider|lm-studio|-p|tarefa|' omp --via lmstudio "tarefa"

# Subcomandos do omp passam direto: sem --yolo e sem -p.
assert_args 'models|'        omp models
assert_args 'usage|'         omp usage
assert_args 'config|get|modelRoles|' omp config get modelRoles

# Flags informativas também: 'ai omp --version' não pode virar prompt.
assert_args '--version|' omp --version
assert_args '--help|'    omp --help

echo "PASS: dispatch do omp"
