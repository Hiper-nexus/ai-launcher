#!/usr/bin/env bash

# ai hy4: Claude Code roteado pelo Token Plan internacional da Tencent.
#
# Os pontos delicados, todos testados direto contra a API em 04/11/2026:
#   - key sk-tp-... só vale no caminho /plan da região internacional. Na
#     TokenHub comum (/v1/messages) e no host da China ela volta 401;
#   - o sufixo [1m] é REJEITADO no wire (403), mas o Claude Code faz o strip
#     antes de chamar. Ele só existe para o client enxergar a janela de 1M;
#   - /v1/models e count_tokens dão 404 em /plan, então o ping tem que ser uma
#     chamada real em /v1/messages;
#   - a API aceita max_tokens acima do teto documentado (64000), logo o valor
#     aqui vem da doc, não do que o servidor deixa passar;
#   - o input máximo é 960000, menor que a janela: o auto-compact tem que
#     disparar antes disso.
# Este teste trava base_url, slots, compact, output, ping, key e o menu 8.

set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
MOCK_PID=""
cleanup() {
    [[ -n "$MOCK_PID" ]] && kill "$MOCK_PID" 2>/dev/null || true
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

# Um export no perfil do desenvolvedor não pode mudar o que o teste enxerga.
unset AI_HY4_MODEL AI_HY4_BASE_URL

TEST_HOME="${TMP_DIR}/home"
FAKE_BIN="${TMP_DIR}/bin"
CAPTURE_ENV="${TMP_DIR}/claude-env"
PROVIDERS="${TEST_HOME}/.local/share/ai-launcher/providers.conf"
TEST_KEY="sk-tp-chave-de-teste"
mkdir -p "$TEST_HOME" "$FAKE_BIN" "${TEST_HOME}/.local/share/ai-launcher"

# Key falsa: sem ela o provider_setup_env para e pede a key no terminal.
printf 'hy4=%s\n' "$TEST_KEY" > "$PROVIDERS"
chmod 600 "$PROVIDERS"

cat > "${FAKE_BIN}/claude" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
: "${CAPTURE_ENV:?}"
{
    printf 'ANTHROPIC_BASE_URL=%s\n'               "${ANTHROPIC_BASE_URL:-}"
    printf 'ANTHROPIC_MODEL=%s\n'                  "${ANTHROPIC_MODEL:-}"
    printf 'ANTHROPIC_DEFAULT_HAIKU_MODEL=%s\n'    "${ANTHROPIC_DEFAULT_HAIKU_MODEL:-}"
    printf 'ANTHROPIC_DEFAULT_SONNET_MODEL=%s\n'   "${ANTHROPIC_DEFAULT_SONNET_MODEL:-}"
    printf 'ANTHROPIC_DEFAULT_OPUS_MODEL=%s\n'     "${ANTHROPIC_DEFAULT_OPUS_MODEL:-}"
    printf 'ANTHROPIC_DEFAULT_FABLE_MODEL=%s\n'    "${ANTHROPIC_DEFAULT_FABLE_MODEL:-}"
    printf 'CLAUDE_CODE_SUBAGENT_MODEL=%s\n'       "${CLAUDE_CODE_SUBAGENT_MODEL:-}"
    printf 'CLAUDE_CODE_AUTO_COMPACT_WINDOW=%s\n'  "${CLAUDE_CODE_AUTO_COMPACT_WINDOW:-}"
    printf 'CLAUDE_CODE_MAX_OUTPUT_TOKENS=%s\n'    "${CLAUDE_CODE_MAX_OUTPUT_TOKENS:-}"
    printf 'CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=%s\n' "${CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC:-}"
    printf 'ENABLE_TOOL_SEARCH=%s\n'               "${ENABLE_TOOL_SEARCH:-}"
    printf 'ANTHROPIC_AUTH_TOKEN=%s\n'             "${ANTHROPIC_AUTH_TOKEN:-}"
    printf 'ANTHROPIC_API_KEY=%s\n'                "${ANTHROPIC_API_KEY:-}"
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
        "$ROOT/ai" "$@" >/dev/null </dev/null
    )
}

env_is() {
    local key="$1" expected="$2" got
    got=$(grep "^${key}=" "$CAPTURE_ENV" | cut -d= -f2-)
    [[ "$got" == "$expected" ]] ||
        fail "${key}: esperado '${expected}', obtido '${got}'"
}

# Tudo que o destino Hy4 precisa ter, seja pela CLI ou pelo menu.
assert_hy4() {
    env_is ANTHROPIC_BASE_URL "https://tokenhub-intl.tencentcloudmaas.com/plan/anthropic"
    env_is ANTHROPIC_MODEL                "hy4[1m]"
    env_is ANTHROPIC_DEFAULT_SONNET_MODEL "hy4[1m]"
    env_is ANTHROPIC_DEFAULT_OPUS_MODEL   "hy4[1m]"
    env_is ANTHROPIC_DEFAULT_HAIKU_MODEL  "hy4[1m]"
    env_is ANTHROPIC_DEFAULT_FABLE_MODEL  "hy4[1m]"
    env_is CLAUDE_CODE_SUBAGENT_MODEL     "hy4[1m]"
    # Input máximo da doc: compactar em 1M estouraria o limite da API.
    env_is CLAUDE_CODE_AUTO_COMPACT_WINDOW "960000"
    env_is CLAUDE_CODE_MAX_OUTPUT_TOKENS  "64000"
    env_is CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC "1"
    # A doc da Tencent pede false, mas isso custa ~5x mais input: cada pedido
    # levaria todas as ferramentas em vez de carregá-las sob demanda.
    env_is ENABLE_TOOL_SEARCH ""
    env_is ANTHROPIC_AUTH_TOKEN "$TEST_KEY"
    env_is ANTHROPIC_API_KEY    ""
}

echo "── 1. aliases da CLI levam ao Hy4"
for alias_cmd in hy4 hy hunyuan tencent; do
    # Um ANTHROPIC_API_KEY herdado do shell não pode sobrar na sessão.
    ( export ANTHROPIC_API_KEY="sk-ant-herdada"; run_launcher "$alias_cmd" )
    assert_hy4
done
ok "hy4 / hy / hunyuan / tencent"

echo "── 2. prompt passa adiante e a key não vai por argv"
run_launcher hy4 "explique este repo"
grep -q '^ARGS=.*explique este repo' "$CAPTURE_ENV" ||
    fail "prompt não chegou ao claude: $(grep '^ARGS=' "$CAPTURE_ENV")"
grep '^ARGS=' "$CAPTURE_ENV" | grep -q "$TEST_KEY" && fail "key vazou para o argv do claude"
ok "prompt one-shot, key fora do argv"

echo "── 3. overrides por env var"
( export AI_HY4_MODEL="hy4-preview"; run_launcher hy4 )
env_is ANTHROPIC_MODEL "hy4-preview"
env_is CLAUDE_CODE_SUBAGENT_MODEL "hy4-preview"
ok "AI_HY4_MODEL"

( export AI_HY4_BASE_URL="https://tokenhub-intl.tencentcloudmaas.com"; run_launcher hy4 )
env_is ANTHROPIC_BASE_URL "https://tokenhub-intl.tencentcloudmaas.com"
ok "AI_HY4_BASE_URL (key de TokenHub pay-as-you-go usa outro caminho)"

echo "── 4. ai hy4 key: salva por stdin ou argumento, sem aceitar vazio"
key_home="${TMP_DIR}/key-home"
key_file="${key_home}/.local/share/ai-launcher/providers.conf"
mkdir -p "$(dirname "$key_file")"

# stdin é o caminho que não expõe a key no ps ('pbpaste | ai hy4 key').
out=$(printf 'sk-tp-via-stdin\n' | HOME="$key_home" PATH="${FAKE_BIN}:$PATH" "$ROOT/ai" hy4 key 2>&1)
grep -qx 'hy4=sk-tp-via-stdin' "$key_file" || fail "key por stdin não foi salva: $(cat "$key_file")"
[[ "$out" != *"sk-tp-via-stdin"* ]] || fail "a key apareceu na saída do comando"
perms=$(stat -c '%a' "$key_file" 2>/dev/null || stat -f '%Lp' "$key_file")
[[ "$perms" == "600" ]] || fail "providers.conf com permissão ${perms}, esperado 600"

HOME="$key_home" PATH="${FAKE_BIN}:$PATH" "$ROOT/ai" hy4 key sk-tp-via-arg >/dev/null 2>&1
grep -qx 'hy4=sk-tp-via-arg' "$key_file" || fail "key por argumento não foi salva"

if empty_key_out=$(HOME="$key_home" PATH="${FAKE_BIN}:$PATH" "$ROOT/ai" hy4 key 2>&1 </dev/null); then
    fail "key vazia deveria falhar"
fi
[[ "$empty_key_out" == *"key vazia"* ]] || fail "erro errado para key vazia: ${empty_key_out}"
grep -qx 'hy4=sk-tp-via-arg' "$key_file" || fail "key vazia apagou a key salva"
ok "stdin, argumento, chmod 600 e rejeição de key vazia"

echo "── 5. ai hy4 ping faz uma chamada real, sem o sufixo [1m] no wire"
MOCK_LOG="${TMP_DIR}/mock.log"
MOCK_PORT_FILE="${TMP_DIR}/mock.port"
python3 - "$MOCK_LOG" "$MOCK_PORT_FILE" "$TEST_KEY" <<'PY' &
import http.server, json, sys

log, port_file, key = sys.argv[1:4]

class Handler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        size = int(self.headers.get("content-length") or 0)
        body = json.loads(self.rfile.read(size) or b"{}")
        auth = self.headers.get("authorization")
        with open(log, "a") as f:
            f.write(json.dumps({"path": self.path, "auth": auth, "model": body.get("model")}) + "\n")
        authorized = auth == "Bearer " + key
        out = {"content": [{"type": "text", "text": "pong"}]} if authorized \
            else {"error": {"message": "API Key does not exist"}}
        data = json.dumps(out).encode()
        self.send_response(200 if authorized else 401)
        self.send_header("content-type", "application/json")
        self.send_header("content-length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, *args):
        pass

server = http.server.HTTPServer(("127.0.0.1", 0), Handler)
with open(port_file, "w") as f:
    f.write(str(server.server_port))
server.serve_forever()
PY
MOCK_PID=$!
for _ in $(seq 1 50); do
    [[ -s "$MOCK_PORT_FILE" ]] && break
    python3 -c 'import time; time.sleep(0.1)'
done
[[ -s "$MOCK_PORT_FILE" ]] || fail "mock não subiu"
MOCK_URL="http://127.0.0.1:$(cat "$MOCK_PORT_FILE")/plan/anthropic"

ping_out=$(HOME="$TEST_HOME" PATH="${FAKE_BIN}:$PATH" AI_HY4_BASE_URL="$MOCK_URL" "$ROOT/ai" hy4 ping 2>&1) ||
    fail "ping falhou contra o mock: ${ping_out}"
[[ "$ping_out" == *"pong"* ]] || fail "ping não mostrou a resposta: ${ping_out}"
[[ "$ping_out" != *"$TEST_KEY"* ]] || fail "a key apareceu na saída do ping"
python3 - "$MOCK_LOG" "$TEST_KEY" <<'PY' || fail "requisição do ping fora do esperado: $(cat "$MOCK_LOG")"
import json, sys
req = json.loads(open(sys.argv[1]).readline())
assert req["path"] == "/plan/anthropic/v1/messages", req
assert req["model"] == "hy4", req
assert req["auth"] == "Bearer " + sys.argv[2], req
PY

bad_home="${TMP_DIR}/bad-home"
mkdir -p "${bad_home}/.local/share/ai-launcher"
printf 'hy4=sk-tp-chave-errada\n' > "${bad_home}/.local/share/ai-launcher/providers.conf"
chmod 600 "${bad_home}/.local/share/ai-launcher/providers.conf"
if bad_out=$(HOME="$bad_home" PATH="${FAKE_BIN}:$PATH" AI_HY4_BASE_URL="$MOCK_URL" "$ROOT/ai" hy4 ping 2>&1); then
    fail "ping com key errada deveria sair com erro: ${bad_out}"
fi
[[ "$bad_out" == *"401"* ]] || fail "ping não relatou o 401: ${bad_out}"
ok "POST /v1/messages, modelo hy4, Bearer, 401 vira erro"

empty_home="${TMP_DIR}/empty-home"
mkdir -p "${empty_home}/.local/share/ai-launcher"
if empty_out=$(HOME="$empty_home" PATH="${FAKE_BIN}:$PATH" "$ROOT/ai" hy4 ping 2>&1 </dev/null); then
    fail "ping sem key deveria falhar: ${empty_out}"
fi
[[ "$empty_out" == *"ai hy4 key"* ]] || fail "ping sem key não orientou: ${empty_out}"
ok "sem key, o ping diz como salvar"

echo "── 6. menu: '8' abre o painel; 'hy4' no prompt também"
# Espera o TEXTO do prompt antes de digitar: resposta que chega antes do read()
# se perde no pty (era o flake do version-cache).
run_menu_pty() {
    : > "$CAPTURE_ENV"
    TEST_HOME="$TEST_HOME" FAKE_BIN="$FAKE_BIN" CAPTURE_ENV="$CAPTURE_ENV" ROOT="$ROOT" \
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
def wait_for(text, timeout=20):
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
try:
    proc.wait(timeout=20)
except subprocess.TimeoutExpired:
    proc.kill()
    sys.exit("launcher não terminou depois da escolha")
PY
}

run_menu_pty "Escolha [1-39/0]" "8" "Escolha [1-3/0]" "1"
assert_hy4
ok "menu 8 → painel → 1 (Claude + Hy4)"

run_menu_pty "Escolha [1-39/0]" "hy4" "Escolha [1-3/0]" "1"
assert_hy4
ok "alias 'hy4' no prompt do menu"

echo "── 7. posição: Hy4 é o 8, logo abaixo do Mercury (grupo CLAUDE CODE)"
grep -A1 -E '^menu_row +7 +"\$C_MERCURY"' "${ROOT}/ai" | grep -Eq '^menu_row +8 +"\$C_HY4"' ||
    fail "a linha logo abaixo do Mercury não é o Hy4 (menu 8)"
grep -q '    8|hy4|hy|hunyuan|tencent)' "${ROOT}/ai" || fail "dispatch do 8 não é o Hy4"
ok "menu 8 = Hy4, abaixo do Mercury"

echo "PASS: hy4-dispatch (CLI, aliases, overrides, key, ping, menu 8)"
