#!/usr/bin/env bash

# ai step: Claude Code roteado pelo Step Plan (StepFun). O ponto delicado é
# o sufixo [1m]: o endpoint da StepFun REJEITA o nome com sufixo (testado
# direto — 400 model_invalid), então o sufixo só pode existir do lado do
# client, que faz o strip antes do wire. Este teste trava os quatro slots
# (step-5-preview[1m] em sonnet/opus/fable, step-3.7-flash em haiku), a
# base_url, a janela de auto-compact de 1M e o subagent no tier barato.

set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

TEST_HOME="${TMP_DIR}/home"
FAKE_BIN="${TMP_DIR}/bin"
CAPTURE_ENV="${TMP_DIR}/claude-env"
mkdir -p "$TEST_HOME" "$FAKE_BIN" "${TEST_HOME}/.local/share/ai-launcher"

# Key falsa: sem ela o provider_setup_env para e pede a key no terminal.
printf 'step=chave-de-teste\n' > "${TEST_HOME}/.local/share/ai-launcher/providers.conf"
chmod 600 "${TEST_HOME}/.local/share/ai-launcher/providers.conf"

cat > "${FAKE_BIN}/claude" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
: "${CAPTURE_ENV:?}"
{
    printf 'ANTHROPIC_BASE_URL=%s\n'               "${ANTHROPIC_BASE_URL:-}"
    printf 'ANTHROPIC_MODEL=%s\n'                  "${ANTHROPIC_MODEL:-}"
    printf 'ANTHROPIC_DEFAULT_HAIKU_MODEL=%s\n'    "${ANTHROPIC_DEFAULT_HAIKU_MODEL:-}"
    printf 'ANTHROPIC_DEFAULT_SONNET_MODEL=%s\n'   "${ANTHROPIC_DEFAULT_SONNET_MODEL:-}"
    printf 'ANTHROPIC_DEFAULT_OPUS_MODEL=%s\n'     "${ANTHROPIC_DEFAULT_OPUS_MODEL:-}"
    printf 'ANTHROPIC_DEFAULT_FABLE_MODEL=%s\n'    "${ANTHROPIC_DEFAULT_FABLE_MODEL:-}"
    printf 'CLAUDE_CODE_SUBAGENT_MODEL=%s\n'       "${CLAUDE_CODE_SUBAGENT_MODEL:-}"
    printf 'CLAUDE_CODE_AUTO_COMPACT_WINDOW=%s\n'  "${CLAUDE_CODE_AUTO_COMPACT_WINDOW:-}"
    printf 'CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=%s\n' "${CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC:-}"
    printf 'ANTHROPIC_AUTH_TOKEN=%s\n'             "${ANTHROPIC_AUTH_TOKEN:-}"
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

# Os três aliases levam ao mesmo lugar. O sufixo [1m] viaja nos slots do
# step-5-preview — o client faz o strip antes do wire, e sem ele o client
# assumiria ~200k de janela para o modelo desconhecido.
for alias_cmd in step sp stepfun; do
    run_launcher "$alias_cmd"
    env_is ANTHROPIC_BASE_URL             "https://api.stepfun.ai/step_plan"
    env_is ANTHROPIC_MODEL                "step-5-preview[1m]"
    env_is ANTHROPIC_DEFAULT_SONNET_MODEL "step-5-preview[1m]"
    env_is ANTHROPIC_DEFAULT_OPUS_MODEL   "step-5-preview[1m]"
    env_is ANTHROPIC_DEFAULT_FABLE_MODEL  "step-5-preview[1m]"
    # Tier barato: Haiku e subagentes no step-3.7-flash (262k, com visão).
    env_is ANTHROPIC_DEFAULT_HAIKU_MODEL  "step-3.7-flash"
    env_is CLAUDE_CODE_SUBAGENT_MODEL     "step-3.7-flash"
    # Janela de 1M: auto-compact com folga antes do teto do step-5-preview.
    env_is CLAUDE_CODE_AUTO_COMPACT_WINDOW "1000000"
    env_is CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC "1"
    env_is ANTHROPIC_AUTH_TOKEN "chave-de-teste"
done

# Override por env var, como nos outros providers.
( export AI_STEP_MODEL="step-3.7-flash"; run_launcher step )
env_is ANTHROPIC_MODEL "step-3.7-flash"

echo "PASS: dispatch do Step Plan (step-5-preview)"
