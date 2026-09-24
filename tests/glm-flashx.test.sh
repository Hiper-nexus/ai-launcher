#!/usr/bin/env bash

# ai glm-flashx: mesmo mecanismo do glm-flash — provider/base_url do GLM com
# o modelo trocado em TODOS os slots. O FlashX (glm-5.3-flashx, lançado
# 18/09/2026) é id próprio no catálogo da Z.ai; o sufixo [1m] viaja em todos
# os slots pelo mesmo motivo do Flash (o client faz o strip antes do wire).
# Este teste trava os quatro slots, a base_url, a key do slot 'glm' e o
# override por AI_GLM_FLASHX_MODEL.

set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

TEST_HOME="${TMP_DIR}/home"
FAKE_BIN="${TMP_DIR}/bin"
CAPTURE_ENV="${TMP_DIR}/claude-env"
mkdir -p "$TEST_HOME" "$FAKE_BIN" "${TEST_HOME}/.local/share/ai-launcher"

printf 'glm=chave-de-teste\n' > "${TEST_HOME}/.local/share/ai-launcher/providers.conf"
chmod 600 "${TEST_HOME}/.local/share/ai-launcher/providers.conf"

cat > "${FAKE_BIN}/claude" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
: "${CAPTURE_ENV:?}"
{
    printf 'ANTHROPIC_BASE_URL=%s\n'             "${ANTHROPIC_BASE_URL:-}"
    printf 'ANTHROPIC_MODEL=%s\n'                "${ANTHROPIC_MODEL:-}"
    printf 'ANTHROPIC_DEFAULT_HAIKU_MODEL=%s\n'  "${ANTHROPIC_DEFAULT_HAIKU_MODEL:-}"
    printf 'ANTHROPIC_DEFAULT_SONNET_MODEL=%s\n' "${ANTHROPIC_DEFAULT_SONNET_MODEL:-}"
    printf 'ANTHROPIC_DEFAULT_OPUS_MODEL=%s\n'   "${ANTHROPIC_DEFAULT_OPUS_MODEL:-}"
    printf 'CLAUDE_CODE_AUTO_COMPACT_WINDOW=%s\n' "${CLAUDE_CODE_AUTO_COMPACT_WINDOW:-}"
    printf 'ANTHROPIC_AUTH_TOKEN=%s\n'           "${ANTHROPIC_AUTH_TOKEN:-}"
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

# Os três aliases levam ao mesmo lugar; os quatro slots no FlashX[1m].
for alias_cmd in glm-flashx glx gfx; do
    run_launcher "$alias_cmd"
    env_is ANTHROPIC_BASE_URL             "https://api.z.ai/api/anthropic"
    env_is ANTHROPIC_MODEL                "glm-5.3-flashx[1m]"
    env_is ANTHROPIC_DEFAULT_HAIKU_MODEL  "glm-5.3-flashx[1m]"
    env_is ANTHROPIC_DEFAULT_SONNET_MODEL "glm-5.3-flashx[1m]"
    env_is ANTHROPIC_DEFAULT_OPUS_MODEL   "glm-5.3-flashx[1m]"
    env_is CLAUDE_CODE_AUTO_COMPACT_WINDOW "1000000"
    # Mesma key do slot 'glm' — o FlashX não é um provider novo.
    env_is ANTHROPIC_AUTH_TOKEN "chave-de-teste"
done

# Override por env var, como no glm/gf.
( export AI_GLM_FLASHX_MODEL="glm-5.3-flash"; run_launcher glx )
env_is ANTHROPIC_MODEL "glm-5.3-flash"

echo "PASS: dispatch do GLM 5.3 FlashX"
