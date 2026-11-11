#!/usr/bin/env bash
# `ai keys pull <host>`: copia slots do providers.conf remoto por SSH sem
# imprimir valores; slots ausentes avisam; o arquivo local fica 600.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d); trap 'rm -rf "$TMP_DIR"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
H="${TMP_DIR}/home"; BIN="${TMP_DIR}/bin"; mkdir -p "$H/.local/share/ai-launcher" "$BIN"
printf 'local=fica\ndashscope=velha\n' > "$H/.local/share/ai-launcher/providers.conf"
printf 'gemini-decision=AQ.segredo-gd-123\ndashscope=sk-segredo-ds-456\noutra=nao-vem\n' > "${TMP_DIR}/remoto.conf"
# ssh falso: confere o host e devolve o providers.conf "remoto"
cat > "$BIN/ssh" <<SH
#!/bin/sh
for a in "\$@"; do last="\$a"; done
case " \$* " in *" casa "*) cat "${TMP_DIR}/remoto.conf" ;; *) exit 255 ;; esac
SH
chmod +x "$BIN/ssh"
saida=$(HOME="$H" PATH="$BIN:$PATH" "$ROOT/ai" keys pull casa 2>&1) || fail "keys pull falhou: $saida"
conf="$H/.local/share/ai-launcher/providers.conf"
grep -qx 'gemini-decision=AQ.segredo-gd-123' "$conf" || fail "gemini-decision não veio"
grep -qx 'dashscope=sk-segredo-ds-456' "$conf" || fail "dashscope não foi atualizado"
grep -qx 'local=fica' "$conf" || fail "apagou slot local"
grep -q '^outra=' "$conf" && fail "trouxe slot que não foi pedido"
echo "$saida" | grep -q "qwen-base-url: não existe" || fail "slot ausente sem aviso: $saida"
echo "$saida" | grep -q "segredo" && fail "imprimiu um valor"
perm=$(stat -f '%Lp' "$conf" 2>/dev/null || stat -c '%a' "$conf"); [[ "$perm" == "600" ]] || fail "perm $perm"
if HOME="$H" PATH="$BIN:$PATH" "$ROOT/ai" keys pull outro-host >/dev/null 2>&1; then fail "host inacessível deveria falhar"; fi
echo "  ok: slots padrão copiados sem eco, locais preservados, extras ignorados, 600; host ruim falha"
echo "PASS: ai keys pull"
