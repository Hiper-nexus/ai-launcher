#!/usr/bin/env bash

# ai deepseek-v41 / ds-v41 (DeepSeek V4.1 Flash, GA): mesmo provider/base_url
# do DeepSeek normal, modelo trocado. O ID GA é 'deepseek-flash' — a DeepSeek
# dropou os números de versão, então ele sempre aponta pro V4.1 mais novo
# (changelog: api-docs.deepseek.com/updates/). Este teste trava base_url,
# modelo, token e o override por env var (AI_DEEPSEEK_V41_MODEL).

set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

TEST_HOME="${TMP_DIR}/home"
FAKE_BIN="${TMP_DIR}/bin"
CAPTURE_ENV="${TMP_DIR}/claude-env"
mkdir -p "$TEST_HOME" "$FAKE_BIN" "${TEST_HOME}/.local/share/ai-launcher"

# Key falsa: sem ela o provider_setup_env para e pede a key no terminal.
printf 'deepseek=chave-de-teste\n' > "${TEST_HOME}/.local/share/ai-launcher/providers.conf"
chmod 600 "${TEST_HOME}/.local/share/ai-launcher/providers.conf"

cat > "${FAKE_BIN}/claude" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
: "${CAPTURE_ENV:?}"
{
    printf 'ANTHROPIC_BASE_URL=%s\n'  "${ANTHROPIC_BASE_URL:-}"
    printf 'ANTHROPIC_MODEL=%s\n'     "${ANTHROPIC_MODEL:-}"
    printf 'ANTHROPIC_AUTH_TOKEN=%s\n' "${ANTHROPIC_AUTH_TOKEN:-}"
    printf 'ANTHROPIC_DEFAULT_HAIKU_MODEL=%s\n'  "${ANTHROPIC_DEFAULT_HAIKU_MODEL:-}"
    printf 'ANTHROPIC_DEFAULT_SONNET_MODEL=%s\n' "${ANTHROPIC_DEFAULT_SONNET_MODEL:-}"
    printf 'ANTHROPIC_DEFAULT_OPUS_MODEL=%s\n'   "${ANTHROPIC_DEFAULT_OPUS_MODEL:-}"
    printf 'ANTHROPIC_DEFAULT_FABLE_MODEL=%s\n'  "${ANTHROPIC_DEFAULT_FABLE_MODEL:-}"
    printf 'CLAUDE_CODE_SUBAGENT_MODEL=%s\n'     "${CLAUDE_CODE_SUBAGENT_MODEL:-}"
    printf 'CLAUDE_CODE_EFFORT_LEVEL=%s\n'       "${CLAUDE_CODE_EFFORT_LEVEL:-}"
    printf 'CLAUDE_CODE_AUTO_COMPACT_WINDOW=%s\n' "${CLAUDE_CODE_AUTO_COMPACT_WINDOW:-}"
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

# Todos os aliases levam ao mesmo lugar: provider deepseek + modelo GA com
# sufixo [1m] (janela de 1M no Claude Code; o endpoint ignora o sufixo).
for alias_cmd in deepseek-v41 ds-v41 dsv41 deepseek-beta ds-beta; do
    run_launcher "$alias_cmd"
    env_is ANTHROPIC_BASE_URL  "https://api.deepseek.com/anthropic"
    env_is ANTHROPIC_MODEL     "deepseek-flash[1m]"
    env_is ANTHROPIC_AUTH_TOKEN "chave-de-teste"
    # Slots conforme docs oficiais DeepSeek x Claude Code: Opus/Sonnet no
    # Flash [1m], Haiku e subagentes no Flash simples. Fable=V4-Pro é
    # exceção nossa (tier Pro no /model).
    env_is ANTHROPIC_DEFAULT_HAIKU_MODEL  "deepseek-flash"
    env_is ANTHROPIC_DEFAULT_SONNET_MODEL "deepseek-flash[1m]"
    env_is ANTHROPIC_DEFAULT_OPUS_MODEL   "deepseek-flash[1m]"
    env_is ANTHROPIC_DEFAULT_FABLE_MODEL  "deepseek-v4-pro[1m]"
    env_is CLAUDE_CODE_SUBAGENT_MODEL     "deepseek-flash"
    env_is CLAUDE_CODE_EFFORT_LEVEL       "max"
    env_is CLAUDE_CODE_AUTO_COMPACT_WINDOW "786432"
done

# Override por env var: se a DeepSeek mudar o ID de novo (ou um código
# versionado voltar), a troca é uma linha.
( export AI_DEEPSEEK_V41_MODEL="deepseek-v4.1-flash"; run_launcher ds-v41 )
env_is ANTHROPIC_MODEL "deepseek-v4.1-flash"

# 'ai ds' (menu 4) abre no V4.1 Flash com janela de 1M — mesmo modelo do
# ds-v41; o PROVIDER_MODELS fica com o nome limpo porque o omp o consome.
run_launcher ds
env_is ANTHROPIC_MODEL "deepseek-flash[1m]"
env_is ANTHROPIC_DEFAULT_HAIKU_MODEL  "deepseek-flash"
env_is ANTHROPIC_DEFAULT_SONNET_MODEL "deepseek-flash[1m]"
env_is ANTHROPIC_DEFAULT_OPUS_MODEL   "deepseek-flash[1m]"
# O V4-Pro segue um tier à parte, também com 1M.
run_launcher ds-pro
env_is ANTHROPIC_MODEL "deepseek-v4-pro[1m]"

echo "PASS: dispatch do DeepSeek V4.1 Flash (GA)"
