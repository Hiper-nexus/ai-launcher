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

# omp falso: registra cada invocação e sai 0, menos para as chaves listadas em
# OMP_FAKE_FAIL_UNKNOWN (simula 'Unknown setting', que deve ser PULADA) e
# OMP_FAKE_FAIL_REAL (erro de verdade, que deve ABORTAR com exit != 0). Sem
# isso o caminho de falha nunca roda e uma regressão que abortasse no primeiro
# 'config set' com erro passaria verde.
cat > "${FAKE_BIN}/omp" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
: "${CAPTURE_ARGS:?}"
printf '%s\n' "$*" >> "$CAPTURE_ARGS"
if [[ "${1:-}" == "config" && "${2:-}" == "get" ]]; then
    printf '%s\n' "${OMP_FAKE_CURRENT:-}"
    exit 0
fi
key="${3:-}"
if [[ -n "${OMP_FAKE_FAIL_UNKNOWN:-}" && "$key" == "${OMP_FAKE_FAIL_UNKNOWN}" ]]; then
    echo "Unknown setting: $key" >&2
    exit 1
fi
if [[ -n "${OMP_FAKE_FAIL_REAL:-}" && "$key" == "${OMP_FAKE_FAIL_REAL}" ]]; then
    echo "Invalid value for $key: schema mismatch" >&2
    exit 1
fi
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

# Igual ao run_ai, mas devolve o exit code em vez de deixar o set -e derrubar
# o teste — usado nos casos que DEVEM falhar.
run_ai_rc() {
    : > "$CAPTURE_ARGS"
    (
        cd "$ROOT"
        HOME="$TEST_HOME" \
        PATH="${FAKE_BIN}:$PATH" \
        CAPTURE_ARGS="$CAPTURE_ARGS" \
        "$ROOT/ai" "$@" >/dev/null 2>&1
    ) && echo 0 || echo $?
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
           retry.fallbackChains task.isolation.mode bashInterceptor.enabled \
           bash.patterns; do
    grep -q "^config set ${key} " "$CAPTURE_ARGS" ||
        fail "chave ausente na afinação: ${key}"
done

# --- bash.patterns é a política de segurança: o conteúdo importa -----------
patterns=$(grep -m1 '^config set bash.patterns ' "$CAPTURE_ARGS")
# 'rm -rf' literal não pega 'rm -fr'/'rm -Rf'; o glob de flag é obrigatório.
grep -q 'rm -\*r\*' <<<"$patterns" ||
    fail "bash.patterns sem glob de flag ('rm -*r*') — 'rm -fr' passaria"
# um curinga logo após a barra casa QUALQUER caminho absoluto e bloqueia
# limpeza legítima de build/temp.
grep -q '"match":"rm -[^"]*/\*"' <<<"$patterns" &&
    fail "bash.patterns tem curinga na raiz — bloquearia 'rm -rf /tmp/build'"
for alvo in 'sudo ' 'git push --force'; do
    grep -qF "$alvo" <<<"$patterns" || fail "bash.patterns sem regra para: ${alvo}"
done

# Roda o launcher com env extra, SEMPRE truncando a captura antes — sobra da
# execução anterior faria uma asserção de ausência passar/falhar por engano.
run_ai_env() {
    local env_assign="$1"; shift
    : > "$CAPTURE_ARGS"
    (
        cd "$ROOT"
        HOME="$TEST_HOME" PATH="${FAKE_BIN}:$PATH" CAPTURE_ARGS="$CAPTURE_ARGS" \
        env "$env_assign" "$ROOT/ai" "$@"
    )
}

# --- chave inexistente é PULADA, não aborta o resto ------------------------
out=$(run_ai_env "OMP_FAKE_FAIL_UNKNOWN=checkpoint.enabled" omp tune config)
grep -q "não existe nesta versão" <<<"$out" ||
    fail "chave desconhecida deveria ser reportada como ausente: ${out}"
grep -q "autolearn.autoContinue" "$CAPTURE_ARGS" ||
    fail "uma chave desconhecida no meio abortou o resto da afinação"

# --- erro REAL não pode ser confundido com 'chave não existe' --------------
: > "$CAPTURE_ARGS"
rc=$(
    cd "$ROOT"
    HOME="$TEST_HOME" PATH="${FAKE_BIN}:$PATH" CAPTURE_ARGS="$CAPTURE_ARGS" \
    env OMP_FAKE_FAIL_REAL=bash.patterns "$ROOT/ai" omp tune config >/dev/null 2>&1
) && rc=0 || rc=$?
[[ "$rc" != "0" ]] ||
    fail "erro real do omp deveria dar exit != 0, obtido ${rc}"

# --- não reduzir silenciosamente uma política de segurança maior -----------
# 30 regras deny na máquina contra as 25 do repo: tem de segurar.
muitas=$(python3 -c 'import json;print(json.dumps([{"match":f"x{i}","approval":"deny"} for i in range(30)]))')
out=$(run_ai_env "OMP_FAKE_CURRENT=${muitas}" omp tune config)
grep -q "política maior" <<<"$out" ||
    fail "afinação reduziu bash.patterns sem avisar: ${out}"
grep -q "^config set bash.patterns " "$CAPTURE_ARGS" &&
    fail "bash.patterns foi gravado apesar da política atual ser maior"

# --- ...mas --force reduz quando o usuário mandar -------------------------
run_ai_env "OMP_FAKE_CURRENT=${muitas}" omp tune config --force >/dev/null
grep -q "^config set bash.patterns " "$CAPTURE_ARGS" ||
    fail "--force deveria aplicar bash.patterns mesmo assim"

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
