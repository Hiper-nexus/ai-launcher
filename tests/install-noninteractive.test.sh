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

# Só bash e python3 de fora (o /opt/homebrew/bin tem as CLIs reais).
SYSBIN="${TMP_DIR}/sysbin"
mkdir -p "$SYSBIN"
ln -s "$(command -v bash)" "${SYSBIN}/bash"
ln -s "$(command -v python3)" "${SYSBIN}/python3"
CAMINHO="${SYSBIN}:/usr/bin:/bin"

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

# Máquina "da casa" (com a key do Gemini Decision): o install.sh reaplica o
# Qwen no T3. O qwen mora no ~/.local/bin, que não está no PATH do ssh — o
# install.sh precisa achá-lo mesmo assim.
H="${TMP_DIR}/home-casa"
mkdir -p "$H/.local/bin" "$H/.local/share/ai-launcher" "$H/.t3/userdata" "$H/.qwen"
: > "$H/.bashrc"
printf 'gemini-decision=AQ.teste-nao-e-key-de-verdade-000000000000000\n' > "$H/.local/share/ai-launcher/providers.conf"
chmod 600 "$H/.local/share/ai-launcher/providers.conf"
printf '#!/bin/sh\n[ "$1" = "--version" ] && echo 1.0.0-preview\nexit 0\n' > "$H/.local/bin/qwen"
chmod +x "$H/.local/bin/qwen"
echo '{"providerInstances": {}}' > "$H/.t3/userdata/settings.json"
set +e
saida=$(HOME="$H" PATH="$CAMINHO" timeout 120 bash "$ROOT/install.sh" </dev/null 2>&1)
rc=$?
set -e
[[ $rc -eq 0 ]] || fail "máquina com key: install.sh saiu com ${rc}: $(tail -3 <<<"$saida")"
python3 -I - "$H/.t3/userdata/settings.json" "$H/.local/bin/qwen" <<'PY' || fail "install.sh não pôs o Qwen no T3 (qwen fora do PATH?): $(grep -i qwen <<<"$saida" | head -3)"
import json, sys
c = json.load(open(sys.argv[1]))["providerInstances"]["qwen_local"]["config"]
assert c["commandArgs"][1:] == [sys.argv[2], "--acp"] and c["commandArgs"][0].endswith("qwen-acp-proxy.py"), c
PY
echo "  ok: com a key, reaplica o Qwen no T3 achando o qwen no ~/.local/bin"

echo "PASS: install.sh sem terminal"
