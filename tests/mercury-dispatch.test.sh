#!/usr/bin/env bash

# ai mercury: Claude Code no Mercury 3 (Inception) pela ponte LiteLLM local.
#
# A Inception só expõe /v1/chat/completions (sem /v1/messages e sem
# /v1/responses — testado em 19/10/2026), então o Claude Code fala com uma
# ponte em 127.0.0.1 que traduz Anthropic → OpenAI. Os pontos delicados:
#   - o Claude recebe o TOKEN LOCAL da ponte, nunca a key da Inception;
#   - a key só chega ao processo da ponte (por env);
#   - a ponte é reaproveitada entre sessões, mas cai e sobe de novo quando a
#     key ou a config mudam (assinatura em bridge.sig);
#   - porta ocupada por outro serviço não pode ser confundida com a ponte.
# A ponte aqui é falsa (um http.server que imita o /v1/models do LiteLLM):
# o teste não instala nada nem gasta token da API.

set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)

TEST_HOME="${TMP_DIR}/home"
FAKE_BIN="${TMP_DIR}/bin"
CAPTURE_ENV="${TMP_DIR}/claude-env"
BRIDGE_CAPTURE="${TMP_DIR}/bridge-starts"
MERCURY_HOME="${TEST_HOME}/.local/share/ai-launcher/mercury"
OTHER_PID=""

cleanup() {
    local pid
    pid=$(head -1 "${MERCURY_HOME}/bridge.pid" 2>/dev/null || true)
    [[ -n "$pid" ]] && kill "$pid" 2>/dev/null || true
    [[ -n "$OTHER_PID" ]] && kill "$OTHER_PID" 2>/dev/null || true
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

free_port() {
    python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])'
}
PORT=$(free_port)
export AI_MERCURY_PORT="$PORT"
unset AI_MERCURY_EFFORT AI_MERCURY_MODEL INCEPTION_API_KEY 2>/dev/null || true

mkdir -p "$TEST_HOME" "$FAKE_BIN" "${MERCURY_HOME}/venv/bin"
printf 'inception=sk_chave-de-teste\n' > "${TEST_HOME}/.local/share/ai-launcher/providers.conf"
chmod 600 "${TEST_HOME}/.local/share/ai-launcher/providers.conf"

# Ponte falsa no lugar do venv do LiteLLM (com o marcador de versão, senão o
# launcher tentaria instalar a de verdade).
cat > "${MERCURY_HOME}/venv/bin/litellm" <<'PY'
#!/usr/bin/env python3
import http.server, json, os, re, sys
args = sys.argv[1:]
port = int(args[args.index("--port") + 1])
cfg = open(args[args.index("--config") + 1]).read()
model = re.search(r"model_name: (\S+)", cfg).group(1)
token = os.environ["LITELLM_MASTER_KEY"]
effort = re.search(r"reasoning_effort: (\S+)", cfg)
with open(os.environ["BRIDGE_CAPTURE"], "a") as f:
    f.write("pid=%d key=%s host=%s effort=%s\n" % (
        os.getpid(), os.environ.get("INCEPTION_API_KEY", ""),
        args[args.index("--host") + 1], effort.group(1) if effort else ""))

class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.headers.get("Authorization") != "Bearer " + token:
            self.send_response(401); self.end_headers(); return
        body = json.dumps({"data": [{"id": model}]}).encode()
        self.send_response(200); self.end_headers(); self.wfile.write(body)
    def log_message(self, *a):
        pass

http.server.HTTPServer(("127.0.0.1", port), H).serve_forever()
PY
chmod +x "${MERCURY_HOME}/venv/bin/litellm"
grep -E '^MERCURY_LITELLM_VERSION=' "${ROOT}/ai" | cut -d'"' -f2 > "${MERCURY_HOME}/venv/.ai-launcher-litellm"

cat > "${FAKE_BIN}/claude" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
: "${CAPTURE_ENV:?}"
{
    printf 'ANTHROPIC_BASE_URL=%s\n'               "${ANTHROPIC_BASE_URL:-}"
    printf 'ANTHROPIC_AUTH_TOKEN=%s\n'             "${ANTHROPIC_AUTH_TOKEN:-}"
    printf 'ANTHROPIC_API_KEY=%s\n'                "${ANTHROPIC_API_KEY:-}"
    printf 'ANTHROPIC_MODEL=%s\n'                  "${ANTHROPIC_MODEL:-}"
    printf 'ANTHROPIC_DEFAULT_HAIKU_MODEL=%s\n'    "${ANTHROPIC_DEFAULT_HAIKU_MODEL:-}"
    printf 'ANTHROPIC_DEFAULT_SONNET_MODEL=%s\n'   "${ANTHROPIC_DEFAULT_SONNET_MODEL:-}"
    printf 'ANTHROPIC_DEFAULT_OPUS_MODEL=%s\n'     "${ANTHROPIC_DEFAULT_OPUS_MODEL:-}"
    printf 'ANTHROPIC_DEFAULT_FABLE_MODEL=%s\n'    "${ANTHROPIC_DEFAULT_FABLE_MODEL:-}"
    printf 'CLAUDE_CODE_SUBAGENT_MODEL=%s\n'       "${CLAUDE_CODE_SUBAGENT_MODEL:-}"
    printf 'CLAUDE_CODE_AUTO_COMPACT_WINDOW=%s\n'  "${CLAUDE_CODE_AUTO_COMPACT_WINDOW:-}"
    printf 'CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=%s\n' "${CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC:-}"
    printf 'API_TIMEOUT_MS=%s\n'                   "${API_TIMEOUT_MS:-}"
    printf 'INCEPTION_API_KEY=%s\n'                "${INCEPTION_API_KEY:-}"
    printf 'ARGS=%s\n'                             "$*"
} > "$CAPTURE_ENV"
SH
chmod +x "${FAKE_BIN}/claude"

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "  ok: $*"; }

run_launcher() {
    : > "$CAPTURE_ENV"
    (
        cd "$ROOT"
        HOME="$TEST_HOME" \
        PATH="${FAKE_BIN}:$PATH" \
        CAPTURE_ENV="$CAPTURE_ENV" \
        BRIDGE_CAPTURE="$BRIDGE_CAPTURE" \
        "$ROOT/ai" "$@" >/dev/null 2>&1 </dev/null
    )
}

env_is() {
    local key="$1" expected="$2" got
    got=$(grep "^${key}=" "$CAPTURE_ENV" | cut -d= -f2-)
    [[ "$got" == "$expected" ]] ||
        fail "${key}: esperado '${expected}', obtido '${got}'"
}

bridge_starts() { grep -c '^pid=' "$BRIDGE_CAPTURE" 2>/dev/null || true; }

assert_mercury_env() {
    env_is ANTHROPIC_BASE_URL "http://127.0.0.1:${PORT}"
    # O Claude recebe o token local da ponte; a key da Inception não vaza.
    env_is ANTHROPIC_AUTH_TOKEN "$(head -1 "${MERCURY_HOME}/bridge.token")"
    env_is ANTHROPIC_API_KEY ""
    env_is INCEPTION_API_KEY ""
    for k in ANTHROPIC_MODEL ANTHROPIC_DEFAULT_HAIKU_MODEL ANTHROPIC_DEFAULT_SONNET_MODEL \
             ANTHROPIC_DEFAULT_OPUS_MODEL ANTHROPIC_DEFAULT_FABLE_MODEL CLAUDE_CODE_SUBAGENT_MODEL; do
        env_is "$k" "mercury-3[1m]"
    done
    env_is CLAUDE_CODE_AUTO_COMPACT_WINDOW "1000000"
    env_is CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC "1"
    env_is API_TIMEOUT_MS "600000"
}

echo "── 1. aliases da CLI levam ao Mercury 3 pela ponte"
for alias_cmd in mercury merc inception mercury-3; do
    # Uma key Anthropic herdada do shell faria o client mandar x-api-key.
    ( export ANTHROPIC_API_KEY="sk-ant-herdada"; run_launcher "$alias_cmd" )
    assert_mercury_env
done
grep -q '^sk-ai-[0-9a-f]\{48\}$' "${MERCURY_HOME}/bridge.token" || fail "token local fora do formato"
[[ "$(stat -f '%Lp' "${MERCURY_HOME}/bridge.token" 2>/dev/null || stat -c '%a' "${MERCURY_HOME}/bridge.token")" == 600 ]] ||
    fail "bridge.token não é 600"
ok "mercury / merc / inception / mercury-3"

echo "── 2. a key vai só para a ponte, que escuta em 127.0.0.1 e é reaproveitada"
[[ "$(bridge_starts)" == 1 ]] || fail "4 sessões subiram $(bridge_starts) pontes (esperado 1)"
grep -q '^pid=[0-9]* key=sk_chave-de-teste host=127.0.0.1 ' "$BRIDGE_CAPTURE" ||
    fail "ponte não recebeu a key/host certos: $(cat "$BRIDGE_CAPTURE")"
ok "1 ponte para 4 sessões, key por env, host local"

echo "── 3. trocar a key derruba a ponte velha e sobe outra"
old_pid=$(head -1 "${MERCURY_HOME}/bridge.pid")
run_launcher mercury key sk_chave-nova
run_launcher mercury
[[ "$(bridge_starts)" == 2 ]] || fail "key nova não reiniciou a ponte"
tail -1 "$BRIDGE_CAPTURE" | grep -q 'key=sk_chave-nova ' || fail "ponte nova sem a key nova"
! kill -0 "$old_pid" 2>/dev/null || fail "ponte velha (pid ${old_pid}) continua viva"
assert_mercury_env
ok "restart na troca de key"

echo "── 4. AI_MERCURY_EFFORT entra na config (e valor inválido não lança nada)"
( export AI_MERCURY_EFFORT=high; run_launcher mercury )
tail -1 "$BRIDGE_CAPTURE" | grep -q 'effort=high$' || fail "reasoning_effort não chegou à ponte"
: > "$CAPTURE_ENV"
( export AI_MERCURY_EFFORT='high\n  api_base: http://evil'; run_launcher mercury ) && fail "esforço inválido foi aceito"
[[ ! -s "$CAPTURE_ENV" ]] || fail "claude rodou com esforço inválido"
ok "effort válido vai para o YAML; inválido para antes"

echo "── 5. prompt passa adiante; '--via mercury' no 'ai c' usa a mesma ponte"
run_launcher mercury "explique este repo"
grep -q '^ARGS=.*explique este repo' "$CAPTURE_ENV" ||
    fail "prompt não chegou ao claude: $(grep '^ARGS=' "$CAPTURE_ENV")"
run_launcher c --via mercury
assert_mercury_env
ok "one-shot e --via"

echo "── 6. 'ai mercury stop' derruba a ponte"
pid=$(head -1 "${MERCURY_HOME}/bridge.pid")
run_launcher mercury stop
! kill -0 "$pid" 2>/dev/null || fail "ponte continua viva depois do stop"
[[ ! -e "${MERCURY_HOME}/bridge.pid" ]] || fail "bridge.pid sobrou"
ok "stop"

echo "── 7. porta ocupada por outro serviço não vira 'ponte'"
python3 -m http.server "$PORT" --bind 127.0.0.1 >/dev/null 2>&1 &
OTHER_PID=$!
for _ in {1..40}; do curl -s -o /dev/null "http://127.0.0.1:${PORT}/" && break; sleep 0.25; done
starts=$(bridge_starts)
run_launcher mercury && fail "lançou com a porta ocupada por outro serviço"
[[ ! -s "$CAPTURE_ENV" ]] || fail "claude rodou apontando para o serviço errado"
[[ "$(bridge_starts)" == "$starts" ]] || fail "subiu ponte em cima da porta ocupada"
kill "$OTHER_PID" 2>/dev/null || true
wait "$OTHER_PID" 2>/dev/null || true
OTHER_PID=""
ok "porta alheia recusada"

echo "── 8. sem key e sem terminal: erro, sem abrir o Claude"
printf 'glm=outra\n' > "${TEST_HOME}/.local/share/ai-launcher/providers.conf"
run_launcher mercury && fail "lançou sem key"
[[ ! -s "$CAPTURE_ENV" ]] || fail "claude rodou sem key"
printf 'inception=sk_chave-de-teste\n' > "${TEST_HOME}/.local/share/ai-launcher/providers.conf"
ok "sem key → erro"

echo "── 9. menu: '7' (logo abaixo do LongCat) abre o painel; 'mercury' no prompt também"
# Espera o TEXTO do prompt antes de digitar: resposta que chega antes do read()
# se perde no pty (era o flake do version-cache).
run_menu_pty() {
    : > "$CAPTURE_ENV"
    TEST_HOME="$TEST_HOME" FAKE_BIN="$FAKE_BIN" CAPTURE_ENV="$CAPTURE_ENV" ROOT="$ROOT" \
    BRIDGE_CAPTURE="$BRIDGE_CAPTURE" \
    python3 - "$@" <<'PY'
import os, pty, subprocess, sys, time, select

steps = sys.argv[1:]  # pares: <texto esperado> <resposta>
master, slave = pty.openpty()
env = os.environ.copy()
env["HOME"] = os.environ["TEST_HOME"]
env["PATH"] = os.environ["FAKE_BIN"] + ":" + env.get("PATH", "")
proc = subprocess.Popen([os.environ["ROOT"] + "/ai"], stdin=slave, stdout=slave,
                        stderr=slave, env=env, cwd=os.environ["ROOT"])
os.close(slave)
buf = b""
def wait_for(text, timeout=30):
    global buf
    end = time.time() + timeout
    while time.time() < end:
        if text.encode() in buf:
            return True
        r, _, _ = select.select([master], [], [], 0.2)
        if r:
            try:
                buf += os.read(master, 65536)
            except OSError:
                return text.encode() in buf
    return False
for i in range(0, len(steps), 2):
    expect, answer = steps[i], steps[i + 1]
    if not wait_for(expect):
        proc.kill()
        sys.exit("prompt não apareceu: %r\n--- saída ---\n%s" % (expect, buf.decode(errors="replace")[-1500:]))
    buf = b""
    os.write(master, (answer + "\n").encode())
# Drena a saída até o fim: com o pty cheio o launcher travaria no write.
end = time.time() + 30
while proc.poll() is None and time.time() < end:
    r, _, _ = select.select([master], [], [], 0.2)
    if r:
        try:
            os.read(master, 65536)
        except OSError:
            break
if proc.poll() is None:
    proc.kill()
    sys.exit("launcher não terminou depois da escolha")
PY
}

run_menu_pty "Escolha [1-38/0]" "7" "Escolha [1-4/0]" "1"
assert_mercury_env
ok "menu 7 → painel → 1 (Claude + Mercury 3)"

run_menu_pty "Escolha [1-38/0]" "mercury" "Escolha [1-4/0]" "1"
assert_mercury_env
ok "alias 'mercury' no prompt do menu"

echo "── 10. posição: Mercury é o 7, logo abaixo do LongCat (grupo CLAUDE CODE)"
grep -A1 -E '^menu_row +6 +"\$C_LONGCAT"' "${ROOT}/ai" | grep -Eq '^menu_row +7 +"\$C_MERCURY"' ||
    fail "a linha logo abaixo do LongCat não é o Mercury (menu 7)"
grep -q '    7|mercury|merc|inception)' "${ROOT}/ai" || fail "dispatch do 7 não é o Mercury"
ok "menu 7 = Mercury, abaixo do LongCat"

echo "PASS: mercury-dispatch (ponte, token local, restart, effort, --via, stop, porta, menu 7)"
