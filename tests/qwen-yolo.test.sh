#!/usr/bin/env bash

# Qwen Code 1.0 (core do Qoder, binário nativo). Este teste trava:
#  - o launcher passa o flag de bypass de permissões do 1.0 e o modelo
#    qualificado (provider/modelo), no interativo e no one-shot posicional;
#  - o provider do Token Plan é gravado em ~/.qwen/settings.json com a key
#    LITERAL (o 1.0.0-preview não resolve ${VAR} no apiKey) e chmod 600,
#    preservando o que o usuário já tinha no arquivo;
#  - o model.name legado do 0.x (sem "provider/") é migrado, e uma escolha
#    feita depois no /model do 1.0 não é sobrescrita;
#  - com o Qwen 0.x instalado, o launcher recusa e manda instalar o 1.0
#    (o 0.x lia OPENAI_*, o 1.0 não — rodaria sem modelo nenhum).

set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

TEST_HOME="${TMP_DIR}/home"
FAKE_BIN="${TMP_DIR}/bin"
CAPTURE_ARGS="${TMP_DIR}/qwen-args"
FAKE_VERSION_FILE="${TMP_DIR}/qwen-version"
SETTINGS="${TEST_HOME}/.qwen/settings.json"
KEY="sk-sp-chave-fake-pra-teste"
mkdir -p "$TEST_HOME" "$FAKE_BIN"
echo "1.0.0-preview" > "$FAKE_VERSION_FILE"

cat > "${FAKE_BIN}/qwen" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "--version" ]]; then cat "$FAKE_VERSION_FILE"; exit 0; fi
: "${CAPTURE_ARGS:?}"
printf '%s\n' "$@" > "$CAPTURE_ARGS"
SH
chmod +x "${FAKE_BIN}/qwen"

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

run_qw() {
    : > "$CAPTURE_ARGS"
    (
        cd "$ROOT"
        HOME="$TEST_HOME" \
        PATH="${FAKE_BIN}:$PATH" \
        CAPTURE_ARGS="$CAPTURE_ARGS" \
        FAKE_VERSION_FILE="$FAKE_VERSION_FILE" \
        DASHSCOPE_API_KEY="$KEY" \
        AI_QWEN_BASE_URL="https://token-plan.exemplo.test/compatible-mode/v1" \
        "$ROOT/ai" "$@" >/dev/null 2>&1
    )
    tr '\n' '|' < "$CAPTURE_ARGS"
}

assert_args() {
    local expected="$1"; shift
    local got
    got=$(run_qw "$@")
    [[ "$got" == "$expected" ]] ||
        fail "ai $*: esperado '${expected}', obtido '${got}'"
}

json_get() {
    python3 -I -c 'import json,sys
d=json.load(open(sys.argv[1]))
for k in sys.argv[2].split("."):
    d=d[int(k)] if isinstance(d,list) else d[k]
print(d)' "$SETTINGS" "$1"
}

# settings.json do 0.x: chaves que o usuário tinha precisam sobreviver.
mkdir -p "${TEST_HOME}/.qwen"
cat > "$SETTINGS" <<'JSON'
{"model":{"name":"deepseek-v4-pro-0813"},"mcpServers":{"x":{"command":"/bin/true"}}}
JSON

FLAGS='--dangerously-skip-permissions|-m|alibaba-token-plan/qwen4-max-preview'

# Interativo e one-shot posicional.
assert_args "${FLAGS}|" qw
assert_args "${FLAGS}|" qwen
assert_args "${FLAGS}|refatora isso|" qw "refatora isso"

# Provider gravado com key literal, endpoint do plano e o modelo default.
[[ "$(json_get providers.alibaba-token-plan.apiKey)" == "$KEY" ]] ||
    fail "apiKey do provider não é a key do launcher"
[[ "$(json_get providers.alibaba-token-plan.type)" == "alibaba" ]] ||
    fail "provider não é do tipo alibaba"
[[ "$(json_get providers.alibaba-token-plan.baseUrl)" == "https://token-plan.exemplo.test/compatible-mode/v1" ]] ||
    fail "baseUrl do provider não segue qwen_base_url()"
[[ "$(json_get providers.alibaba-token-plan.models.0.model)" == "qwen4-max-preview" ]] ||
    fail "qwen4-max-preview não é o primeiro modelo do provider"
[[ "$(json_get model.name)" == "alibaba-token-plan/qwen4-max-preview" ]] ||
    fail "model.name legado do 0.x não foi migrado"
[[ "$(json_get mcpServers.x.command)" == "/bin/true" ]] ||
    fail "configuração existente do usuário foi perdida"
perm=$(stat -f '%Lp' "$SETTINGS" 2>/dev/null || stat -c '%a' "$SETTINGS")
[[ "$perm" == "600" ]] || fail "settings.json com a key está com permissão ${perm}, esperado 600"

# Escolha feita depois no /model do 1.0 (já qualificada) não é sobrescrita.
python3 -I -c 'import json,sys
p=sys.argv[1]; d=json.load(open(p)); d["model"]["name"]="alibaba-token-plan/qwen3.8-max"
json.dump(d,open(p,"w"))' "$SETTINGS"
run_qw qw >/dev/null
[[ "$(json_get model.name)" == "alibaba-token-plan/qwen3.8-max" ]] ||
    fail "launcher sobrescreveu o model.name escolhido no /model"

# Qwen 0.x instalado: recusa e não executa.
echo "0.27.2" > "$FAKE_VERSION_FILE"
got=$(run_qw qw || true)
[[ -z "$got" ]] || fail "launcher executou o Qwen 0.x (args: ${got})"

echo "PASS: qwen code 1.0 (flags, modelo, settings)"
