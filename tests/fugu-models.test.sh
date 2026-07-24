#!/usr/bin/env bash

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

assert_invocation() {
    local command="$1"
    local expected_model="${2:-}"
    shift 2

    : > "$CAPTURE_ARGS"
    (
        cd "$ROOT"
        HOME="$TEST_HOME" \
        CODEX_HOME="$CODEX_HOME" \
        PATH="${FAKE_BIN}:$PATH" \
        SAKANA_API_KEY="test-sakana-key" \
        CAPTURE_ARGS="$CAPTURE_ARGS" \
        "$ROOT/ai" "$command" "$@" >/dev/null
    )

    mapfile -t args < "$CAPTURE_ARGS"
    [[ "${args[0]:-}" == "-p" && "${args[1]:-}" == "fugu" ]] ||
        fail "${command}: perfil fugu ausente (${args[*]-})"

    local model=""
    local index
    for index in "${!args[@]}"; do
        if [[ "${args[$index]}" == "-m" || "${args[$index]}" == "--model" ]]; then
            model="${args[$((index + 1))]:-}"
            break
        fi
    done

    [[ "$model" == "$expected_model" ]] ||
        fail "${command}: esperado modelo '${expected_model}', obtido '${model}'"
}

# O setup deve gerar exatamente os seis IDs públicos documentados.
HOME="$TEST_HOME" CODEX_HOME="$CODEX_HOME" PATH="${FAKE_BIN}:$PATH" \
    "$ROOT/ai" fugu setup >/dev/null

python3 - "$CODEX_HOME/fugu.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    slugs = [model["slug"] for model in json.load(handle)["models"]]

expected = [
    "fugu",
    "fugu-ultra",
    "fugu-ultra-v1.0",
    "fugu-ultra-v1.1",
    "fugu-cyber",
    "fugu-cyber-v1.0",
]
if slugs != expected:
    raise SystemExit(f"catálogo inesperado: {slugs!r}")
PY

# Aliases estáveis devem resolver para a versão documentada atual.
assert_invocation "fugu" ""
assert_invocation "fugu-ultra" "fugu-ultra-v1.1"
assert_invocation "fugu-ultra-v1.0" "fugu-ultra-v1.0"
assert_invocation "fugu-ultra-20260615" "fugu-ultra-v1.0"
assert_invocation "fugu-ultra-v1.1" "fugu-ultra-v1.1"
assert_invocation "fugu-cyber" "fugu-cyber-v1.0"
assert_invocation "fugu-cyber-v1.0" "fugu-cyber-v1.0"

# A rota genérica do Codex deve usar a mesma resolução.
assert_invocation "x" "fugu-ultra-v1.1" --via fugu-ultra
assert_invocation "x" "fugu-cyber-v1.0" --via fugu-cyber

echo "PASS: catálogo e aliases Fugu"
