#!/usr/bin/env bash

# Launcher aberto sem LANG (Git Bash filho do pane do Nexus) cai no locale C.
# Lá ${#texto} conta bytes: cada "█" do wordmark vale 3, o laço do banner passa
# das 18 colunas do gradiente e o set -u derruba o menu em BANNER_GRAD[i]
# unbound. O topo do `ai` força C.UTF-8 quando o ambiente não traz UTF-8.
#
# O teste extrai o bloco de locale e as funções do banner e roda num ambiente
# limpo (env -i), sem TTY: o splash inteiro só aparece no menu interativo.

set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

LIB="${TMP_DIR}/lib.sh"
{
    sed -n '/^case "\${LC_ALL:-}\${LC_CTYPE:-}\${LANG:-}" in$/,/^esac$/p' "${ROOT}/ai"
    sed -n '/^_banner_build_gradient() {$/,/^# Desenha o wordmark/p' "${ROOT}/ai"
} > "$LIB"
grep -q '^esac$' "$LIB" || fail "não achei o bloco de locale no topo do ai"
grep -q '^_banner_line()' "$LIB" || fail "não achei _banner_line no ai"

BASH_BIN="$(command -v bash)"

# Desenha uma linha do wordmark sem nenhuma variável de locale herdada.
desenha() {
    env -i PATH="$(dirname "$BASH_BIN"):/usr/bin:/bin" "$@" "$BASH_BIN" -c '
        set -euo pipefail
        source "$1"
        COLOR_DEPTH=24 RESET="" C_QWEN="" BOLD=""
        _banner_build_gradient 18
        _banner_line " ██   ██   ██████ " >/dev/null
        echo OK
    ' _ "$LIB" 2>&1
}

out=$(desenha) || fail "banner quebrou sem LANG: ${out}"
[[ "$out" == *OK* ]] || fail "banner não terminou sem LANG: ${out}"

# Com UTF-8 já no ambiente o bloco não mexe em nada e o banner segue.
out=$(desenha LC_ALL=C.UTF-8) || fail "banner quebrou com LC_ALL=C.UTF-8: ${out}"

echo "PASS: locale-utf8"
