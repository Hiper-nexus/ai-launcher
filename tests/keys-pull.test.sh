#!/usr/bin/env bash
# `ai keys pull <host>`: copia slots do providers.conf remoto por SSH sem
# imprimir valores; slots ausentes avisam; o arquivo local fica 600.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d); trap 'rm -rf "$TMP_DIR"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
H="${TMP_DIR}/home"; BIN="${TMP_DIR}/bin"; mkdir -p "$H/.local/share/ai-launcher" "$BIN"
printf 'local=fica\ndashscope=velha\n' > "$H/.local/share/ai-launcher/providers.conf"
printf 'gemini-decision=AQ.segredo-gd-123\ndashscope=sk-segredo-ds-456\noutra=nao-vem\nqwen-base-url=https://evil.example.com/v1\n' > "${TMP_DIR}/remoto.conf"
# ssh falso: confere o host e devolve o providers.conf "remoto"
cat > "$BIN/ssh" <<SH
#!/bin/sh
for a in "\$@"; do last="\$a"; done
echo "\$*" > "${TMP_DIR}/ssh-args"
case " \$* " in *" casa "*) cat "${TMP_DIR}/remoto.conf" ;; *) exit 255 ;; esac
SH
chmod +x "$BIN/ssh"
saida=$(HOME="$H" PATH="$BIN:$PATH" "$ROOT/ai" keys pull casa 2>&1) || fail "keys pull falhou: $saida"
conf="$H/.local/share/ai-launcher/providers.conf"
grep -qx 'gemini-decision=AQ.segredo-gd-123' "$conf" || fail "gemini-decision não veio"
grep -qx 'dashscope=sk-segredo-ds-456' "$conf" || fail "dashscope não foi atualizado"
grep -qx 'local=fica' "$conf" || fail "apagou slot local"
grep -q '^outra=' "$conf" && fail "trouxe slot que não foi pedido"
echo "$saida" | grep -q "qwen-base-url: endpoint fora" || fail "endpoint estranho não foi barrado: $saida"
grep -q '^qwen-base-url=' "$conf" && fail "gravou endpoint fora dos domínios esperados"
echo "$saida" | grep -q "StrictHostKeyChecking=accept-new" && fail "aceitou host na primeira conexão"
echo "$saida" | grep -q "segredo" && fail "imprimiu um valor"
perm=$(stat -f '%Lp' "$conf" 2>/dev/null || stat -c '%a' "$conf"); [[ "$perm" == "600" ]] || fail "perm $perm"
if HOME="$H" PATH="$BIN:$PATH" "$ROOT/ai" keys pull outro-host >/dev/null 2>&1; then fail "host inacessível deveria falhar"; fi
grep -q "StrictHostKeyChecking=yes" "${TMP_DIR}/ssh-args" || fail "ssh sem checagem estrita de host: $(cat "${TMP_DIR}/ssh-args")"
echo "  ok: slots padrão copiados sem eco, locais preservados, extras ignorados, 600; host ruim falha"
# import por stdin (canal do age): mesmos filtros, nada impresso
H2="${TMP_DIR}/home2"; mkdir -p "$H2"
saida=$(printf 'gemini-decision=AQ.import-789\nqwen-base-url=https://x.aliyuncs.com/v1\nlixo=1\n' |
    HOME="$H2" "$ROOT/ai" keys import 2>&1) || fail "keys import falhou: $saida"
grep -qx 'gemini-decision=AQ.import-789' "$H2/.local/share/ai-launcher/providers.conf" || fail "import não gravou"
grep -qx 'qwen-base-url=https://x.aliyuncs.com/v1' "$H2/.local/share/ai-launcher/providers.conf" || fail "import barrou endpoint válido"
grep -q '^lixo=' "$H2/.local/share/ai-launcher/providers.conf" && fail "import trouxe slot não pedido"
echo "$saida" | grep -q "import-789" && fail "import imprimiu valor"
echo "  ok: ai keys import por stdin com os mesmos filtros"
echo "PASS: ai keys pull"
