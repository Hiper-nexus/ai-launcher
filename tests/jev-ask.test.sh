#!/usr/bin/env bash

# ai ask / ai jev — roteamento por linguagem natural via Jev (TypeSafe).
#
# O que este teste trava:
#   1. `ai ask "<frase>"` consulta o Jev e relança o launcher no alias escolhido
#   2. confiança abaixo do threshold NÃO lança (cai no aviso), com --force lança
#   3. resposta "nenhum" NÃO lança
#   4. sem key, o comando nem tenta (e o fallback implícito fica desligado)
#   5. o fallback implícito (`ai <frase-solta>`) roteia igual ao `ai ask`
#   6. a req bate no endpoint/body certos (model, questions.destino, criteria)
#
# O Jev é substituído por um servidor HTTP local: nada sai para a rede, e o
# caminho de código exercitado (urllib → parse → dispatch) é o real.

set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
MOCK_PID=""
cleanup() {
    [[ -n "$MOCK_PID" ]] && kill "$MOCK_PID" 2>/dev/null || true
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

# Resolve o bash 4+ ANTES de restringir o PATH: o launcher exige bash 4+ e o
# /bin/bash do macOS é 3.2. Sem isso o teste morre no guard de versão do script.
BASH_BIN="$(command -v bash)"
[[ -n "$BASH_BIN" ]] || { echo "FAIL: bash não encontrado" >&2; exit 1; }

TEST_HOME="${TMP_DIR}/home"
FAKE_BIN="${TMP_DIR}/bin"
CAPTURE="${TMP_DIR}/claude-env"
REQ_BODY="${TMP_DIR}/req-body"
mkdir -p "$TEST_HOME" "$FAKE_BIN" "${TEST_HOME}/.local/share/ai-launcher"

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "  ok: $*"; }

# ── Servidor Jev falso ───────────────────────────────────
# Sobe em porta efêmera, grava a porta num arquivo e responde os POSTs na
# ordem da lista de respostas dada (a última se repete). Cada item é
# "<status>:<json>". Guarda o corpo do PRIMEIRO request recebido.
start_jev_mock() {
    local resp_json="$1"
    # Sem isto o arquivo de porta fica com o valor do mock anterior (servidor
    # já morto) e o launcher tenta conectar na porta errada.
    rm -f "${TMP_DIR}/port"
    printf '%s' "$resp_json" > "${TMP_DIR}/resp.json"
    cat > "${TMP_DIR}/mock.py" <<'PY'
import http.server, json, os, sys

ESPEC = os.environ["MOCK_RESP"]     # JSON: [[status, {"corpo":...}], ...]
BODY  = os.environ["MOCK_BODY"]
SEQ   = json.load(open(ESPEC))
if isinstance(SEQ, dict):        # forma curta: um único 200 com esse corpo
    SEQ = [[200, SEQ]]

class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        i = min(self.server.n, len(SEQ) - 1)
        status, payload = SEQ[i]
        self.server.n += 1
        n = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(n)
        if i == 0:   # guarda só o primeiro request (o retry repete o mesmo body)
            with open(BODY, "wb") as f:
                f.write(raw)
                f.write(b"\n--PATH--\n" + self.path.encode())
                f.write(b"\n--AUTH--\n" + (self.headers.get("Authorization") or "").encode())
        data = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)
    def log_message(self, *a):  # silencia o stderr do http.server
        pass

srv = http.server.HTTPServer(("127.0.0.1", 0), H)
srv.n = 0
with open(os.environ["MOCK_PORT"], "w") as f:
    f.write(str(srv.server_port))
# atende o que vier até o processo ser morto (o retry manda N requisições)
srv.serve_forever()
PY
    MOCK_RESP="${TMP_DIR}/resp.json" MOCK_BODY="$REQ_BODY" \
    MOCK_PORT="${TMP_DIR}/port" \
        python3 "${TMP_DIR}/mock.py" &
    MOCK_PID=$!
    # espera a porta aparecer (até ~5s)
    local i
    for i in $(seq 1 50); do
        [[ -s "${TMP_DIR}/port" ]] && return 0
        sleep 0.1
    done
    fail "servidor de mock não subiu"
}

stop_jev_mock() {
    [[ -n "$MOCK_PID" ]] && kill "$MOCK_PID" 2>/dev/null || true
    wait "$MOCK_PID" 2>/dev/null || true
    MOCK_PID=""
}

# ── Binário claude falso ─────────────────────────────────
cat > "${FAKE_BIN}/claude" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
: "${CAPTURE_ENV:?}"
{
    printf 'ARGV=%s\n' "$*"
    printf 'ANTHROPIC_BASE_URL=%s\n' "${ANTHROPIC_BASE_URL:-}"
    printf 'ANTHROPIC_MODEL=%s\n'    "${ANTHROPIC_MODEL:-}"
} > "$CAPTURE_ENV"
SH
chmod +x "${FAKE_BIN}/claude"

# Key do provider de destino (deepseek) + key do TypeSafe.
printf 'deepseek=chave-de-teste\ntypesafe=ts-de-teste\n' \
    > "${TEST_HOME}/.local/share/ai-launcher/providers.conf"
chmod 600 "${TEST_HOME}/.local/share/ai-launcher/providers.conf"

run_ai() {
    # HOME isolado, PATH com o fake, e o host do Jev apontando pro mock.
    # AI_JEV_* são as envs que o launcher lê (ver jev_route).
    # O dir do bash 4+ entra no PATH porque o re-exec do launcher (`ai ask`
    # relança a si mesmo com o alias resolvido) depende do shebang
    # `#!/usr/bin/env bash` achar um bash moderno.
    env -i \
        HOME="$TEST_HOME" \
        PATH="${FAKE_BIN}:$(dirname "$BASH_BIN"):/usr/bin:/bin:/usr/sbin:/sbin" \
        TERM="${TERM:-xterm}" \
        CAPTURE_ENV="$CAPTURE" \
        AI_JEV_HOST="http://127.0.0.1:$(cat "${TMP_DIR}/port")" \
        "${@}" 2>&1
}

# ══════════════════════════════════════════════════════════
echo "── 1. ai ask roteia e lança o provider escolhido"
rm -f "$CAPTURE" "$REQ_BODY"
start_jev_mock '{"model":"jev-1.13.0","usage":{"input_tokens":42,"output_tokens":0},
  "answers":{"destino":{"type":"choice","choice":"deepseek","confidence":0.91,
  "probabilities":{"deepseek":0.91,"claude":0.06,"glm":0.03}}}}'

out=$(run_ai "$BASH_BIN" "$ROOT/ai" ask "refatorar um repo grande sem gastar muito") || true
stop_jev_mock

echo "$out" | grep -q "Jev →" || fail "não imprimiu a linha de decisão. Saída: $out"
echo "$out" | grep -q "deepseek" || fail "não escolheu deepseek. Saída: $out"
[[ -f "$CAPTURE" ]] || fail "o claude falso não foi executado (roteou mas não lançou)"
grep -q "ANTHROPIC_MODEL=deepseek-flash" "$CAPTURE" \
    || fail "não lançou no modelo do deepseek. Capture: $(cat "$CAPTURE")"
ok "roteou para deepseek e lançou com o modelo certo"

# ── a requisição foi montada corretamente?
[[ -f "$REQ_BODY" ]] || fail "o mock não recebeu requisição"
python3 - "$REQ_BODY" <<'PY' || exit 1
import json, sys
raw = open(sys.argv[1], "rb").read().decode("utf-8", "replace")
body, path, auth = raw.split("\n--PATH--\n")[0], None, None
parts = raw.split("\n--PATH--\n")
if len(parts) == 2:
    path, auth = parts[1].split("\n--AUTH--\n")
d = json.loads(body)
assert d["model"] == "jev-latest", f'model errado: {d["model"]}'
q = d["questions"]["destino"]
assert q["type"] == "choice", "tipo deveria ser choice"
assert "nenhum" in q["criteria"], "criteria sem a opção de não-correspondência"
assert "deepseek" in q["criteria"], "criteria sem deepseek"
assert d["state"]["pedido_do_usuario"].startswith("refatorar"), "frase não foi no state"
assert path == "/v1/systemone", f"path errado: {path}"
assert auth.startswith("Bearer ts-de-teste"), f"auth errado: {auth}"
PY
ok "body/path/auth corretos (model, choice, criteria, state, Bearer)"

echo
echo "── 2. confiança baixa não lança; --force lança"
rm -f "$CAPTURE" "$REQ_BODY"
start_jev_mock '{"model":"jev-1.13.0","usage":{},"answers":{"destino":
  {"type":"choice","choice":"qwen","confidence":0.30,
  "probabilities":{"qwen":0.30,"deepseek":0.25,"claude":0.20}}}}'
out=$(run_ai "$BASH_BIN" "$ROOT/ai" ask "hmm algo com qwen talvez") || true
stop_jev_mock
echo "$out" | grep -q "incerto" || fail "deveria avisar incerteza. Saída: $out"
[[ ! -f "$CAPTURE" ]] || fail "não deveria lançar com confiança baixa"
ok "confiança 0.30 < 0.55 → avisou e não lançou"

rm -f "$CAPTURE" "$REQ_BODY"
start_jev_mock '{"model":"jev-1.13.0","usage":{},"answers":{"destino":
  {"type":"choice","choice":"deepseek","confidence":0.30,
  "probabilities":{"deepseek":0.30,"qwen":0.25}}}}'
out=$(run_ai "$BASH_BIN" "$ROOT/ai" ask --force "hmm algo com deepseek talvez") || true
stop_jev_mock
[[ -f "$CAPTURE" ]] || fail "--force deveria lançar mesmo com confiança baixa. Saída: $out"
grep -q "ANTHROPIC_MODEL=deepseek-flash" "$CAPTURE" \
    || fail "--force não lançou no provider roteado. Capture: $(cat "$CAPTURE")"
ok "--force ignorou o threshold e lançou"

echo
echo "── 3. resposta 'nenhum' não lança"
rm -f "$CAPTURE" "$REQ_BODY"
start_jev_mock '{"model":"jev-1.13.0","usage":{},"answers":{"destino":
  {"type":"choice","choice":"nenhum","confidence":0.95,
  "probabilities":{"nenhum":0.95,"claude":0.05}}}}'
out=$(run_ai "$BASH_BIN" "$ROOT/ai" ask "bom dia, tudo bem?") || true
stop_jev_mock
echo "$out" | grep -q "destino claro" || fail "deveria avisar que não veio destino. Saída: $out"
[[ ! -f "$CAPTURE" ]] || fail "não deveria lançar com 'nenhum'"
ok "'nenhum' → avisou e não lançou"

echo
echo "── 4. sem key do TypeSafe: não tenta, e o fallback implícito fica off"
mv "${TEST_HOME}/.local/share/ai-launcher/providers.conf" "${TMP_DIR}/pc.bak"
printf 'deepseek=chave-de-teste\n' \
    > "${TEST_HOME}/.local/share/ai-launcher/providers.conf"
out=$(run_ai "$BASH_BIN" "$ROOT/ai" ask "qualquer coisa") || true
echo "$out" | grep -qi "nenhuma API key do TypeSafe" \
    || fail "deveria reclamar da key ausente. Saída: $out"
out=$(run_ai "$BASH_BIN" "$ROOT/ai" frasesoltaqualquer) || true
echo "$out" | grep -q "Opção desconhecida" \
    || fail "sem key, frase solta deveria cair no erro de sempre. Saída: $out"
mv "${TMP_DIR}/pc.bak" "${TEST_HOME}/.local/share/ai-launcher/providers.conf"
ok "sem key: mensagem clara e fallback implícito desligado"

echo
echo "── 5. fallback implícito: ai <frase> roteia igual ao ask"
rm -f "$CAPTURE" "$REQ_BODY"
start_jev_mock '{"model":"jev-1.13.0","usage":{},"answers":{"destino":
  {"type":"choice","choice":"deepseek","confidence":0.88,
  "probabilities":{"deepseek":0.88,"claude":0.07}}}}'
out=$(run_ai "$BASH_BIN" "$ROOT/ai" "preciso revisar um PR grande e barato") || true
stop_jev_mock
[[ -f "$CAPTURE" ]] || fail "fallback implícito não lançou. Saída: $out"
grep -q "ANTHROPIC_MODEL=deepseek-flash" "$CAPTURE" \
    || fail "fallback não caiu no deepseek. Capture: $(cat "$CAPTURE")"
ok "frase solta roteou e lançou"

echo
echo "── 6. typo que parece flag NÃO vira chamada de rede"
out=$(run_ai "$BASH_BIN" "$ROOT/ai" --nao-existe) || true
echo "$out" | grep -q "Opção desconhecida" \
    || fail "flag desconhecida deveria manter o erro antigo. Saída: $out"
ok "flag desconhecida mantém o comportamento antigo"

echo
echo "── 7. retry com backoff em 529/503 (a doc manda retentar)"
# 529 duas vezes e depois 200: tem que sobreviver e rotear.
rm -f "$CAPTURE" "$REQ_BODY"
start_jev_mock '[[529,{"detail":{"error_type":"system_overloaded"}}],
                 [529,{"detail":{"error_type":"system_overloaded"}}],
                 [200,{"model":"jev-1.13.0","usage":{},"answers":{"destino":
                   {"type":"choice","choice":"deepseek","confidence":0.90,
                    "probabilities":{"deepseek":0.90}}}}]]'
out=$(run_ai "$BASH_BIN" "$ROOT/ai" ask "refatorar muita coisa") || true
stop_jev_mock
[[ -f "$CAPTURE" ]] || fail "deveria ter sobrevivido aos 529 e lançado. Saída: $out"
ok "529, 529, 200 → roteou e lançou"

# 529 em todas: desiste com mensagem clara e NÃO lança nada.
rm -f "$CAPTURE" "$REQ_BODY"
start_jev_mock '[[529,{"detail":{"error_type":"system_overloaded"}}]]'
out=$(run_ai "$BASH_BIN" "$ROOT/ai" ask "refatorar muita coisa") || true
stop_jev_mock
echo "$out" | grep -q "indisponível" || fail "deveria avisar indisponibilidade. Saída: $out"
[[ ! -f "$CAPTURE" ]] || fail "não deveria lançar quando o Jev está fora"
ok "529 persistente → avisou e não lançou"

echo
echo "PASS: jev-ask (7/7)"
