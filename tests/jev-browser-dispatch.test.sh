#!/usr/bin/env bash

# `ai jb` / `ai jev-browser` — orquestração do agente de browser (jev-ultrafast).
#
# O launcher NÃO instala código de terceiros: só orquestra o que já está no
# disco e falha com as instruções quando não está. Estes testes cobrem os
# caminhos de falha e a montagem do comando. O caminho feliz (subir o Chrome e
# rodar o agente) não é exercitado aqui de propósito: abriria uma janela e
# faria chamadas pagas.

set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

BASH_BIN="$(command -v bash)"
[[ -n "$BASH_BIN" ]] || { echo "FAIL: bash não encontrado" >&2; exit 1; }

TEST_HOME="${TMP_DIR}/home"
mkdir -p "$TEST_HOME"

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "  ok: $*"; }

run_ai() {
    env -i HOME="$TEST_HOME" PATH="$(dirname "$BASH_BIN"):/usr/bin:/bin" \
        TERM="${TERM:-xterm}" "$BASH_BIN" "$ROOT/ai" "$@" 2>&1
}

echo "── 1. diretório não instalado → instruções, não erro obscuro"
out=$(JEV_DIR="${TMP_DIR}/nao-existe" run_ai jb) || true
echo "$out" | grep -q "não está instalado" || fail "deveria dizer que não está instalado. Saída: $out"
echo "$out" | grep -q "git clone https://github.com/browser-use/jev-ultrafast" \
    || fail "deveria dar o comando de instalação. Saída: $out"
echo "$out" | grep -q "uv sync" || fail "deveria citar o uv sync. Saída: $out"
echo "$out" | grep -q "TYPESAFE_API_KEY" || fail "deveria citar as chaves do .env. Saída: $out"
ok "sem instalação: instruções completas"

echo
echo "── 2. instalado mas sem .env → aponta o que falta"
FAKE_DIR="${TMP_DIR}/jev-ultrafast"
mkdir -p "$FAKE_DIR"
# AI_JEV_BROWSER_DIR é a env que o launcher lê
out=$(env -i HOME="$TEST_HOME" PATH="$(dirname "$BASH_BIN"):/usr/bin:/bin" \
        AI_JEV_BROWSER_DIR="$FAKE_DIR" "$BASH_BIN" "$ROOT/ai" jb 2>&1) || true
echo "$out" | grep -q "Falta o .env" || fail "deveria reclamar do .env. Saída: $out"
echo "$out" | grep -q ".env.example" || fail "deveria dizer de onde copiar. Saída: $out"
ok "sem .env: aponta o arquivo que falta"

echo
echo "── 3. alias 'ai jev-browser' funciona igual"
out=$(env -i HOME="$TEST_HOME" PATH="$(dirname "$BASH_BIN"):/usr/bin:/bin" \
        AI_JEV_BROWSER_DIR="${TMP_DIR}/nao-existe" "$BASH_BIN" "$ROOT/ai" jev-browser 2>&1) || true
echo "$out" | grep -q "não está instalado" || fail "alias jev-browser não roteou. Saída: $out"
ok "alias 'jev-browser' roteia igual a 'jb'"

echo
echo "── 4. a env de configuração é respeitada (não hardcoda o caminho)"
out=$(env -i HOME="$TEST_HOME" PATH="$(dirname "$BASH_BIN"):/usr/bin:/bin" \
        AI_JEV_BROWSER_DIR="${TMP_DIR}/outro-lugar" "$BASH_BIN" "$ROOT/ai" jb 2>&1) || true
echo "$out" | grep -q "${TMP_DIR}/outro-lugar" \
    || fail "deveria usar o caminho da env. Saída: $out"
ok "AI_JEV_BROWSER_DIR é respeitado"

echo
echo "── 5. a chave NÃO aparece na saída de erro"
out=$(env -i HOME="$TEST_HOME" PATH="$(dirname "$BASH_BIN"):/usr/bin:/bin" \
        AI_JEV_BROWSER_DIR="${TMP_DIR}/nao-existe" "$BASH_BIN" "$ROOT/ai" jb 2>&1) || true
if echo "$out" | grep -qE "ts-[A-Za-z0-9_-]{20,}|sk-[A-Za-z0-9]{20,}"; then
    fail "a saída vazou algo com cara de chave"
fi
ok "nenhuma chave na saída"

echo
echo "PASS: jev-browser-dispatch (5/5)"
