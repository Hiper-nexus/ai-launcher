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
echo "── 6. perfil symlinkado é RECUSADO (exfiltração via /tmp)"
# O perfil já foi /tmp/jev-chrome-profile: /tmp é compartilhado e previsível,
# então outro usuário local podia plantar um symlink no caminho e o Chrome
# escreveria o perfil inteiro (cookies, sessões) no alvo do link.
DIR_OK="${TMP_DIR}/agente"
mkdir -p "$DIR_OK" && printf 'TYPESAFE_API_KEY=x\n' > "${DIR_OK}/.env"
LINK="${TMP_DIR}/perfil-symlink"
ALVO="${TMP_DIR}/alvo-do-atacante"
mkdir -p "$ALVO"
ln -s "$ALVO" "$LINK"
out=$(env -i HOME="$TEST_HOME" PATH="$(dirname "$BASH_BIN"):/usr/bin:/bin" \
        AI_JEV_BROWSER_DIR="$DIR_OK" AI_JEV_BROWSER_PROFILE="$LINK" \
        "$BASH_BIN" "$ROOT/ai" jb 2>&1) || true
echo "$out" | grep -qi "symlink" || fail "deveria recusar perfil symlinkado. Saída: $out"
[[ -z "$(ls -A "$ALVO" 2>/dev/null)" ]] || fail "escreveu no alvo do symlink!"
ok "perfil symlinkado: recusado, nada escrito no alvo"

echo
echo "── 7. o perfil default NÃO fica em /tmp"
# Regressão direta: o default já foi /tmp/jev-chrome-profile.
default_profile=$(sed -n 's/.*AI_JEV_BROWSER_PROFILE:-\([^}]*\).*/\1/p' "$ROOT/ai" | head -1)
case "$default_profile" in
    *'/tmp/'*) fail "perfil default voltou para /tmp: $default_profile" ;;
    *'HOME'*)  ok "perfil default sob \$HOME ($default_profile)" ;;
    *)         fail "perfil default inesperado: $default_profile" ;;
esac

echo
echo "── 8. impostor que se declara Chrome é rejeitado"
# A primeira versão AUTENTICAVA O BROWSER PELA RESPOSTA DELE: perguntava na
# porta "você é o Chrome?" e acreditava na string. Qualquer processo local
# escreve "Browser: Chrome" — passava. O conserto não é validar melhor a
# resposta, é não confiar em quem não se conhece: a identidade tem que vir do
# PROCESSO que escuta a porta (argv com o nosso --user-data-dir, dono = nós).
#
# Este teste sobe exatamente o impostor: um servidor que responde /json/version
# se declarando Chrome. Depois prova que _jev_pid_confiavel NÃO o aceita.
python3 - <<'PY' &
import http.server, json
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        body = json.dumps({"Browser": "Chrome/999",
                           "webSocketDebuggerUrl": "ws://127.0.0.1:9455/x"}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, *a): pass
http.server.HTTPServer(("127.0.0.1", 9455), H).serve_forever()
PY
IMPOSTOR=$!
sleep 1.5

FUNCS=$(mktemp)
sed -n '/^_jev_ws_do_log()/,/^}/p;/^_jev_pid_confiavel()/,/^}/p;/^_jev_porta_do_ws()/,/^}/p;/^_jev_ws_garantido()/,/^}$/p' "$ROOT/ai" > "$FUNCS"

# O PID do impostor: escuta a porta mas o argv NÃO tem --user-data-dir nosso.
PID_IMPOSTOR=$(lsof -nP -iTCP:9455 -sTCP:LISTEN -t 2>/dev/null | head -1)
if bash -c "source '$FUNCS'; _jev_pid_confiavel '$PID_IMPOSTOR' '${TMP_DIR}/perfil'" 2>/dev/null; then
    kill $IMPOSTOR 2>/dev/null || true; rm -f "$FUNCS"
    fail "confiou no impostor: PID $PID_IMPOSTOR foi aceito como Chrome nosso"
fi
ok "impostor que se diz Chrome: rejeitado (argv não tem nosso perfil)"

echo
echo "── 9. o parser do anúncio do Chrome"
ws_ok=$(bash -c "source '$FUNCS'
_jev_ws_do_log /dev/stdin" <<< 'DevTools listening on ws://127.0.0.1:61157/devtools/browser/abc-123' 2>/dev/null)
[[ "$ws_ok" == "ws://127.0.0.1:61157/devtools/browser/abc-123" ]] \
    || fail "não parseou a linha do Chrome: '$ws_ok'"
porta_ok=$(bash -c "source '$FUNCS'; _jev_porta_do_ws '$ws_ok'" 2>/dev/null)
[[ "$porta_ok" == "61157" ]] || fail "não extraiu a porta: '$porta_ok'"
# linha de outro formato não pode virar porta
porta_ruim=$(bash -c "source '$FUNCS'; _jev_porta_do_ws 'ws://evil.example.com:9/x'" 2>/dev/null)
[[ -z "$porta_ruim" ]] || fail "aceitou host não-loopback: '$porta_ruim'"
ok "parser do anúncio: linha certa vira ws+porta, host externo é descartado"

kill $IMPOSTOR 2>/dev/null; wait $IMPOSTOR 2>/dev/null || true
rm -f "$FUNCS"

echo
echo "PASS: jev-browser-dispatch (9/9)"
