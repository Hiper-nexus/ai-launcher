#!/usr/bin/env bash

# Servidor MCP do Jev (mcp/jev-server.py).
#
# O que este teste trava:
#   1. handshake `initialize` devolve protocolVersion e serverInfo
#   2. `tools/list` expõe UMA tool (o custo de contexto por CLI depende disso —
#      se alguém acrescentar tools sem pensar, o teste avisa)
#   3. `tools/call` roteia de verdade e devolve a decisão formatada
#   4. 'nenhum' vem com a instrução de NÃO escolher sozinho
#   5. sem key → erro claro, não crash
#   6. pedido vazio → erro de argumento
#   7. método desconhecido → -32601, servidor sobrevive
#   8. linha inválida no stream não derruba o servidor
#   9. o criteria é lido do `ai` instalado (fonte única, sem duplicação)
#  10. launcher inexistente → erro explícito, não roteamento errado
#
# O Jev é substituído por um servidor HTTP local: nada sai para a rede.

set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
MOCK_PID=""
cleanup() {
    [[ -n "$MOCK_PID" ]] && kill "$MOCK_PID" 2>/dev/null || true
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

PY_BIN="$(command -v python3)"
[[ -n "$PY_BIN" ]] || { echo "FAIL: python3 não encontrado" >&2; exit 1; }

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "  ok: $*"; }

# ── Servidor Jev falso (mesma ideia dos outros testes) ───
start_jev_mock() {
    rm -f "${TMP_DIR}/port"
    printf '%s' "$1" > "${TMP_DIR}/resp.json"
    cat > "${TMP_DIR}/mock.py" <<'PY'
import http.server, json, os
RESP = open(os.environ["MOCK_RESP"], "rb").read()
class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        self.rfile.read(int(self.headers.get("Content-Length") or 0))
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(RESP)))
        self.end_headers()
        self.wfile.write(RESP)
    def log_message(self, *a): pass
srv = http.server.HTTPServer(("127.0.0.1", 0), H)
with open(os.environ["MOCK_PORT"], "w") as f:
    f.write(str(srv.server_port))
srv.serve_forever()
PY
    MOCK_RESP="${TMP_DIR}/resp.json" MOCK_PORT="${TMP_DIR}/port" \
        python3 "${TMP_DIR}/mock.py" &
    MOCK_PID=$!
    local i
    for i in $(seq 1 50); do
        [[ -s "${TMP_DIR}/port" ]] && return 0
        sleep 0.1
    done
    fail "mock não subiu"
}
stop_jev_mock() {
    [[ -n "$MOCK_PID" ]] && kill "$MOCK_PID" 2>/dev/null || true
    wait "$MOCK_PID" 2>/dev/null || true
    MOCK_PID=""
}

# mcp <json-lines...> — sobe o servidor, manda as mensagens, devolve o stdout.
# AI_LAUNCHER_PATH aponta para o `ai` do repo (o criteria sai de lá).
mcp() {
    local host="${1:-}"; shift
    env -i \
        PATH="/usr/bin:/bin" \
        TYPESAFE_API_KEY="${MCP_KEY-ts-de-teste}" \
        AI_JEV_HOST="$host" \
        AI_LAUNCHER_PATH="${MCP_LAUNCHER:-$ROOT/ai}" \
        "$PY_BIN" "$ROOT/mcp/jev-server.py" 2>&1
}

# Extrai o campo .result.content[0].text da N-ésima resposta do servidor.
campo() {
    python3 -c '
import json, sys
alvo = int(sys.argv[1]); campo = sys.argv[2]
for linha in sys.stdin:
    linha = linha.strip()
    if not linha or not linha.startswith("{"):
        continue
    try: d = json.loads(linha)
    except Exception: continue
    if d.get("id") != alvo: continue
    if campo == "erro":
        print((d.get("error") or {}).get("message", "")); break
    txt = ((d.get("result") or {}).get("content") or [{}])[0].get("text", "")
    print(txt); break
' "$1" "$2"
}

# ══════════════════════════════════════════════════════════
echo "── 1. handshake initialize"
saida=$(printf '%s\n' \
    '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' | mcp)
echo "$saida" | python3 -c '
import json,sys
d = [json.loads(l) for l in sys.stdin if l.strip().startswith("{")][0]
r = d["result"]
assert r["protocolVersion"] == "2024-11-05", r
assert r["serverInfo"]["name"] == "jev", r
assert "tools" in r["capabilities"], r
' || fail "handshake errado. Saída: $saida"
ok "initialize devolve protocolVersion, serverInfo e capabilities"

echo
echo "── 2. tools/list expõe exatamente UMA tool"
saida=$(printf '%s\n' \
    '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' | mcp)
n=$(echo "$saida" | python3 -c '
import json,sys
d=[json.loads(l) for l in sys.stdin if l.strip().startswith("{")][0]
t=d["result"]["tools"]
assert all("inputSchema" in x for x in t), "tool sem inputSchema"
assert all(x.get("description") for x in t), "tool sem description"
print(len(t))
')
[[ "$n" == "1" ]] || fail "esperava 1 tool (custo de contexto!), veio '$n'. Saída: $saida"
ok "1 tool só (com description e inputSchema) — custo mínimo por CLI"

echo
echo "── 3. tools/call roteia e formata a decisão"
start_jev_mock '{"model":"jev-1.13.0","usage":{"input_tokens":40,"output_tokens":0},
  "answers":{"destino":{"type":"choice","choice":"sol","confidence":0.91,
  "probabilities":{"sol":0.91,"codex":0.06,"claude":0.03}}}}'
HOST="http://127.0.0.1:$(cat "${TMP_DIR}/port")"
saida=$(printf '%s\n' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"jev_route","arguments":{"pedido":"codex com 1M pra varrer tudo"}}}' \
    | mcp "$HOST")
stop_jev_mock
txt=$(printf '%s\n' "$saida" | campo 2 text)
echo "$txt" | grep -q "sol" || fail "não trouxe a opção. Texto: $txt"
echo "$txt" | grep -q "91%" || fail "não formatou a confiança. Texto: $txt"
echo "$txt" | grep -q "codex" || fail "não trouxe a distribuição. Texto: $txt"
ok "roteou, formatou opção + confiança + distribuição"

echo
echo "── 4. 'nenhum' instrui a NÃO escolher sozinho"
start_jev_mock '{"model":"jev-1.13.0","usage":{},
  "answers":{"destino":{"type":"choice","choice":"nenhum","confidence":0.98,
  "probabilities":{"nenhum":0.98}}}}'
HOST="http://127.0.0.1:$(cat "${TMP_DIR}/port")"
saida=$(printf '%s\n' \
    '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"jev_route","arguments":{"pedido":"bom dia"}}}' \
    | mcp "$HOST")
stop_jev_mock
txt=$(printf '%s\n' "$saida" | campo 3 text)
echo "$txt" | grep -qi "pergunte ao usuário" \
    || fail "'nenhum' deveria instruir a perguntar em vez de assumir. Texto: $txt"
ok "'nenhum' vem com a instrução de não decidir pelo usuário"

echo
echo "── 5. sem key → erro claro (não crash)"
# HOME falso + AI_PROVIDERS_FILE apontando para lugar nenhum: nem env nem arquivo.
saida=$(printf '%s\n' \
    '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"jev_route","arguments":{"pedido":"x"}}}' \
    | env -i PATH="/usr/bin:/bin" HOME="${TMP_DIR}/vazio" \
        AI_PROVIDERS_FILE="${TMP_DIR}/nao-existe.conf" \
        AI_LAUNCHER_PATH="$ROOT/ai" "$PY_BIN" "$ROOT/mcp/jev-server.py" 2>&1)
erro=$(printf '%s\n' "$saida" | campo 4 erro)
echo "$erro" | grep -qi "ai jev key" \
    || fail "deveria dizer como resolver. Erro: $erro"
ok "sem key: mensagem explícita com o comando que resolve"

echo
echo "── 5b. key lida do providers.conf (sem key no config da CLI)"
# É o que permite configurar 5 CLIs sem gravar a key em 5 arquivos.
printf 'glm=x\ntypesafe=ts-do-arquivo\n' > "${TMP_DIR}/providers.conf"
chmod 600 "${TMP_DIR}/providers.conf"
# servidor fake que devolve o Authorization recebido, para provar de onde veio
cat > "${TMP_DIR}/auth.py" <<'PY'
import http.server, json, os
class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        self.rfile.read(int(self.headers.get("Content-Length") or 0))
        auth = self.headers.get("Authorization") or ""
        body = json.dumps({"answers": {"destino": {
            "type": "choice", "choice": auth, "confidence": 0.9}}}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, *a): pass
srv = http.server.HTTPServer(("127.0.0.1", 0), H)
with open(os.environ["MOCK_PORT"], "w") as f: f.write(str(srv.server_port))
srv.serve_forever()
PY
rm -f "${TMP_DIR}/port"
MOCK_PORT="${TMP_DIR}/port" python3 "${TMP_DIR}/auth.py" &
MOCK_PID=$!
for _ in $(seq 1 50); do [[ -s "${TMP_DIR}/port" ]] && break; sleep 0.1; done
saida=$(printf '%s\n' \
    '{"jsonrpc":"2.0","id":10,"method":"tools/call","params":{"name":"jev_route","arguments":{"pedido":"x"}}}' \
    | env -i PATH="/usr/bin:/bin" HOME="${TMP_DIR}/vazio" \
        AI_PROVIDERS_FILE="${TMP_DIR}/providers.conf" \
        AI_JEV_HOST="http://127.0.0.1:$(cat "${TMP_DIR}/port")" \
        AI_LAUNCHER_PATH="$ROOT/ai" "$PY_BIN" "$ROOT/mcp/jev-server.py" 2>&1)
stop_jev_mock
txt=$(printf '%s\n' "$saida" | campo 10 text)
echo "$txt" | grep -q "Bearer ts-do-arquivo" \
    || fail "não leu a key do providers.conf. Texto: $txt"
ok "key sai do providers.conf — nenhuma CLI precisa dela no config"

echo
echo "── 6. pedido vazio → erro de argumento"
saida=$(printf '%s\n' \
    '{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"jev_route","arguments":{"pedido":"   "}}}' \
    | mcp)
erro=$(printf '%s\n' "$saida" | campo 5 erro)
echo "$erro" | grep -qi "pedido" || fail "deveria reclamar do pedido vazio. Erro: $erro"
ok "pedido vazio: -32602 com mensagem"

echo
echo "── 7. método desconhecido e linha inválida não derrubam o servidor"
saida=$(printf '%s\n' \
    '{"jsonrpc":"2.0","id":6,"method":"nao/existe"}' \
    'isto nao e json' \
    '{"jsonrpc":"2.0","id":7,"method":"tools/list"}' | mcp)
erro=$(printf '%s\n' "$saida" | campo 6 erro)
echo "$erro" | grep -q "não suportado" || fail "método desconhecido: erro errado: $erro"
# a prova de sobrevivência: a mensagem SEGUINTE ainda é respondida
printf '%s\n' "$saida" | python3 -c '
import json,sys
ids=[json.loads(l)["id"] for l in sys.stdin if l.strip().startswith("{")]
assert 7 in ids, f"servidor morreu no lixo: ids={ids}"
' || fail "o servidor não respondeu depois de uma linha inválida"
ok "lixo no stream não derruba; o servidor continua respondendo"

echo
echo "── 8. criteria vem do launcher ai (fonte única, sem cópia no servidor)"
# Se o servidor tivesse uma cópia própria do criteria, este teste passaria
# mesmo assim — então ele checa o CONTRÁRIO: um launcher sem o bloco de
# criteria tem que dar erro explícito, e não rotear com lista vazia.
mkdir -p "${TMP_DIR}/fake"
printf '#!/usr/bin/env bash\necho oi\n' > "${TMP_DIR}/fake/ai"
chmod +x "${TMP_DIR}/fake/ai"
start_jev_mock '{"answers":{"destino":{"choice":"claude","confidence":0.9}}}'
HOST="http://127.0.0.1:$(cat "${TMP_DIR}/port")"
saida=$(printf '%s\n' \
    '{"jsonrpc":"2.0","id":8,"method":"tools/call","params":{"name":"jev_route","arguments":{"pedido":"x"}}}' \
    | MCP_LAUNCHER="${TMP_DIR}/fake/ai" mcp "$HOST")
stop_jev_mock
txt=$(printf '%s\n' "$saida" | campo 8 text)
echo "$txt" | grep -q "JEV_ROUTE_CRITERIA" \
    || fail "launcher sem criteria deveria falhar alto. Texto: $txt"
ok "launcher sem o bloco de criteria → erro explícito (não roteia vazio)"

echo
echo "── 9. launcher inexistente → erro explícito"
saida=$(printf '%s\n' \
    '{"jsonrpc":"2.0","id":9,"method":"tools/call","params":{"name":"jev_route","arguments":{"pedido":"x"}}}' \
    | MCP_LAUNCHER="/nao/existe/ai" mcp "http://127.0.0.1:1")
txt=$(printf '%s\n' "$saida" | campo 9 text)
echo "$txt" | grep -qi "não consegui ler o launcher" \
    || fail "deveria apontar o launcher ausente. Texto: $txt"
echo "$txt" | grep -q "AI_LAUNCHER_PATH" \
    || fail "deveria dizer como corrigir. Texto: $txt"
ok "launcher ausente: erro explícito com a variável que resolve"

echo
echo "PASS: jev-mcp-server (10/10)"
