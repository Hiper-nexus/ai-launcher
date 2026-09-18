#!/usr/bin/env bash

# `ai jb` / `ai jev-browser` — orquestração do agente de browser (jev-ultrafast).
#
# O launcher NÃO instala código de terceiros: só orquestra o que já está no
# disco e falha com as instruções quando não está. Estes testes cobrem os
# caminhos de falha e a montagem do comando. O caminho feliz (subir o Chrome e
# rodar o agente) não é exercitado aqui de propósito: abriria uma janela e
# faria chamadas pagas.
#
# As dependências externas (uv, Chrome) entram como STUB no PATH. Antes elas
# vinham da máquina, e num computador sem uv o dispatch parava na checagem de
# dependência — os asserts seguintes testavam a mensagem do uv achando que
# testavam outra coisa.

set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
# Todo processo de fundo entra aqui. Um deles sobrevivendo a um `fail` não é
# só lixo: ele herda o stdout do teste, e o pipeline de quem chamou (`| tail`)
# fica aberto enquanto o fd existir — o que aparece como suíte TRAVADA, não
# como falha. Daí também o >/dev/null em cada um deles abaixo.
BG_PIDS=()
cleanup() {
    local pid
    for pid in ${BG_PIDS[@]+"${BG_PIDS[@]}"}; do
        kill "$pid" 2>/dev/null || true
        wait "$pid" 2>/dev/null || true
    done
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

# Espera o processo de fundo anunciar a porta que escolheu, e devolve o número.
espera_porta() {
    local arquivo="$1" i
    for i in $(seq 1 60); do
        [[ -s "$arquivo" ]] && { cat "$arquivo"; return 0; }
        sleep 0.2
    done
    return 1
}

BASH_BIN="$(command -v bash)"
[[ -n "$BASH_BIN" ]] || { echo "FAIL: bash não encontrado" >&2; exit 1; }

# A camada de plataforma dá ai_os/ai_python/ai_pid_na_porta. `command -v
# python3` não serve no Windows: o alias da Microsoft Store atende por esse
# nome sem Python instalado e só falha ao executar (exit 49).
# shellcheck source=helpers/platform.sh
source "${ROOT}/tests/helpers/platform.sh"
PY_BIN="$(ai_python)" || { echo "FAIL: nenhum Python utilizável" >&2; exit 1; }
export PYTHONIOENCODING=utf-8

TEST_HOME="${TMP_DIR}/home"
FAKE_BIN="${TMP_DIR}/bin"
mkdir -p "$TEST_HOME" "$FAKE_BIN"

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "  ok: $*"; }

# uv e Chrome falsos: presentes o bastante para o dispatch seguir adiante, mas
# inertes. Nenhum dos testes abaixo chega a executá-los.
cat > "${FAKE_BIN}/uv" <<'SH'
#!/usr/bin/env bash
echo "uv-stub $*"
SH
cat > "${FAKE_BIN}/chrome-stub" <<'SH'
#!/usr/bin/env bash
echo "chrome-stub $*"
SH
chmod +x "${FAKE_BIN}/uv" "${FAKE_BIN}/chrome-stub"

run_ai() {
    env -i HOME="$TEST_HOME" \
        PATH="${FAKE_BIN}:$(dirname "$BASH_BIN"):/usr/bin:/bin" \
        AI_JEV_CHROME="${FAKE_BIN}/chrome-stub" \
        TERM="${TERM:-xterm}" "$BASH_BIN" "$ROOT/ai" "$@" 2>&1
}

# Mesma invocação, com envs extras antes do comando.
run_ai_env() {
    local -a envs=()
    while [[ "${1:-}" == *=* ]]; do envs+=("$1"); shift; done
    env -i HOME="$TEST_HOME" \
        PATH="${FAKE_BIN}:$(dirname "$BASH_BIN"):/usr/bin:/bin" \
        AI_JEV_CHROME="${FAKE_BIN}/chrome-stub" \
        TERM="${TERM:-xterm}" "${envs[@]}" \
        "$BASH_BIN" "$ROOT/ai" "$@" 2>&1
}

echo "── 1. diretório não instalado → instruções, não erro obscuro"
out=$(run_ai_env AI_JEV_BROWSER_DIR="${TMP_DIR}/nao-existe" jb) || true
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
out=$(run_ai_env AI_JEV_BROWSER_DIR="$FAKE_DIR" jb) || true
echo "$out" | grep -q "Falta o .env" || fail "deveria reclamar do .env. Saída: $out"
echo "$out" | grep -q ".env.example" || fail "deveria dizer de onde copiar. Saída: $out"
ok "sem .env: aponta o arquivo que falta"

echo
echo "── 3. alias 'ai jev-browser' funciona igual"
out=$(run_ai_env AI_JEV_BROWSER_DIR="${TMP_DIR}/nao-existe" jev-browser) || true
echo "$out" | grep -q "não está instalado" || fail "alias jev-browser não roteou. Saída: $out"
ok "alias 'jev-browser' roteia igual a 'jb'"

echo
echo "── 4. a env de configuração é respeitada (não hardcoda o caminho)"
out=$(run_ai_env AI_JEV_BROWSER_DIR="${TMP_DIR}/outro-lugar" jb) || true
echo "$out" | grep -q "${TMP_DIR}/outro-lugar" \
    || fail "deveria usar o caminho da env. Saída: $out"
ok "AI_JEV_BROWSER_DIR é respeitado"

echo
echo "── 5. a chave NÃO aparece na saída de erro"
out=$(run_ai_env AI_JEV_BROWSER_DIR="${TMP_DIR}/nao-existe" jb) || true
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
# MSYS=winsymlinks:nativestrict: no Git Bash o `ln -s` de diretório faz uma
# CÓPIA por padrão, e o teste passaria a exercitar um diretório comum. Com
# nativestrict ele cria symlink de verdade — ou falha, quando a máquina não
# concede o privilégio (sem Modo Desenvolvedor nem admin). Os dois casos são
# tratados: sem symlink real não há o que testar aqui.
MSYS=winsymlinks:nativestrict ln -s "$ALVO" "$LINK" 2>/dev/null || true
if [[ -L "$LINK" ]]; then
    out=$(run_ai_env AI_JEV_BROWSER_DIR="$DIR_OK" AI_JEV_BROWSER_PROFILE="$LINK" jb) || true
    echo "$out" | grep -qi "symlink" || fail "deveria recusar perfil symlinkado. Saída: $out"
    [[ -z "$(ls -A "$ALVO" 2>/dev/null)" ]] || fail "escreveu no alvo do symlink!"
    ok "perfil symlinkado: recusado, nada escrito no alvo"
else
    echo "  (pulado: esta máquina não cria symlink — sem privilégio no Windows)"
fi

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
# Porta EFÊMERA: com porta fixa, uma execução anterior que tenha deixado
# processo vivo faz o teste inspecionar o processo ERRADO — e então ele passa
# ou falha por um motivo que não é o testado.
cat > "${TMP_DIR}/impostor.py" <<'PY'
import http.server, json, os
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        body = json.dumps({"Browser": "Chrome/999",
                           "webSocketDebuggerUrl": "ws://127.0.0.1:0/x"}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, *a): pass
srv = http.server.HTTPServer(("127.0.0.1", 0), H)
with open(os.environ["PORT_FILE"], "w") as fh:
    fh.write(str(srv.server_address[1]))
srv.serve_forever()
PY
PORT_FILE="${TMP_DIR}/porta-impostor" \
    "$PY_BIN" "${TMP_DIR}/impostor.py" >/dev/null 2>&1 &
IMPOSTOR=$!
BG_PIDS+=("$IMPOSTOR")
PORTA_IMPOSTOR=$(espera_porta "${TMP_DIR}/porta-impostor") || fail "o impostor não subiu"

FUNCS="${TMP_DIR}/funcs.sh"
sed -n '/^_jev_norm_path()/,/^}/p
        /^_jev_pid_confiavel()/,/^}/p
        /^_jev_pid_confiavel_win()/,/^}/p
        /^_jev_ws_do_log()/,/^}/p
        /^_jev_porta_do_ws()/,/^}/p
        /^_jev_chrome_bin()/,/^}/p' "$ROOT/ai" > "$FUNCS"
# shellcheck source=/dev/null
source "$FUNCS"

# O PID do impostor: escuta a porta mas o argv NÃO tem --user-data-dir nosso.
PID_IMPOSTOR=$(ai_pid_na_porta "$PORTA_IMPOSTOR" || true)
[[ -n "$PID_IMPOSTOR" ]] || fail "não descobri quem escuta a ${PORTA_IMPOSTOR} (lsof/netstat)"
if _jev_pid_confiavel "$PID_IMPOSTOR" "${TMP_DIR}/perfil" 2>/dev/null; then
    fail "confiou no impostor: PID $PID_IMPOSTOR foi aceito como Chrome nosso"
fi
ok "impostor que se diz Chrome: rejeitado (argv não tem nosso perfil)"

kill "$IMPOSTOR" 2>/dev/null || true
wait "$IMPOSTOR" 2>/dev/null || true

echo
echo "── 9. o parser do anúncio do Chrome"
ws_ok=$(_jev_ws_do_log /dev/stdin \
    <<< 'DevTools listening on ws://127.0.0.1:61157/devtools/browser/abc-123')
[[ "$ws_ok" == "ws://127.0.0.1:61157/devtools/browser/abc-123" ]] \
    || fail "não parseou a linha do Chrome: '$ws_ok'"
porta_ok=$(_jev_porta_do_ws "$ws_ok")
[[ "$porta_ok" == "61157" ]] || fail "não extraiu a porta: '$porta_ok'"
# linha de outro formato não pode virar porta
porta_ruim=$(_jev_porta_do_ws 'ws://evil.example.com:9/x')
[[ -z "$porta_ruim" ]] || fail "aceitou host não-loopback: '$porta_ruim'"
ok "parser do anúncio: linha certa vira ws+porta, host externo é descartado"

echo
echo "── 10. Chrome ausente → mensagem com a saída (não um caminho fixo)"
out=$(run_ai_env AI_JEV_BROWSER_DIR="$DIR_OK" AI_JEV_CHROME="${TMP_DIR}/nao-ha-chrome" jb) || true
echo "$out" | grep -q "Chrome não encontrado" || fail "deveria dizer que não achou o Chrome. Saída: $out"
echo "$out" | grep -q "AI_JEV_CHROME" || fail "deveria ensinar a apontar o binário. Saída: $out"
ok "Chrome ausente: erro explícito e a env que resolve"

echo
echo "── 12. o caminho do perfil é comparado como CAMINHO, não como texto"
# Windows-only: lá o argv traz o caminho do Windows (barra invertida, o case
# que o Chrome resolveu, às vezes entre aspas) e o nosso perfil nasceu POSIX.
# Comparar as duas strings cruas reprovaria o nosso PRÓPRIO Chrome — e a falha
# apareceria como "não subiu", indistinguível de um problema de verdade.
if [[ "$(ai_os)" != "windows" ]]; then
    echo "  (pulado: $(ai_os) — a normalização de caminho é do Windows)"
else
    PERFIL_POSIX="${TMP_DIR}/perfil-win"
    mkdir -p "$PERFIL_POSIX"
    PERFIL_WIN=$(ai_win_path "$PERFIL_POSIX")
    # de propósito em caixa baixa: se a comparação fosse textual, falharia
    ARGV_PERFIL=$(printf '%s' "$PERFIL_WIN" | tr '[:upper:]' '[:lower:]')

    cat > "${TMP_DIR}/falso-chrome.py" <<'PY'
import http.server, os
srv = http.server.HTTPServer(("127.0.0.1", 0), http.server.BaseHTTPRequestHandler)
with open(os.environ["PORT_FILE"], "w") as fh:
    fh.write(str(srv.server_address[1]))
srv.serve_forever()
PY
    PORT_FILE="${TMP_DIR}/porta-falso-chrome" \
        "$PY_BIN" "${TMP_DIR}/falso-chrome.py" "--user-data-dir=${ARGV_PERFIL}" \
        --no-first-run >/dev/null 2>&1 &
    NOSSO=$!
    BG_PIDS+=("$NOSSO")
    PORTA_NOSSA=$(espera_porta "${TMP_DIR}/porta-falso-chrome") \
        || fail "o chrome falso não subiu"
    PID_NOSSO=$(ai_pid_na_porta "$PORTA_NOSSA" || true)
    [[ -n "$PID_NOSSO" ]] || fail "não descobri quem escuta a ${PORTA_NOSSA}"

    _jev_pid_confiavel "$PID_NOSSO" "$PERFIL_POSIX" \
        || fail "rejeitou processo com o NOSSO perfil no argv (normalização quebrou)"
    ok "argv em caixa baixa e barra invertida: reconhecido como o nosso perfil"

    # E o contrário continua valendo: perfil parecido, mas outro diretório.
    if _jev_pid_confiavel "$PID_NOSSO" "${PERFIL_POSIX}-do-atacante" 2>/dev/null; then
        kill "$NOSSO" 2>/dev/null || true
        fail "aceitou um perfil que não é o nosso"
    fi
    ok "perfil de nome parecido: rejeitado"

    kill "$NOSSO" 2>/dev/null || true
    wait "$NOSSO" 2>/dev/null || true
fi

echo
echo "── 11. permissão do perfil é forçada em TODA execução, não só na criação"
# O perfil do Chrome é um COFRE DE CREDENCIAIS: cookies e tokens de sessão de
# todo site logado ali. A versão anterior só rodava `chmod 700` quando o
# diretório NÃO existia — um diretório pré-existente com 755 (umask de outro
# dia, ou criado à mão) ficava aberto para os outros usuários da máquina.
#
# Este teste stuba o passo que lança o Chrome para poder exercitar o resto do
# dispatch sem abrir janela nem gastar chamada.
DIR_P="${TMP_DIR}/perfil-perms"
mkdir -p "$DIR_P"
chmod 755 "$DIR_P"          # estado inseguro de partida
LOG_P="${DIR_P}/.jev-stderr"
printf 'DevTools listening on ws://127.0.0.1:9/x\n' > "$LOG_P"
chmod 644 "$LOG_P"          # idem: log com permissão de umask

cat > "${TMP_DIR}/stub-uv" <<'SH'
#!/usr/bin/env bash
exit 0
SH
chmod +x "${TMP_DIR}/stub-uv"
# Chrome falso: o dispatch só precisa que _jev_chrome_bin resolva; com o
# _jev_ws_garantido stubado abaixo, o binário nunca é executado.
printf '#!/usr/bin/env bash\nexit 0\n' > "${TMP_DIR}/chrome-falso"
chmod +x "${TMP_DIR}/chrome-falso"

bash -c '
set -uo pipefail
DIR_P="$1"; ROOT="$2"; STUB="$3"
export ROOT
# camada de plataforma (ai_os) + o dispatch e TUDO que ele chama até o
# ponto exercitado. Só jev_browser_dispatch não basta: sem _jev_chrome_bin
# e sem as cores, ele morre antes do secure_dir e o teste aprovaria sem
# testar nada (foi o que o `|| true` engoliu na primeira versão).
# shellcheck source=/dev/null
source "$ROOT/tests/helpers/platform.sh"
source <(sed -n "/^jev_browser_dispatch()/,/^}/p
        /^_jev_chrome_bin()/,/^}/p
        /^secure_dir()/,/^}/p
        /^secure_file()/,/^}/p
        /^_ai_lock_acl()/,/^}/p
        /^ai_win_path()/,/^}/p" "$ROOT/ai")
# cores vazias: ninguém lê saída colorida aqui, e sem elas o set -u aborta
RED="" GREEN="" DIM="" BOLD="" RESET="" YELLOW=""
# fora do alvo do teste: sem escrita no histórico real e sem exec
save_history() { return 0; }
exec_cli() { return 0; }
# substitui o passo que lança o Chrome por um stub
_jev_ws_garantido() { JEV_WS="ws://127.0.0.1:9/x"; JEV_WS_REUSADO=false; return 0; }
# JEV_BROWSER_* (não AI_JEV_BROWSER_*): o launcher resolve o AI_ no CARREGAMENTO,
# então setar o AI_ depois do source não teria efeito e o teste usaria o
# diretório real do usuário.
JEV_BROWSER_DIR="$DIR_P"
JEV_BROWSER_PROFILE="$DIR_P"
AI_JEV_CHROME="$STUB/chrome-falso"
mkdir -p "$DIR_P" && printf "TYPESAFE_API_KEY=x\n" > "$DIR_P/.env"
PATH="$STUB:$PATH" jev_browser_dispatch
' _ "$DIR_P" "$ROOT" "${TMP_DIR}" >/dev/null 2>&1 || true

if [[ "$(ai_os)" != "windows" ]]; then
    perms_dir=$(stat -c '%a' "$DIR_P" 2>/dev/null || stat -f '%Lp' "$DIR_P")
    [[ "$perms_dir" == "700" ]] \
        || fail "perfil pré-existente continuou com $perms_dir (esperado 700)"
else
    # No NTFS o modo POSIX é decorativo: o que fecha é a ACL de dono
    # (secure_dir). Mesma leitura que assert_secret_file faz para arquivo.
    acl_dir=$(icacls.exe "$(cygpath -w "$DIR_P")" 2>/dev/null) \
        || fail "icacls não leu a ACL de $DIR_P"
    n_aces=$(grep -oE '[^ ]+:\([^)]*\)' <<<"$acl_dir" | wc -l | tr -d ' ')
    [[ "$n_aces" -eq 1 ]] \
        || fail "perfil com $n_aces ACEs (esperada 1, a do dono)"
    grep -qi "${USERNAME}" <<<"$acl_dir" \
        || fail "a ACE de $DIR_P não é a do dono"
fi
ok "perfil 755 pré-existente → forçado para 700"

assert_secret_file "$LOG_P" \
    || fail "log do CDP sem proteção de dono (guarda o UUID, que é token de capacidade do browser)"
ok "log do CDP → só o dono lê"

echo
echo "PASS: jev-browser-dispatch"
