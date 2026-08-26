#!/usr/bin/env bash

# ai glm-flash: mesmo provider/base_url do GLM, modelo trocado em TODOS os
# slots. O ponto delicado: o PROVIDER_EXTRA_ENV do glm exporta sonnet/opus=
# glm-5.3 e haiku=glm-5.3-flash ANTES do override do Flash — se algum slot
# escapar, a sessão mistura duas gerações de modelo sem avisar. Este teste
# trava os quatro slots, a base_url e o mapeamento do 'ai glm' normal (haiku
# = Flash, para o /model da sessão GLM oferecê-lo).

set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

TEST_HOME="${TMP_DIR}/home"
FAKE_BIN="${TMP_DIR}/bin"
CAPTURE_ENV="${TMP_DIR}/claude-env"
mkdir -p "$TEST_HOME" "$FAKE_BIN" "${TEST_HOME}/.local/share/ai-launcher"

# Key falsa: sem ela o provider_setup_env para e pede a key no terminal.
printf 'glm=chave-de-teste\n' > "${TEST_HOME}/.local/share/ai-launcher/providers.conf"
chmod 600 "${TEST_HOME}/.local/share/ai-launcher/providers.conf"

cat > "${FAKE_BIN}/claude" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
: "${CAPTURE_ENV:?}"
{
    printf 'ANTHROPIC_BASE_URL=%s\n'            "${ANTHROPIC_BASE_URL:-}"
    printf 'ANTHROPIC_MODEL=%s\n'               "${ANTHROPIC_MODEL:-}"
    printf 'ANTHROPIC_DEFAULT_HAIKU_MODEL=%s\n' "${ANTHROPIC_DEFAULT_HAIKU_MODEL:-}"
    printf 'ANTHROPIC_DEFAULT_SONNET_MODEL=%s\n' "${ANTHROPIC_DEFAULT_SONNET_MODEL:-}"
    printf 'ANTHROPIC_DEFAULT_OPUS_MODEL=%s\n'  "${ANTHROPIC_DEFAULT_OPUS_MODEL:-}"
    printf 'CLAUDE_CODE_AUTO_COMPACT_WINDOW=%s\n' "${CLAUDE_CODE_AUTO_COMPACT_WINDOW:-}"
    printf 'ANTHROPIC_AUTH_TOKEN=%s\n'          "${ANTHROPIC_AUTH_TOKEN:-}"
} > "$CAPTURE_ENV"
SH
chmod +x "${FAKE_BIN}/claude"

fail() { echo "FAIL: $*" >&2; exit 1; }

run_launcher() {
    : > "$CAPTURE_ENV"
    (
        cd "$ROOT"
        HOME="$TEST_HOME" \
        PATH="${FAKE_BIN}:$PATH" \
        CAPTURE_ENV="$CAPTURE_ENV" \
        "$ROOT/ai" "$@" >/dev/null </dev/null
    )
}

env_is() {
    local key="$1" expected="$2" got
    got=$(grep "^${key}=" "$CAPTURE_ENV" | cut -d= -f2-)
    [[ "$got" == "$expected" ]] ||
        fail "${key}: esperado '${expected}', obtido '${got}'"
}

# Os quatro aliases levam ao mesmo lugar.
for alias_cmd in glm-flash gf zf flash; do
    run_launcher "$alias_cmd"
    env_is ANTHROPIC_BASE_URL             "https://api.z.ai/api/anthropic"
    env_is ANTHROPIC_MODEL                "glm-5.3-flash"
    env_is ANTHROPIC_DEFAULT_HAIKU_MODEL  "glm-5.3-flash"
    env_is ANTHROPIC_DEFAULT_SONNET_MODEL "glm-5.3-flash"
    env_is ANTHROPIC_DEFAULT_OPUS_MODEL   "glm-5.3-flash"
    # O Flash também tem 1M: a janela de auto-compact do GLM continua valendo.
    env_is CLAUDE_CODE_AUTO_COMPACT_WINDOW "1000000"
    # Mesma key do slot 'glm' — o Flash não é um provider novo.
    env_is ANTHROPIC_AUTH_TOKEN "chave-de-teste"
done

# Override por env var, como no glm normal.
( export AI_GLM_FLASH_MODEL="glm-4.7-flash"; run_launcher gf )
env_is ANTHROPIC_MODEL "glm-4.7-flash"

# 'ai glm' segue no 5.3 nos slots sonnet/opus; o haiku é o Flash — é o que
# faz o /model da sessão GLM oferecer o 5.3 Flash sem item de menu próprio.
run_launcher glm
env_is ANTHROPIC_DEFAULT_SONNET_MODEL "glm-5.3"
env_is ANTHROPIC_DEFAULT_OPUS_MODEL   "glm-5.3"
env_is ANTHROPIC_DEFAULT_HAIKU_MODEL  "glm-5.3-flash"

echo "PASS: dispatch do GLM 5.3 Flash"
