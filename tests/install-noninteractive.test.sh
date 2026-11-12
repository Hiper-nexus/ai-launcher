#!/usr/bin/env bash

# install.sh sem terminal (ssh host './install.sh', T3, CI): com o
# ~/.local/bin fora do PATH ele perguntava se devia mexer no .bashrc. Com a
# entrada fechada o `read` falhava e o `set -e` encerrava o script calado,
# antes de reaplicar Gemini Decision e Qwen no T3; com a entrada aberta,
# travava para sempre. O teste trava: sem terminal ele não pergunta, não
# mexe no .bashrc, avisa como pôr no PATH e chega até o fim.

set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

BASH_DIR=$(dirname "$(command -v bash)")
PY_DIR=$(dirname "$(command -v python3)")
CAMINHO="${BASH_DIR}:${PY_DIR}:/usr/bin:/bin"

roda() {  # $1 = modo da entrada: fechada | aberta
    local home="${TMP_DIR}/home-$1"
    mkdir -p "$home"
    : > "${home}/.bashrc"
    if [[ "$1" == fechada ]]; then
        HOME="$home" PATH="$CAMINHO" bash "$ROOT/install.sh" </dev/null 2>&1
    else
        # Entrada aberta que nunca manda nada (como `ssh host cmd` sem -n).
        HOME="$home" PATH="$CAMINHO" bash "$ROOT/install.sh" < <(sleep 60) 2>&1
    fi
}

for modo in fechada aberta; do
    set +e
    saida=$(timeout 45 bash -c "$(declare -f roda); ROOT='$ROOT' TMP_DIR='$TMP_DIR' CAMINHO='$CAMINHO' roda $modo")
    rc=$?
    set -e
    [[ $rc -ne 124 ]] || fail "entrada ${modo}: install.sh travou esperando resposta"
    [[ $rc -eq 0 ]] || fail "entrada ${modo}: install.sh saiu com ${rc} antes do fim: $(tail -3 <<<"$saida")"
    grep -q "Instalado com sucesso" <<<"$saida" || fail "entrada ${modo}: não chegou ao fim"
    grep -q 'export PATH="\$HOME/.local/bin:\$PATH"' <<<"$saida" || fail "entrada ${modo}: não disse como pôr no PATH"
    [[ ! -s "${TMP_DIR}/home-${modo}/.bashrc" ]] || fail "entrada ${modo}: mexeu no .bashrc sem perguntar"
    echo "  ok: entrada ${modo} → não pergunta, não trava, vai até o fim"
done

echo "PASS: install.sh sem terminal"
