#!/usr/bin/env bash
# Cofre de segredos: no macOS é o Keychain, no Windows é arquivo com ACL
# fechada. Antes disto, no Windows a troca de contas era no-op silencioso —
# `security` não existe e o launcher seguia reportando sucesso.

set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

# shellcheck source=helpers/platform.sh
source "${ROOT}/tests/helpers/platform.sh"

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

# As constantes do cofre derivam de $HOME; apontar para o TMP_DIR mantém o
# teste longe das credenciais reais da máquina.
export HOME="${TMP_DIR}/home"
mkdir -p "$HOME"
ai_secrets_load "$ROOT" || fail "não consegui carregar o cofre"

if ! ai_is_windows; then
    # No macOS/Linux o teste não deve mexer no Keychain de verdade.
    echo "SKIP: cofre em modo Keychain (só o caminho Windows é exercitado aqui)"
    exit 0
fi

# ── mapeamento de serviço → arquivo ──────────────────────
# O slot ativo do Claude é o arquivo do PRÓPRIO Claude Code, não um nosso.
[[ "$(secret_backing_file "$CLAUDE_KEYCHAIN_SERVICE")" == "${HOME}/.claude/.credentials.json" ]] ||
    fail "slot ativo do Claude não aponta para o arquivo do Claude Code"
[[ "$(secret_backing_file "${ACCOUNT_KEYCHAIN_PREFIX}:trabalho")" == "${ACCOUNTS_DIR}/trabalho.cred" ]] ||
    fail "backup de conta Claude com caminho errado"
[[ "$(secret_backing_file "${XACCOUNT_KEYCHAIN_PREFIX}:pessoal")" == "${XACCOUNTS_DIR}/pessoal.cred" ]] ||
    fail "backup de conta Codex com caminho errado"
if secret_backing_file "servico-desconhecido" >/dev/null 2>&1; then
    fail "secret_backing_file aceitou serviço fora do mapa"
fi

secret_store_available || fail "cofre deveria estar disponível no Windows (é arquivo)"

# ── ciclo de vida ────────────────────────────────────────
SVC="${ACCOUNT_KEYCHAIN_PREFIX}:trabalho"
BLOB='{"claudeAiOauth":{"accessToken":"tok-secreto","expiresAt":123}}'

secret_has "$SVC" && fail "cofre vazio não deveria ter o serviço"
secret_get "$SVC" >/dev/null 2>&1 && fail "secret_get devolveu algo de cofre vazio"

secret_set "$SVC" "$BLOB" || fail "secret_set falhou"
secret_has "$SVC" || fail "secret_has não enxergou o que acabou de ser salvo"
[[ "$(secret_get "$SVC")" == "$BLOB" ]] ||
    fail "secret_get devolveu conteúdo diferente do salvo"

# O blob é credencial: tem que nascer restrito ao dono.
assert_secret_file "$(secret_backing_file "$SVC")" ||
    fail "blob salvo pelo cofre não está restrito ao dono"

# Sobrescrever (o -U do keychain) tem que substituir, não concatenar.
secret_set "$SVC" "outro-valor" || fail "secret_set não sobrescreveu"
[[ "$(secret_get "$SVC")" == "outro-valor" ]] ||
    fail "sobrescrita deixou conteúdo antigo"

secret_delete "$SVC" || fail "secret_delete falhou"
secret_has "$SVC" && fail "serviço continua no cofre após delete"
secret_delete "$SVC" && fail "delete de serviço ausente deveria falhar"

# ── troca de conta ponta a ponta ─────────────────────────
# É o fluxo que era no-op no Windows: salvar a conta ativa num backup e depois
# restaurá-la por cima do slot ativo.
ATIVO='{"claudeAiOauth":{"accessToken":"conta-A"}}'
secret_set "$CLAUDE_KEYCHAIN_SERVICE" "$ATIVO" || fail "não salvou o slot ativo"
[[ -f "${HOME}/.claude/.credentials.json" ]] ||
    fail "slot ativo não criou o arquivo do Claude Code"

secret_set "${ACCOUNT_KEYCHAIN_PREFIX}:A" "$(secret_get "$CLAUDE_KEYCHAIN_SERVICE")" ||
    fail "não fez backup da conta ativa"
secret_set "$CLAUDE_KEYCHAIN_SERVICE" '{"claudeAiOauth":{"accessToken":"conta-B"}}' ||
    fail "não trocou o slot ativo"
[[ "$(secret_get "$CLAUDE_KEYCHAIN_SERVICE")" == *"conta-B"* ]] ||
    fail "slot ativo não virou a conta B"

secret_set "$CLAUDE_KEYCHAIN_SERVICE" "$(secret_get "${ACCOUNT_KEYCHAIN_PREFIX}:A")" ||
    fail "não restaurou a conta A"
[[ "$(secret_get "$CLAUDE_KEYCHAIN_SERVICE")" == "$ATIVO" ]] ||
    fail "restauração não devolveu a conta A intacta"

echo "PASS: cofre de segredos"
