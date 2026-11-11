#!/usr/bin/env bash

# Gemini Decision: servidor MCP (mcp/gemini-decision-server.py) e `ai gd`.
#
# O que este teste trava:
#   servidor
#    1. handshake e exatamente três tools (ui_check, rank, decide), com schema
#       portável: todo objeto declara properties (Gemini/Antigravity recusam
#       objeto livre)
#    2. decide monta o pedido nativo: POST /v1beta/decisions, key no header
#       (lida do providers.conf, nunca de argv), arquivo em base64 com o MIME
#       certo, options→criteria (choice), levels→criteria (score)
#    3. ui_check separa falha / incerto / ok e inclui as checagens padrão
#    4. rank ordena pela nota
#    5. credencial no texto → recusa SEM chamar a API e sem ecoar o segredo
#    6. arquivo de texto (.env) → recusa: só mídia sai como arquivo
#    7. sem key → erro que ensina `ai gd key`, sem chamar a API
#    8. HTTP 400 da API → erro legível para o modelo, servidor vivo
#    9. o registro de uso não guarda conteúdo
#   launcher
#   10. ai gd key grava no slot certo, chmod 600, sem imprimir a key
#   11. ai gd setup registra nas CLIs que existem (e só nelas), sem key nos
#       configs, preservando o resto; o bloco de instruções entra uma vez
#   12. rodar o setup de novo não muda nada
#   13. ai gd ui devolve 1 quando um critério falha
#
# A API do Google é um servidor HTTP local: nada sai para a rede.

set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
MOCK_PID=""
cleanup() {
    [[ -n "$MOCK_PID" ]] && kill "$MOCK_PID" 2>/dev/null || true
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

SERVER="$ROOT/mcp/gemini-decision-server.py"
PY_BIN="$(type -P python3)"
[[ -n "$PY_BIN" ]] || { echo "FAIL: python3 não encontrado" >&2; exit 1; }

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "  ok: $*"; }

KEY="gdk-teste-$$-chave"
H="${TMP_DIR}/home"
mkdir -p "$H/.local/share/ai-launcher"
printf 'typesafe=outra\ngemini-decision=%s\n' "$KEY" > "$H/.local/share/ai-launcher/providers.conf"
chmod 600 "$H/.local/share/ai-launcher/providers.conf"

# PNG de 1x1 e um .env que não pode sair da máquina.
printf '\x89PNG\r\n\x1a\nfakepng' > "${TMP_DIR}/tela.png"
printf 'SEGREDO=1\n' > "${TMP_DIR}/.env"

# ── API falsa ────────────────────────────────────────────
# Grava cada pedido (path, key do header, corpo) e responde conforme o modo:
#   smart: noul = 0.1 se a pergunta contém um termo de MOCK_FAIL, senão 0.95;
#          score = 2.9 para "gráfico", 1.2 para "tabela", 0.2 no resto
#   erro400: devolve o erro de safety da API
start_mock() {
    rm -f "${TMP_DIR}/port"
    cat > "${TMP_DIR}/mock.py" <<'PY'
import http.server, json, os
LOG = os.environ["MOCK_LOG"]
class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        corpo = self.rfile.read(int(self.headers.get("Content-Length") or 0))
        with open(LOG, "a") as f:
            f.write(json.dumps({"path": self.path, "key": self.headers.get("x-goog-api-key"),
                                "body": json.loads(corpo)}) + "\n")
        if os.environ.get("MOCK_MODE") == "erro400":
            out = json.dumps({"error": {"code": 400, "message": "Request blocked due to safety violations"}}).encode()
            self.send_response(400)
        else:
            q = json.loads(corpo)["questions"]
            falhar = [t for t in os.environ.get("MOCK_FAIL", "").split(",") if t]
            ans = {}
            for k, v in q.items():
                txt = v["instructions"]
                if v["type"] == "noul":
                    p = 0.1 if any(t in txt for t in falhar) else 0.95
                    ans[k] = {"type": "noul", "noul": p, "confidence": max(p, 1 - p)}
                elif v["type"] == "score":
                    s = 2.9 if "gráfico" in txt else 1.2 if "tabela" in txt else 0.2
                    n = len(v["criteria"])
                    probs = {str(i): (0.9 if i == round(s) else 0.1 / (n - 1)) for i in range(n)}
                    ans[k] = {"type": "score", "score": s, "probabilities": probs,
                              "legend": {str(i): c for i, c in enumerate(v["criteria"])},
                              "confidence": 0.9}
                else:
                    ops = sorted(v["criteria"])
                    pref = [o for o in os.environ.get("MOCK_CHOICE", "").split(",") if o in ops]
                    esc = pref[0] if pref else ops[0]
                    ans[k] = {"type": "choice", "choice": esc,
                              "probabilities": {o: (0.9 if o == esc else 0.1 / (len(ops) - 1)) for o in ops},
                              "confidence": 0.9}
            out = json.dumps({"answers": ans, "usage": {"total_input_tokens": 321, "total_output_tokens": 0}}).encode()
            self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(out)))
        self.end_headers()
        self.wfile.write(out)
    def log_message(self, *a): pass
srv = http.server.HTTPServer(("127.0.0.1", 0), H)
open(os.environ["MOCK_PORT"], "w").write(str(srv.server_port))
srv.serve_forever()
PY
    MOCK_LOG="${TMP_DIR}/pedidos.jsonl" MOCK_PORT="${TMP_DIR}/port" \
        MOCK_MODE="${MOCK_MODE:-smart}" MOCK_FAIL="${MOCK_FAIL:-}" MOCK_CHOICE="${MOCK_CHOICE:-}" \
        "$PY_BIN" "${TMP_DIR}/mock.py" &
    MOCK_PID=$!
    local i
    for i in $(seq 1 50); do
        [[ -s "${TMP_DIR}/port" ]] && { BASE="http://127.0.0.1:$(cat "${TMP_DIR}/port")"; return 0; }
        sleep 0.1
    done
    fail "mock não subiu"
}
stop_mock() {
    [[ -n "$MOCK_PID" ]] && kill "$MOCK_PID" 2>/dev/null || true
    wait "$MOCK_PID" 2>/dev/null || true
    MOCK_PID=""
}
pedidos() { [[ -f "${TMP_DIR}/pedidos.jsonl" ]] && wc -l < "${TMP_DIR}/pedidos.jsonl" | tr -d ' ' || echo 0; }

# mcp <home> <linhas json...> — sobe o servidor com env limpo, devolve stdout.
mcp() {
    local home="$1"; shift
    printf '%s\n' "$@" | env -i PATH="/usr/bin:/bin" HOME="$home" \
        GEMINI_DECISION_BASE_URL="${BASE:-http://127.0.0.1:9}" \
        GEMINI_DECISION_LOG="${TMP_DIR}/uso.jsonl" \
        "$PY_BIN" "$SERVER" 2>&1
}

# resposta <id> <campo> — campo: texto | erro_tool
resposta() {
    "$PY_BIN" -c '
import json, sys
alvo, campo = int(sys.argv[1]), sys.argv[2]
for l in sys.stdin:
    l = l.strip()
    if not l.startswith("{"): continue
    d = json.loads(l)
    if d.get("id") != alvo: continue
    r = d.get("result") or {}
    if campo == "erro_tool":
        print("SIM" if r.get("isError") else "NAO")
    print((r.get("content") or [{}])[0].get("text", "") or json.dumps(d.get("error")))
    break
' "$1" "$2"
}

call() {  # call <id> <tool> <json-args>
    printf '{"jsonrpc":"2.0","id":%s,"method":"tools/call","params":{"name":"%s","arguments":%s}}' "$1" "$2" "$3"
}

# ══════════════════════════════════════════════════════════
echo "── 1. handshake e tools"
saida=$(mcp "$H" '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' \
              '{"jsonrpc":"2.0","method":"notifications/initialized"}' \
              '{"jsonrpc":"2.0","id":2,"method":"tools/list"}')
echo "$saida" | "$PY_BIN" -c '
import json, sys
ds = {d["id"]: d for d in (json.loads(l) for l in sys.stdin if l.strip().startswith("{"))}
assert ds[1]["result"]["serverInfo"]["name"] == "gemini_decision", ds[1]
tools = ds[2]["result"]["tools"]
assert sorted(t["name"] for t in tools) == ["decide", "rank", "route", "ui_check"], [t["name"] for t in tools]
def andar(s, onde):
    if isinstance(s, dict):
        if s.get("type") == "object":
            assert s.get("properties"), f"objeto sem properties em {onde}"
        assert "anyOf" not in s and "oneOf" not in s, f"anyOf/oneOf em {onde}"
        for k, v in s.items():
            andar(v, onde + "." + k)
    elif isinstance(s, list):
        for i, v in enumerate(s):
            andar(v, f"{onde}[{i}]")
for t in tools:
    assert t["description"], t["name"]
    andar(t["inputSchema"], t["name"])
' || fail "handshake/tools errados: $saida"
ok "initialize, quatro tools e schemas portáveis"

echo
echo "── 2. decide monta o pedido nativo"
start_mock
args=$(printf '{"input":"log: fetch falhou","files":["%s"],"resolution":"low","questions":[
  {"id":"cors","type":"noul","instructions":"O erro é de CORS?","true_description":"bloqueio de origem"},
  {"id":"camada","type":"choice","instructions":"Qual camada?","options":["front: navegador","back: servidor"]},
  {"id":"sev","type":"score","instructions":"Gravidade?","levels":["baixa","media","alta"]}]}' "${TMP_DIR}/tela.png" | tr -d '\n')
saida=$(mcp "$H" "$(call 3 decide "$args")")
txt=$(echo "$saida" | resposta 3 texto)
echo "$txt" | grep -q '"cors"' || fail "decide não devolveu as respostas: $saida"
"$PY_BIN" - "${TMP_DIR}/pedidos.jsonl" "$KEY" "${TMP_DIR}/tela.png" <<'PY' || fail "pedido montado errado"
import base64, json, sys
p = json.loads(open(sys.argv[1]).readlines()[-1])
assert p["path"] == "/v1beta/decisions", p["path"]
assert p["key"] == sys.argv[2], "key não veio do providers.conf"
b = p["body"]
assert b["model"] == "gemini-decision-1"
txt, img = b["input"]
assert txt == {"type": "text", "text": "log: fetch falhou"}, txt
assert img["type"] == "image" and img["mime_type"] == "image/png" and img["resolution"] == "low", img
assert base64.b64decode(img["data"]) == open(sys.argv[3], "rb").read()
q = b["questions"]
assert q["cors"] == {"type": "noul", "instructions": "O erro é de CORS?",
                     "criteria": {"true_description": "bloqueio de origem"}}, q["cors"]
assert q["camada"]["criteria"] == {"front": "navegador", "back": "servidor"}, q["camada"]
assert q["sev"]["criteria"] == ["baixa", "media", "alta"], q["sev"]
PY
ok "POST /v1beta/decisions, key do providers.conf, PNG em base64, criteria convertidos"

echo
echo "── 3. ui_check separa falha / incerto / ok"
stop_mock
MOCK_FAIL="Salvar" start_mock
args=$(printf '{"screenshots":["%s"],"checks":["O botão Salvar está visível","O título usa a fonte da marca"],"context":"home 1440px"}' "${TMP_DIR}/tela.png")
saida=$(mcp "$H" "$(call 4 ui_check "$args")")
echo "$saida" | resposta 4 texto | "$PY_BIN" -c '
import json, sys
r = json.loads(sys.stdin.read())
c = r["capturas"][0]
assert [f["criterio"] for f in c["falhas"]] == ["O botão Salvar está visível"], c
assert c["ok"] == 6, c  # 1 critério do usuário + 5 padrão
assert "1 falha" in r["resumo"], r["resumo"]
' || fail "ui_check errado: $saida"
"$PY_BIN" -c '
import json, sys
b = json.loads(open(sys.argv[1]).readlines()[-1])["body"]
assert len(b["questions"]) == 7, len(b["questions"])
img = [x for x in b["input"] if x["type"] == "image"][0]
assert img["resolution"] == "high", img
' "${TMP_DIR}/pedidos.jsonl" || fail "ui_check não mandou 7 perguntas em alta resolução"
ok "critério reprovado vira falha; checagens padrão incluídas; resolução high"

echo
echo "── 4. rank ordena pela nota"
args='{"goal":"mostrar vendas por mês","candidates":["alpha: tabela de dados","beta: gráfico de barras","gamma: formulário"],"top":2}'
saida=$(mcp "$H" "$(call 5 rank "$args")")
echo "$saida" | resposta 5 texto | "$PY_BIN" -c '
import json, sys
r = json.loads(sys.stdin.read())
assert [x["id"] for x in r["ranking"]] == ["beta", "alpha"], r
assert r["descartados"] == 1, r
' || fail "rank errado: $saida"
ok "beta (gráfico) > alpha (tabela); gamma descartado; top respeitado"

echo
echo "── 5. credencial no texto não sai da máquina"
antes=$(pedidos)
segredo="AIza$(printf 'X%.0s' $(seq 1 35))"
saida=$(mcp "$H" "$(call 6 decide "{\"input\":\"config: $segredo\",\"questions\":[{\"type\":\"noul\",\"instructions\":\"ok?\"}]}")")
[[ "$(echo "$saida" | resposta 6 erro_tool | head -1)" == "SIM" ]] || fail "segredo não foi recusado: $saida"
[[ "$(pedidos)" == "$antes" ]] || fail "o pedido com segredo chegou à API"
echo "$saida" | grep -q "$segredo" && fail "a mensagem de erro ecoou o segredo"
for vazado in "sk_live_$(printf 'a1%.0s' $(seq 1 12))" "postgres://app:s3nh4@db.interno:5432/x" \
              "Authorization: Bearer $(printf 'Zx9%.0s' $(seq 1 10))"; do
    saida=$(mcp "$H" "$(call 6 rank "$("$PY_BIN" -c 'import json,sys; print(json.dumps({"goal":"x","candidates":["a: " + sys.argv[1]]}))' "$vazado")")")
    echo "$saida" | resposta 6 texto | grep -q "credencial" || fail "não recusou: ${vazado%%:*}…"
done
[[ "$(pedidos)" == "$antes" ]] || fail "um segredo chegou à API"
ok "recusado antes da rede, sem ecoar o valor (Google, Stripe, URL com senha, Bearer)"

echo
echo "── 5b. identificadores comuns não são confundidos com segredo"
saida=$(mcp "$H" "$(call 6 rank '{"goal":"tela de tarefas","candidates":["task-runner-default-worker-pool-1: fila","risk-assessment-summary-card-header: card","desk-booking-confirmation-modal-header: modal"]}')")
[[ "$(echo "$saida" | resposta 6 erro_tool | head -1)" == "NAO" ]] || fail "falso positivo: $saida"
ok "task-runner-…, risk-assessment-…, desk-booking-… passam"
antes=$(pedidos)

echo
echo "── 6. .env não vira anexo"
saida=$(mcp "$H" "$(call 7 decide "{\"files\":[\"${TMP_DIR}/.env\"],\"questions\":[{\"type\":\"noul\",\"instructions\":\"ok?\"}]}")")
echo "$saida" | resposta 7 texto | grep -q "tipo não suportado" || fail ".env aceito como arquivo: $saida"
[[ "$(pedidos)" == "$antes" ]] || fail ".env chegou à API"
cp "${TMP_DIR}/.env" "${TMP_DIR}/disfarce.png"
saida=$(mcp "$H" "$(call 7 decide "{\"files\":[\"${TMP_DIR}/disfarce.png\"],\"questions\":[{\"type\":\"noul\",\"instructions\":\"ok?\"}]}")")
echo "$saida" | resposta 7 texto | grep -q "não é um image/png de verdade" || fail ".env renomeado para .png passou: $saida"
[[ "$(pedidos)" == "$antes" ]] || fail ".env disfarçado chegou à API"
ok "só imagem/PDF/áudio/vídeo saem como arquivo, conferindo o conteúdo (não só a extensão)"

echo
echo "── 6b. arquivo fora das pastas permitidas não sai (nem por symlink)"
mkdir -p "${TMP_DIR}/permitido" "${TMP_DIR}/fora"
cp "${TMP_DIR}/tela.png" "${TMP_DIR}/fora/foto.png"
ln -s "${TMP_DIR}/fora/foto.png" "${TMP_DIR}/permitido/atalho.png"
for alvo in "${TMP_DIR}/fora/foto.png" "${TMP_DIR}/permitido/atalho.png"; do
    saida=$(printf '%s\n' "$(call 13 decide "{\"files\":[\"$alvo\"],\"questions\":[{\"type\":\"noul\",\"instructions\":\"ok?\"}]}")" |
        env -i PATH="/usr/bin:/bin" HOME="$H" GEMINI_DECISION_ALLOWED_DIRS="${TMP_DIR}/permitido" \
            GEMINI_DECISION_BASE_URL="http://127.0.0.1:9" GEMINI_DECISION_LOG=off "$PY_BIN" "$SERVER" 2>&1)
    echo "$saida" | resposta 13 texto | grep -q "fora das pastas permitidas" || fail "$alvo saiu: $saida"
done
ok "fora da lista → recusado; symlink resolvido antes da checagem"

echo
echo "── 7. sem key"
SEM="${TMP_DIR}/sem-key"; mkdir -p "$SEM"
saida=$(mcp "$SEM" "$(call 8 decide '{"input":"x","questions":[{"type":"noul","instructions":"ok?"}]}')")
echo "$saida" | resposta 8 texto | grep -q "ai gd key" || fail "erro sem key não ensina o comando: $saida"
[[ "$(pedidos)" == "$antes" ]] || fail "chamou a API sem key"
ok "erro ensina 'ai gd key' e não chama a API"

echo
echo "── 8. HTTP 400 da API"
stop_mock
MOCK_MODE=erro400 start_mock
saida=$(mcp "$H" "$(call 9 decide '{"input":"x","questions":[{"type":"noul","instructions":"ok?"}]}')" \
                 '{"jsonrpc":"2.0","id":10,"method":"ping"}')
echo "$saida" | resposta 9 texto | grep -q "HTTP 400: Request blocked" || fail "erro 400 ilegível: $saida"
echo "$saida" | grep -q '"id": 10' || fail "servidor morreu depois do 400"
ok "400 vira erro da tool e o servidor continua"
stop_mock

echo
echo "── 8b. argumento de tipo errado vira erro da tool, não -32603"
saida=$(mcp "$H" "$(call 11 decide '{"input":"x","questions":[{"type":"noul","instructions":5}]}')")
[[ "$(echo "$saida" | resposta 11 erro_tool | head -1)" == "SIM" ]] || fail "tipo errado não virou isError: $saida"
ok "instructions numérico → isError"

echo
echo "── 8c. stdio em cp1252 (Windows) não quebra acento nem ≤"
start_mock
saida=$(printf '%s\n' "$(call 12 ui_check "{\"screenshots\":[\"${TMP_DIR}/tela.png\"],\"checks\":[\"O botão não some\"]}")" |
    env -i PATH="/usr/bin:/bin" HOME="$H" PYTHONIOENCODING=cp1252 GEMINI_DECISION_BASE_URL="$BASE" \
        GEMINI_DECISION_LOG=off "$PY_BIN" "$SERVER" 2>&1)
echo "$saida" | resposta 12 texto | grep -q "≤" || fail "resumo com ≤ quebrou em cp1252: $saida"
"$PY_BIN" -c '
import json, sys
b = json.loads(open(sys.argv[1]).readlines()[-1])["body"]
assert any("O botão não some" in q["instructions"] for q in b["questions"].values()), b["questions"]
' "${TMP_DIR}/pedidos.jsonl" || fail "acento corrompido no caminho até a API"
stop_mock
ok "entrada e saída em UTF-8 mesmo com o locale do Windows"

echo
echo "── 9. registro de uso sem conteúdo"
[[ -s "${TMP_DIR}/uso.jsonl" ]] || fail "uso não registrado"
grep -q "fetch falhou\|Salvar\|vendas" "${TMP_DIR}/uso.jsonl" && fail "o registro de uso guardou conteúdo"
ok "só data, tool, tokens, ms e nº de perguntas"

# ══════════════════════════════════════════════════════════
# Launcher. Um HOME falso com as CLIs que o T3 usa; `claude` é um falso que
# grava como o de verdade (`claude mcp add-json -s user`).
L="${TMP_DIR}/lhome"
FAKE_BIN="${TMP_DIR}/bin"
mkdir -p "$L/.claude" "$L/.claude_segunda" "$L/.codex" "$L/.gemini" "$L/.config/opencode" "$FAKE_BIN"
echo '{"mcpServers":{"jev":{"type":"stdio","command":"py","args":["j"]}},"numStartups":7}' > "$L/.claude.json"
echo '{"mcpServers":{}}' > "$L/.claude_segunda/.claude.json"
printf '# Minhas regras\nlinha original\n' > "$L/.claude/CLAUDE.md"
printf 'model = "x"\n\n[mcp_servers.jev]\ncommand = "py"\nargs = ["j"]\n' > "$L/.codex/config.toml"
printf 'regras codex\n' > "$L/.codex/AGENTS.md"
echo '{"mcpServers":{"firecrawl":{"command":"npx"}},"security":{"a":1}}' > "$L/.gemini/settings.json"
chmod 600 "$L/.gemini/settings.json"
echo '{"$schema":"x","mcp":{"jev":{"type":"local","command":["py","j"],"enabled":true}}}' > "$L/.config/opencode/opencode.json"
# T3 com um provider ACP que lê MCP de arquivo próprio (o Qwen do t1).
mkdir -p "$L/.t3/userdata" "$L/.config/t3-routing"
echo '{"mcpServers":{"t3_jev":{"command":"py","args":["s"]}}}' > "$L/.config/t3-routing/qwen-mcp.json"
# Mais CLIs que o T3 roda, cada uma com o formato dela.
mkdir -p "$L/.minimax" "$L/.codebuddy" "$L/.config/muse" "$L/.codex-venice" "$L/perfis/hy4"
echo '{"mcpServers":{"nexus":{"command":"n","args":[]}}}' > "$L/.minimax/mcp.json"
echo '{"mcpServers":{"browse":{"type":"stdio","command":"b","args":[]}}}' > "$L/.codebuddy/.mcp.json"
echo '{"model":"m","mcpServers":{"jev":{"mode":"optional","transport":"stdio","command":"python3","args":["j"]}}}' > "$L/.config/muse/settings.json"
echo '{"mcpServers":{}}' > "$L/perfis/hy4/.claude.json"
# Codex com home própria (provider do T3) e um bloco antigo com cabeçalho
# comentado, array de várias linhas e uma chave do usuário a preservar.
printf 'model = "v"\n\n[mcp_servers.gemini_decision] # antigo\ncommand = "velho"\nargs = [\n  "x",\n]\nstartup_timeout_sec = 30\n\n[outra]\nk = 1\n' > "$L/.codex-venice/config.toml"
printf 'regras venice\n' > "$L/.codex-venice/AGENTS.md"
printf '{"providerInstances":{"acp_qwen":{"driver":"acpRegistry","config":{"source":"local","commandPath":"qwen","commandArgs":["--acp","--mcp-config","%s"]}},"venice":{"driver":"codex","config":{"homePath":"%s"}},"hy4":{"driver":"claudeAgent","config":{"homePath":"%s"}}}}\n' \
    "$L/.config/t3-routing/qwen-mcp.json" "$L/.codex-venice" "$L/perfis/hy4" > "$L/.t3/userdata/settings.json"

cat > "$FAKE_BIN/claude" <<'PY'
#!/usr/bin/env python3
import json, os, sys
a = sys.argv[1:]
d = os.environ.get("CLAUDE_CONFIG_DIR")
with open(os.environ["FAKE_CLAUDE_LOG"], "a") as f:
    f.write(f"{d or '-'}|{' '.join(a[:4])}\n")
cfg = os.path.join(d, ".claude.json") if d else os.path.join(os.environ["HOME"], ".claude.json")
j = json.load(open(cfg))
if a[:2] == ["mcp", "add-json"]:
    j.setdefault("mcpServers", {})[a[4]] = json.loads(a[5])
elif a[:2] == ["mcp", "remove"]:
    j.get("mcpServers", {}).pop(a[-1], None)
json.dump(j, open(cfg, "w"), indent=2)
PY
chmod +x "$FAKE_BIN/claude"

ai_l() {
    HOME="$L" PATH="${FAKE_BIN}:$PATH" FAKE_CLAUDE_LOG="${TMP_DIR}/claude.log" AI_GD_PYTHON="$PY_BIN" \
        GEMINI_DECISION_BASE_URL="${BASE:-http://127.0.0.1:9}" GEMINI_DECISION_LOG=off \
        "$ROOT/ai" gd "$@"
}

echo
echo "── 10. ai gd key"
saida=$(ai_l key "$KEY" 2>&1) || fail "ai gd key falhou: $saida"
grep -q "^gemini-decision=${KEY}$" "$L/.local/share/ai-launcher/providers.conf" || fail "key não foi para o slot gemini-decision"
perm=$(stat -f '%Lp' "$L/.local/share/ai-launcher/providers.conf" 2>/dev/null || stat -c '%a' "$L/.local/share/ai-launcher/providers.conf")
[[ "$perm" == "600" ]] || fail "providers.conf com permissão $perm"
echo "$saida" | grep -q "$KEY" && fail "ai gd key imprimiu a key"
ok "slot gemini-decision, chmod 600, nada impresso"

echo
echo "── 11. ai gd setup"
saida=$(ai_l setup 2>&1) || fail "ai gd setup falhou: $saida"
INST="$L/.local/share/ai-launcher/mcp/gemini-decision-server.py"
cmp -s "$INST" "$SERVER" || fail "servidor não foi instalado em ${INST}"
"$PY_BIN" - "$L" "$INST" "$PY_BIN" <<'PY' || fail "registro errado. Saída: $saida"
import json, os, re, sys
L, inst, py = sys.argv[1:4]
esperado = {"command": py, "args": [inst]}
c = json.load(open(f"{L}/.claude.json"))
assert c["numStartups"] == 7 and "jev" in c["mcpServers"], "perdeu config do Claude"
assert c["mcpServers"]["gemini_decision"]["command"] == py, c["mcpServers"]["gemini_decision"]
assert c["mcpServers"]["gemini_decision"]["args"] == [inst]
s = json.load(open(f"{L}/.claude_segunda/.claude.json"))
assert s["mcpServers"]["gemini_decision"]["args"] == [inst], "perfil claude_segunda ficou de fora"
g = json.load(open(f"{L}/.gemini/settings.json"))
assert {k: g["mcpServers"]["gemini_decision"][k] for k in ("command", "args")} == esperado, g
assert g["security"] == {"a": 1} and "firecrawl" in g["mcpServers"], "perdeu config do Gemini"
q = json.load(open(f"{L}/.config/t3-routing/qwen-mcp.json"))
assert q["mcpServers"]["gemini_decision"] == esperado and "t3_jev" in q["mcpServers"], q
o = json.load(open(f"{L}/.config/opencode/opencode.json"))
assert o["mcp"]["gemini_decision"] == {"type": "local", "command": [py, inst], "enabled": True}, o["mcp"]
assert "jev" in o["mcp"] and o["$schema"] == "x"
t = open(f"{L}/.codex/config.toml").read()
assert t.count("[mcp_servers.gemini_decision]") == 1, t
assert f"command = {json.dumps(py)}" in t and f"args = [{json.dumps(inst)}]" in t, t
assert t.startswith('model = "x"') and "[mcp_servers.jev]" in t, "perdeu config do Codex"
m = json.load(open(f"{L}/.minimax/mcp.json"))["mcpServers"]
assert m["gemini_decision"] == esperado and "nexus" in m, m
b = json.load(open(f"{L}/.codebuddy/.mcp.json"))["mcpServers"]
assert b["gemini_decision"] == dict(esperado, type="stdio"), b
u = json.load(open(f"{L}/.config/muse/settings.json"))
assert u["mcpServers"]["gemini_decision"] == dict(esperado, mode="optional", transport="stdio"), u
assert u["model"] == "m" and "jev" in u["mcpServers"]
h = json.load(open(f"{L}/perfis/hy4/.claude.json"))
assert h["mcpServers"]["gemini_decision"]["args"] == [inst], "homePath claudeAgent do T3 ficou de fora"
v = open(f"{L}/.codex-venice/config.toml").read()
try:
    import tomllib
    tv = tomllib.loads(v)
    assert tv["mcp_servers"]["gemini_decision"] == {"command": py, "args": [inst], "startup_timeout_sec": 30}, tv
    assert tv["outra"] == {"k": 1} and tv["model"] == "v", tv
except ImportError:
    pass
assert v.count("gemini_decision") == 1 and "velho" not in v, v
assert "<!-- gemini-decision:inicio" in open(f"{L}/.codex-venice/AGENTS.md").read(), "AGENTS.md da home venice sem bloco"
for ausente in (".kimi", ".cursor", ".qwen", ".gemini/antigravity", ".config/devin"):
    assert not os.path.exists(f"{L}/{ausente}"), f"criou {ausente} para CLI que não existe"
for f, original in ((f"{L}/.claude/CLAUDE.md", "# Minhas regras\nlinha original\n"),
                    (f"{L}/.codex/AGENTS.md", "regras codex\n")):
    t = open(f).read()
    assert t.startswith(original), f"{f}: conteúdo original mexido"
    assert t.count("<!-- gemini-decision:inicio") == 1 and "ui_check" in t, f"{f}: bloco ausente"
assert not os.path.exists(f"{L}/.gemini/GEMINI.md"), "criou GEMINI.md"
PY
perm=$(stat -f '%Lp' "$L/.gemini/settings.json" 2>/dev/null || stat -c '%a' "$L/.gemini/settings.json")
[[ "$perm" == "600" ]] || fail "settings.json do Gemini mudou para $perm"
if grep -rl --exclude=providers.conf -- "$KEY" "$L" >/dev/null 2>&1; then
    fail "a key foi parar num config: $(grep -rl --exclude=providers.conf -- "$KEY" "$L")"
fi
grep -q "^${L}/.claude_segunda|mcp add-json -s user" "${TMP_DIR}/claude.log" || fail "perfil não usou CLAUDE_CONFIG_DIR: $(cat "${TMP_DIR}/claude.log")"
grep -q "^${L}/perfis/hy4|mcp add-json -s user" "${TMP_DIR}/claude.log" || fail "homePath do T3 não usou CLAUDE_CONFIG_DIR"
ok "Claude (perfis e homePath do T3), Codex (2 homes, TOML válido), Gemini, MiniMax, CodeBuddy, Muse, opencode, MCP de provider do T3; nada criado para CLI ausente; key fora dos configs"

echo
echo "── 12. setup de novo não muda nada"
soma() { find "$L" -type f ! -name '*.log' ! -path '*/ai-launcher/*' -exec cksum {} + | sort; }
antes=$(soma); chamadas=$(wc -l < "${TMP_DIR}/claude.log")
ai_l setup >/dev/null 2>&1 || fail "segundo setup falhou"
[[ "$(soma)" == "$antes" ]] || fail "segundo setup mudou arquivos"
[[ "$(wc -l < "${TMP_DIR}/claude.log")" == "$chamadas" ]] || fail "segundo setup chamou o claude de novo"
ok "idempotente"

echo
echo "── 13. ai gd ui sinaliza falha no código de saída"
MOCK_FAIL="Salvar" start_mock
set +e
saida=$(ai_l ui "${TMP_DIR}/tela.png" -c "O botão Salvar está visível" 2>&1); rc=$?
set -e
[[ $rc -eq 1 ]] || fail "ai gd ui devolveu $rc com critério reprovado: $saida"
echo "$saida" | grep -q "✗.*Salvar" || fail "falha não aparece na saída: $saida"
stop_mock
ok "rc=1 e a falha listada"

echo
echo "── 16. route usa o catálogo real do T3: tier certo, rodízio, só prontos"
T3F="${TMP_DIR}/t3"; mkdir -p "$T3F/userdata" "$T3F/caches"
echo "env-teste-1" > "$T3F/userdata/environment-id"
cat > "$T3F/userdata/settings.json" <<'JSON'
{"providerInstances": {
  "claude": {"driver": "claudeAgent", "enabled": true, "displayName": "Claude"},
  "glm": {"driver": "acpRegistry", "enabled": true, "displayName": "GLM Agent"},
  "gpt": {"driver": "codex", "enabled": true, "displayName": "Codex"},
  "hy4": {"driver": "claudeAgent", "enabled": true, "displayName": "Tencent Hy4",
          "environment": [{"name": "ANTHROPIC_BASE_URL", "value": "", "sensitive": false}]},
  "desligado": {"driver": "claudeAgent", "enabled": false},
  "quebrado": {"driver": "acpRegistry", "enabled": true},
  "venice": {"driver": "opencode", "enabled": true}
}}
JSON
EF='{"optionDescriptors":[{"id":"effort","options":[{"id":"low"},{"id":"medium"},{"id":"high"},{"id":"max"}]}]}'
modelos() { "$PY_BIN" -c 'import json,sys; c=json.loads(sys.argv[1]); print(json.dumps({"status": sys.argv[2], "models": [dict(slug=m, name=m, isDefault=(i==0), capabilities=c) for i,m in enumerate(sys.argv[3:])]}))' "$EF" "$@"; }
modelos ready claude-opus-5-5 claude-sonnet-5-5 claude-haiku-5-5 > "$T3F/caches/claude.json"
modelos ready glm-5.3 glm-5.3-flash glm-5-turbo > "$T3F/caches/glm.json"
modelos ready gpt-6-sol gpt-6-luna gpt-6-luna-fast > "$T3F/caches/gpt.json"
modelos ready claude-opus-5-5 claude-haiku-5-5 > "$T3F/caches/hy4.json"
modelos ready claude-haiku-5-5 > "$T3F/caches/desligado.json"
modelos error claude-haiku-5-5 > "$T3F/caches/quebrado.json"
modelos ready venice-uncensored-flash > "$T3F/caches/venice.json"
modelos ready gpt-6-luna > "$T3F/caches/sem-instancia.json"
GDD="${TMP_DIR}/gddata"
MOCK_CHOICE="simples,geral,standard" start_mock
rota() {
    env -i PATH="/usr/bin:/bin" HOME="$H" T3CODE_HOME="$T3F" GEMINI_DECISION_DATA_DIR="$GDD" \
        GEMINI_DECISION_BASE_URL="$BASE" GEMINI_DECISION_LOG=off "$PY_BIN" "$SERVER" call route "$1"
}
r=$(rota '{"task":"renomear uma variável em três arquivos","units":3}') || fail "route falhou: $r"
echo "$r" | "$PY_BIN" -c '
import json, sys
r = json.load(sys.stdin)
d = r["destinos"]
assert r["complexidade"] == "simples" and r["tier"] == "light", r
assert r["ambiente"] == "env-teste-1", r
assert {(x["providerInstanceId"], x["model"]) for x in d} == {
    ("claude", "claude-haiku-5-5"), ("glm", "glm-5.3-flash"), ("gpt", "gpt-6-luna")}, d
claude = [x for x in d if x["providerInstanceId"] == "claude"][0]
assert claude["effort"] == "low", claude
todos = json.dumps(r)
for proibido in ("desligado", "quebrado", "venice", "sem-instancia", "luna-fast"):
    assert proibido not in todos, proibido
' || fail "route simples errado: $r"
ok "simples → Haiku, GLM 5.3 Flash e Luna, um por provedor, esforço low; desligado/erro/sem censura/Fast/sem instância fora"
vistos=""
for i in 1 2 3; do
    r=$(rota '{"task":"ajustar um texto"}') || fail "route falhou"
    vistos="$vistos $(echo "$r" | "$PY_BIN" -c 'import json,sys; print(json.load(sys.stdin)["destinos"][0]["providerInstanceId"])')"
done
[[ "$(echo $vistos | tr ' ' '\n' | sort -u | wc -l | tr -d ' ')" == "3" ]] || fail "sem rodízio entre provedores: $vistos"
ok "rodízio: três chamadas seguidas foram para três provedores diferentes ($vistos )"
r=$(rota '{"task":"redesenhar a arquitetura de autenticação","complexity":"complexa","units":2}') || fail "route complexa falhou"
echo "$r" | "$PY_BIN" -c '
import json, sys
r = json.load(sys.stdin)
assert r["tier"] == "flagship", r
assert {x["model"] for x in r["destinos"]} == {"claude-opus-5-5", "gpt-6-sol"}, r["destinos"]
assert [x["effort"] for x in r["destinos"] if x["model"] == "claude-opus-5-5"] == ["high"], r["destinos"]
' || fail "route complexa errado: $r"
"$PY_BIN" -c '
import json, sys
c = json.load(open(sys.argv[1]))
assert c.get("glm agent|glm-5-turbo") == "standard" and c.get("tencent hy4|claude-opus-5-5") == "standard", c
' "$GDD/gd-model-tiers.json" || fail "tier dos desconhecidos não foi classificado/cacheado"
stop_mock
ok "complexa → Opus e Sol com esforço high (nunca max); desconhecidos classificados pelo Gemini Decision e cacheados"
echo
echo "── 16b. frontend: só os melhores de ponta, famílias diferentes, sempre com revisor"
T3G="${TMP_DIR}/t3front"; mkdir -p "$T3G/userdata" "$T3G/caches"
cat > "$T3G/userdata/settings.json" <<'JSON'
{"providerInstances": {
  "claude": {"driver": "claudeAgent", "enabled": true},
  "claude2": {"driver": "claudeAgent", "enabled": true},
  "gpt": {"driver": "codex", "enabled": true},
  "gem": {"driver": "antigravity", "enabled": true},
  "venice": {"driver": "codex", "enabled": true, "environment": [{"name": "VENICE_API_KEY", "value": ""}]},
  "glm": {"driver": "acpRegistry", "enabled": true},
  "hy4": {"driver": "claudeAgent", "enabled": true, "displayName": "Tencent Hy4",
          "environment": [{"name": "ANTHROPIC_BASE_URL", "value": ""}]}
}}
JSON
modelos ready claude-opus-5-5 claude-fable-5-2 claude-haiku-5-5 > "$T3G/caches/claude.json"
modelos ready claude-opus-5-5 claude-sonnet-5-5 > "$T3G/caches/claude2.json"
modelos ready gpt-6-astra gpt-6-luna > "$T3G/caches/gpt.json"
modelos ready gemini-4-carbon gemini-3.8-flash > "$T3G/caches/gem.json"
modelos ready glm-5.3 glm-5.3-flash > "$T3G/caches/glm.json"
modelos ready claude-opus-5-5 > "$T3G/caches/hy4.json"
modelos ready gpt-6-astra > "$T3G/caches/venice.json"
MOCK_CHOICE="frontend,simples,standard" start_mock
r=$(env -i PATH="/usr/bin:/bin" HOME="$H" T3CODE_HOME="$T3G" GEMINI_DECISION_DATA_DIR="${TMP_DIR}/gddata2" \
    GEMINI_DECISION_BASE_URL="$BASE" GEMINI_DECISION_LOG=off "$PY_BIN" "$SERVER" call route \
    '{"task":"trocar a cor do botão primário","units":2}') || fail "route frontend falhou: $r"
stop_mock
echo "$r" | "$PY_BIN" -c '
import json, sys
r = json.load(sys.stdin)
topo = {"claude-fable-5-2", "claude-opus-5-5", "gemini-4-carbon", "gpt-6-astra"}
d = r["destinos"]
assert r["papel"] == "frontend" and r["tier"] == "flagship", r
assert all(x["model"] in topo for x in d), d
assert len({x["providerInstanceId"] for x in d}) == 2 and len({x["model"] for x in d}) == 2, d
assert "hy4" not in json.dumps(r), "Hy4 (endpoint próprio com slug de Opus) entrou como Opus"
assert "venice" not in json.dumps(r), "Venice (key própria) entrou como GPT-6 Astra oficial"
rv = r["revisor"]
assert rv and rv["model"] in topo, rv
assert rv["model"] not in {x["model"] for x in d}, ("revisor da mesma família", rv, d)
assert rv["providerInstanceId"] not in {x["providerInstanceId"] for x in d}, ("revisor do mesmo provedor", rv)
' || fail "route frontend errado: $r"
ok "UI simples ainda vai para Fable/Opus/Carbon/Astra, duas famílias, revisor de outra família e provedor; Hy4 fora"

saida=$(env -i PATH="/usr/bin:/bin" HOME="$H" T3CODE_HOME="${TMP_DIR}/nao-existe" GEMINI_DECISION_LOG=off \
    "$PY_BIN" "$SERVER" call route '{"task":"x"}' 2>&1) && fail "route sem T3 deveria falhar"
echo "$saida" | grep -q "T3 não encontrado" || fail "erro sem T3 ilegível: $saida"
ok "sem T3: erro claro"

echo
echo "── 14. sem a CLI do Claude: edição direta; arquivo ruim não para os outros"
L2="${TMP_DIR}/l2"; mkdir -p "$L2/.codex"
echo '{"mcpServers":{"jev":{"command":"py"}},"numStartups":3}' > "$L2/.claude.json"
printf 'regras\n<!-- gemini-decision:inicio órfão sem fim\n' > "$L2/.codex/AGENTS.md"
cp "$L2/.codex/AGENTS.md" "${TMP_DIR}/agents-orfao"
chamadas=$(wc -l < "${TMP_DIR}/claude.log")
set +e
saida=$(HOME="$L2" PATH="${FAKE_BIN}:$PATH" FAKE_CLAUDE_LOG="${TMP_DIR}/claude.log" AI_GD_NO_CLAUDE_CLI=1 AI_GD_PYTHON="$PY_BIN" \
    "$ROOT/ai" gd setup 2>&1); rc=$?
set -e
[[ $rc -eq 1 ]] || fail "setup com marcador órfão devolveu $rc: $saida"
"$PY_BIN" -c '
import json, sys
c = json.load(open(sys.argv[1]))
assert c["numStartups"] == 3 and "jev" in c["mcpServers"] and "gemini_decision" in c["mcpServers"], c
' "$L2/.claude.json" || fail "edição direta do .claude.json errada"
cmp -s "$L2/.codex/AGENTS.md" "${TMP_DIR}/agents-orfao" || fail "mexeu no arquivo com marcador órfão"
[[ "$(wc -l < "${TMP_DIR}/claude.log")" == "$chamadas" ]] || fail "chamou a CLI do Claude com AI_GD_NO_CLAUDE_CLI"
ok "registro direto preserva o JSON; marcador órfão vira ERRO (rc=1) sem tocar no arquivo"

echo
echo "── 15. ai gd remove desfaz tudo"
ai_l remove >/dev/null 2>&1 || fail "ai gd remove falhou"
"$PY_BIN" - "$L" <<'CHECK' || fail "remove incompleto"
import json, os, sys
L = sys.argv[1]
for f, k in ((".claude.json", "mcpServers"), (".claude_segunda/.claude.json", "mcpServers"),
             ("perfis/hy4/.claude.json", "mcpServers"), (".gemini/settings.json", "mcpServers"),
             (".minimax/mcp.json", "mcpServers"), (".codebuddy/.mcp.json", "mcpServers"),
             (".config/muse/settings.json", "mcpServers"), (".config/opencode/opencode.json", "mcp"),
             (".config/t3-routing/qwen-mcp.json", "mcpServers")):
    assert "gemini_decision" not in json.load(open(f"{L}/{f}"))[k], f
for f in (".codex/config.toml", ".codex-venice/config.toml"):
    t = open(f"{L}/{f}").read()
    assert "gemini_decision" not in t, (f, t)
assert "[outra]" in open(f"{L}/.codex-venice/config.toml").read()
assert open(f"{L}/.claude/CLAUDE.md").read() == "# Minhas regras\nlinha original\n"
assert open(f"{L}/.codex/AGENTS.md").read() == "regras codex\n"
assert os.path.isfile(f"{L}/.codex/config.toml.bak-gd"), "sem backup do original"
CHECK
ok "MCP fora de todas as CLIs, instruções voltam ao original, backups .bak-gd guardados"

echo
echo "PASS: Gemini Decision (servidor MCP e ai gd)"
