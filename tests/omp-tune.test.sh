#!/usr/bin/env bash

# 'ai omp tune' provisiona uma máquina nova: aplica a afinação do omp e copia
# as keys do providers.conf para ~/.omp/agent/.env. Dois riscos que o teste
# cobre: 'tune' não pode ser engolido pelo passthrough de subcomandos do omp,
# e o .env não pode perder variáveis que o usuário escreveu à mão.

set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

TEST_HOME="${TMP_DIR}/home"
FAKE_BIN="${TMP_DIR}/bin"
CAPTURE_ARGS="${TMP_DIR}/omp-calls"
PROVIDERS="${TEST_HOME}/.local/share/ai-launcher/providers.conf"
mkdir -p "$TEST_HOME" "$FAKE_BIN" "$(dirname "$PROVIDERS")"

# omp falso: registra cada invocação numa linha e sai 0, menos para a chave
# sentinela, que sai 1 — é assim que se testa o "pulou, não abortou".
cat > "${FAKE_BIN}/omp" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
: "${CAPTURE_ARGS:?}"
printf '%s\n' "$*" >> "$CAPTURE_ARGS"
[[ "${2:-}" == "chave.inexistente" ]] && exit 1
exit 0
SH
chmod +x "${FAKE_BIN}/omp"

cat > "$PROVIDERS" <<'CONF'
glm=key-glm-teste
deepseek=key-deepseek-teste
muse-spark=key-muse-teste
CONF
chmod 600 "$PROVIDERS"

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

run_ai() {
    : > "$CAPTURE_ARGS"
    (
        cd "$ROOT"
        HOME="$TEST_HOME" \
        PATH="${FAKE_BIN}:$PATH" \
        CAPTURE_ARGS="$CAPTURE_ARGS" \
        "$ROOT/ai" "$@"
    )
}

ENV_FILE="${TEST_HOME}/.omp/agent/.env"

# --- 'tune' não pode cair no passthrough de subcomandos do omp -------------
run_ai omp tune --dry >/dev/null
[[ ! -s "$CAPTURE_ARGS" ]] ||
    fail "--dry não pode chamar o omp (chamou: $(cat "$CAPTURE_ARGS"))"

# --- 'setup' AINDA precisa cair no passthrough ----------------------------
run_ai omp setup >/dev/null
grep -qx "setup" "$CAPTURE_ARGS" ||
    fail "'ai omp setup' deveria passar direto pro omp, obtido: $(cat "$CAPTURE_ARGS")"

# --- 'tune config' aplica cada chave via 'config set' ---------------------
run_ai omp tune config >/dev/null
calls=$(grep -c '^config set ' "$CAPTURE_ARGS" || true)
(( calls > 10 )) ||
    fail "esperado >10 'config set', obtido ${calls}"
for key in modelRoles lsp.diagnosticsOnEdit checkpoint.enabled memory.backend \
           retry.fallbackChains task.isolation.mode bashInterceptor.enabled; do
    grep -q "^config set ${key} " "$CAPTURE_ARGS" ||
        fail "chave ausente na afinação: ${key}"
done

# --- 'tune env' traduz slot -> variável que o omp lê ----------------------
run_ai omp tune env >/dev/null
[[ -f "$ENV_FILE" ]] || fail ".env não foi criado"

assert_env() {
    grep -qx "$1=$2" "$ENV_FILE" ||
        fail "esperado '$1=$2' no .env, conteúdo: $(cut -d= -f1 "$ENV_FILE" | tr '\n' ' ')"
}
assert_env ZAI_API_KEY      key-glm-teste
assert_env DEEPSEEK_API_KEY key-deepseek-teste
assert_env META_API_KEY     key-muse-teste

# Slot ausente no providers.conf não vira variável vazia.
grep -q "^SAKANA_API_KEY=" "$ENV_FILE" &&
    fail "slot sakana não existe no providers.conf, não deveria virar variável"

# O arquivo carrega API key: 0600, não mais.
perms=$(stat -f '%Lp' "$ENV_FILE" 2>/dev/null || stat -c '%a' "$ENV_FILE")
[[ "$perms" == "600" ]] || fail ".env deveria ser 600, obtido ${perms}"

# Nenhuma key pode vazar para stdout.
out=$(run_ai omp tune env)
grep -q "key-glm-teste" <<<"$out" &&
    fail "a key vazou para a saída do comando"

# --- variável escrita à mão sobrevive ao regenerar ------------------------
printf 'MINHA_VAR_MANUAL=preservar\n' >> "$ENV_FILE"
run_ai omp tune env >/dev/null
grep -qx "MINHA_VAR_MANUAL=preservar" "$ENV_FILE" ||
    fail "variável não gerenciada foi apagada ao regenerar o .env"

# --- idempotência: rodar duas vezes dá o mesmo arquivo --------------------
first=$(cat "$ENV_FILE")
run_ai omp tune env >/dev/null
[[ "$first" == "$(cat "$ENV_FILE")" ]] ||
    fail "'tune env' não é idempotente"

echo "PASS: ai omp tune"
