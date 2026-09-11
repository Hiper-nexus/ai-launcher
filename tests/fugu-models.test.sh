#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

TEST_HOME="${TMP_DIR}/home"
CODEX_HOME="${TMP_DIR}/codex"
FAKE_BIN="${TMP_DIR}/bin"
CAPTURE_ARGS="${TMP_DIR}/codex-args"
CAPTURE_ENV="${TMP_DIR}/provider-env"
mkdir -p "$TEST_HOME" "$CODEX_HOME" "$FAKE_BIN"

cat > "${FAKE_BIN}/codex" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
: "${CAPTURE_ARGS:?}"
printf '%s\n' "$@" > "$CAPTURE_ARGS"
if [[ -n "${CAPTURE_ENV:-}" ]]; then
    printf '%s\n' \
        "${ANTHROPIC_BASE_URL:-}" \
        "${ANTHROPIC_MODEL:-}" \
        "${ANTHROPIC_DEFAULT_SONNET_MODEL:-}" \
        "${ANTHROPIC_DEFAULT_OPUS_MODEL:-}" \
        "${ANTHROPIC_DEFAULT_FABLE_MODEL:-}" \
        "${ANTHROPIC_DEFAULT_HAIKU_MODEL:-}" \
        "${CLAUDE_CODE_SUBAGENT_MODEL:-}" > "$CAPTURE_ENV"
fi
SH
chmod +x "${FAKE_BIN}/codex"
cp "${FAKE_BIN}/codex" "${FAKE_BIN}/claude"

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

# O setup deve espelhar o catálogo oficial usado pelo codex-fugu.
HOME="$TEST_HOME" CODEX_HOME="$CODEX_HOME" PATH="${FAKE_BIN}:$PATH" \
    "$ROOT/ai" fugu setup >/dev/null

grep -q '^model_context_window = 1000000$' "$CODEX_HOME/fugu.config.toml" ||
    fail "perfil fugu sem model_context_window = 1000000"
grep -q '^model_auto_compact_token_limit = 900000$' "$CODEX_HOME/fugu.config.toml" ||
    fail "perfil fugu sem model_auto_compact_token_limit = 900000"
grep -q '^model = "fugu-ultra-v2.0"$' "$CODEX_HOME/fugu.config.toml" ||
    fail "perfil fugu não usa Ultra V2.0 por padrão"

python3 - "$CODEX_HOME/fugu.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    models = json.load(handle)["models"]

efforts_by_model = {
    model["slug"]: [level["effort"] for level in model["supported_reasoning_levels"]]
    for model in models
}
expected = {
    "fugu-ultra-v2.0": ["high", "xhigh", "max"],
    "fugu-max-v1.0": ["high", "xhigh", "max"],
    "fugu-ultra-v1.1": ["high", "xhigh", "max"],
    "fugu-ultra-v1.0": ["high", "xhigh"],
}
if efforts_by_model != expected:
    raise SystemExit(f"catálogo inesperado: {efforts_by_model!r}")
PY

# O setup silencioso também deve substituir catálogos antigos que ainda tenham
# o alias fugu-ultra ou não exponham os novos níveis de raciocínio.
python3 - "$CODEX_HOME/fugu.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    catalog = json.load(handle)
catalog["models"][0]["supported_reasoning_levels"] = catalog["models"][0]["supported_reasoning_levels"][:2]
catalog["models"].append({**catalog["models"][1], "slug": "fugu-ultra"})
with open(sys.argv[1], "w", encoding="utf-8") as handle:
    json.dump(catalog, handle)
PY

assert_invocation "fugu" ""
python3 - "$CODEX_HOME/fugu.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    models = json.load(handle)["models"]
slugs = [model["slug"] for model in models]
ultra = next(model for model in models if model["slug"] == "fugu-ultra-v2.0")
efforts = [level["effort"] for level in ultra["supported_reasoning_levels"]]
if "fugu-ultra" in slugs or efforts != ["high", "xhigh", "max"]:
    raise SystemExit(f"catálogo legado não foi atualizado: {slugs!r} / {efforts!r}")
PY

# Aliases estáveis devem resolver para a versão documentada atual.
assert_invocation "fugu" ""
assert_invocation "fugu-ultra" ""
assert_invocation "fugu-ultra-v2.0" ""
assert_invocation "fugu-max" "fugu-max-v1.0"
assert_invocation "fugu-max-v1.0" "fugu-max-v1.0"
assert_invocation "fugu-ultra-v1.0" "fugu-ultra-v1.0"
assert_invocation "fugu-ultra-20260615" "fugu-ultra-v1.0"
assert_invocation "fugu-ultra-v1.1" "fugu-ultra-v1.1"
assert_invocation "fugu" "fugu-max-v1.0" --model fugu-max -c model_reasoning_effort=max

mapfile -t args < "$CAPTURE_ARGS"
[[ "${args[*]}" == *"-c model_reasoning_effort=max"* ]] ||
    fail "flags de raciocínio não chegaram ao Codex (${args[*]-})"

# A rota genérica do Codex deve usar a mesma resolução.
assert_invocation "x" "" --via fugu-ultra
assert_invocation "x" "fugu-max-v1.0" --via fugu-max

# O endpoint Anthropic-compatible da Sakana também deve estar disponível no
# launcher por um atalho próprio do Claude Code.
: > "$CAPTURE_ARGS"
(
    cd "$ROOT"
    HOME="$TEST_HOME" \
    PATH="${FAKE_BIN}:$PATH" \
    SAKANA_API_KEY="test-sakana-key" \
    CAPTURE_ARGS="$CAPTURE_ARGS" \
    CAPTURE_ENV="$CAPTURE_ENV" \
    "$ROOT/ai" claude-fugu "tarefa" >/dev/null
)
mapfile -t args < "$CAPTURE_ARGS"
[[ "${args[0]:-}" == "--dangerously-skip-permissions" &&
   "${args[1]:-}" == "-p" &&
   "${args[2]:-}" == "tarefa" ]] ||
    fail "claude-fugu não encaminhou a chamada (${args[*]-})"
mapfile -t provider_env < "$CAPTURE_ENV"
[[ "${provider_env[0]:-}" == "https://api.sakana.ai" &&
   "${provider_env[1]:-}" == "fugu-ultra-v2.0" &&
   "${provider_env[2]:-}" == "fugu-ultra-v2.0" &&
   "${provider_env[3]:-}" == "fugu-ultra-v2.0" &&
   "${provider_env[4]:-}" == "fugu-ultra-v2.0" &&
   "${provider_env[5]:-}" == "fugu-max-v1.0" &&
   "${provider_env[6]:-}" == "fugu-max-v1.0" ]] ||
    fail "claude-fugu configurou modelos inválidos (${provider_env[*]-})"

echo "PASS: catálogo e aliases Fugu"
