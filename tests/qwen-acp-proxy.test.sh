#!/usr/bin/env bash

# mcp/qwen-acp-proxy.py: o Qwen Code 1.0 no ACP só anuncia e só aceita o
# model.name do settings.json. O proxy mostra ao T3 todos os modelos dos
# providers e troca de modelo retomando a sessão num `qwen --acp` por modelo.
# O qwen falso abaixo imita o real: um modelo só no ACP, set_model recusado
# para outro, sessão gravada em <config>/projects só depois do 1º prompt e,
# no resume, volta ao modelo salvo se ele ainda estiver na lista. O teste trava:
#  - lista completa no session/new e no config option "model";
#  - troca por set_model e por set_config_option, com histórico e modo mantidos;
#  - sessão ainda sem prompt troca abrindo outra (o T3 continua vendo o id dele);
#  - pedido de permissão de dois processos com o mesmo id não se confunde;
#  - pasta por modelo: settings 600 só com aquele modelo, projects compartilhado;
#  - modelo fora da lista dá erro; um modelo só → qwen direto, sem proxy.

set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT
export HOME="${TMP_DIR}/home"
mkdir -p "$HOME/.qwen/memory"
echo "nota" > "$HOME/.qwen/memory/x.md"
FAKE="${TMP_DIR}/qwen"

cat > "$FAKE" <<'PY'
#!/usr/bin/env python3
import json, os, sys, uuid
cfg = os.environ["QWEN_CONFIG_DIR"] if os.environ.get("QWEN_CONFIG_DIR") else os.path.expanduser("~/.qwen")
st = json.load(open(os.path.join(cfg, "settings.json")))
MODEL = st["model"]["name"]
listed = {f"{p}/{m['model']}" for p, v in st.get("providers", {}).items() for m in v.get("models", [])}
sessions = {}
def out(m): sys.stdout.write(json.dumps(m) + "\n"); sys.stdout.flush()
def state(sid, model):
    return {"sessionId": sid,
            "models": {"availableModels": [{"modelId": model, "name": model}], "currentModelId": model},
            "configOptions": [{"id": "mode", "type": "select", "currentValue": sessions[sid]["mode"], "options": []},
                              {"id": "model", "type": "select", "currentValue": model,
                               "options": [{"value": model, "name": model}]}]}
def path(sid): return os.path.join(cfg, "projects", sid + ".json")
for line in sys.stdin:
    d = json.loads(line); mid = d.get("id"); m = d.get("method"); p = d.get("params") or {}
    if m is None: continue
    if m == "initialize":
        out({"jsonrpc": "2.0", "id": mid, "result": {"protocolVersion": 1}})
    elif m == "session/new":
        sid = str(uuid.uuid4()); sessions[sid] = {"model": MODEL, "mode": "default", "hist": []}
        out({"jsonrpc": "2.0", "id": mid, "result": state(sid, MODEL)})
    elif m == "session/resume":
        sid = p["sessionId"]
        if not os.path.exists(path(sid)):
            out({"jsonrpc": "2.0", "id": mid, "error": {"code": -32002, "message": "Resource not found"}}); continue
        saved = json.load(open(path(sid)))
        model = saved["model"] if saved["model"] in listed else MODEL
        sessions[sid] = {"model": model, "mode": "default", "hist": saved["hist"]}
        out({"jsonrpc": "2.0", "id": mid, "result": state(sid, model)})
    elif m == "session/set_model":
        if p["modelId"] != sessions[p["sessionId"]]["model"]:
            out({"jsonrpc": "2.0", "id": mid, "error": {"code": -32602, "message": "Invalid or unavailable model"}})
        else:
            out({"jsonrpc": "2.0", "id": mid, "result": {}})
    elif m == "session/set_mode":
        sessions[p["sessionId"]]["mode"] = p["modeId"]; out({"jsonrpc": "2.0", "id": mid, "result": {}})
    elif m == "session/close":
        sessions.pop(p["sessionId"], None); out({"jsonrpc": "2.0", "id": mid, "result": {}})
    elif m == "session/prompt":
        sid = p["sessionId"]; s = sessions[sid]; txt = p["prompt"][0]["text"]
        out({"jsonrpc": "2.0", "id": 0, "method": "session/request_permission", "params": {"sessionId": sid}})
        resp = json.loads(sys.stdin.readline())
        assert resp.get("id") == 0 and resp["result"]["outcome"] == "ok", resp
        out({"jsonrpc": "2.0", "method": "session/update", "params": {"sessionId": sid, "update": {
            "sessionUpdate": "agent_message_chunk",
            "content": {"type": "text", "text": f"{s['model']}|{s['mode']}|{len(s['hist'])}:{txt}"}}}})
        s["hist"].append(txt)
        os.makedirs(os.path.dirname(path(sid)), exist_ok=True)
        json.dump({"model": s["model"], "hist": s["hist"]}, open(path(sid), "w"))
        out({"jsonrpc": "2.0", "id": mid, "result": {"stopReason": "end_turn"}})
PY
chmod +x "$FAKE"

P="alibaba-token-plan"
cat > "$HOME/.qwen/settings.json" <<JSON
{"model": {"name": "$P/qwen4-max-preview"},
 "mcpServers": {"x": {"command": "y"}},
 "providers": {"$P": {"type": "alibaba", "apiKey": "sk-teste", "models": [
   {"model": "qwen4-max-preview"}, {"model": "deepseek-v4-pro"}, {"model": "deepseek-v4.1-flash"}]}}}
JSON

python3 -I - "$ROOT/mcp/qwen-acp-proxy.py" "$FAKE" "$P" <<'PY'
import json, os, queue, subprocess, sys, threading, time
proxy, fake, P = sys.argv[1:4]
Q4, PRO, FLASH = f"{P}/qwen4-max-preview", f"{P}/deepseek-v4-pro", f"{P}/deepseek-v4.1-flash"
pr = subprocess.Popen([sys.executable, proxy, fake, "--acp"], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
linhas = queue.Queue()
threading.Thread(target=lambda: [linhas.put(l) for l in pr.stdout], daemon=True).start()
ids = iter(range(100, 10**6))
notes = []
def send(m): pr.stdin.write(json.dumps(m) + "\n"); pr.stdin.flush()
def call(method, params, timeout=20):
    i = next(ids); send({"jsonrpc": "2.0", "id": i, "method": method, "params": params})
    end = time.time() + timeout
    while time.time() < end:
        try:
            d = json.loads(linhas.get(timeout=0.2))
        except queue.Empty:
            continue
        if "method" in d and "id" in d:  # permissão: responde e segue
            send({"jsonrpc": "2.0", "id": d["id"], "result": {"outcome": "ok"}}); notes.append(d); continue
        if "method" in d: notes.append(d); continue
        if d.get("id") == i: return d
    raise SystemExit(f"FAIL: sem resposta para {method}")
def ok(c, msg):
    if not c: raise SystemExit("FAIL: " + msg)
def texto(sid):
    t = [n["params"]["update"]["content"]["text"] for n in notes
         if n.get("method") == "session/update" and n["params"].get("sessionId") == sid
         and n["params"]["update"].get("sessionUpdate") == "agent_message_chunk"]
    return t[-1] if t else None
def prompt(sid, txt):
    r = call("session/prompt", {"sessionId": sid, "prompt": [{"type": "text", "text": txt}]})
    ok(r.get("result", {}).get("stopReason") == "end_turn", f"prompt falhou: {r}")
    return texto(sid)

ok("result" in call("initialize", {"protocolVersion": 1}), "initialize")
r = call("session/new", {"cwd": "/tmp", "mcpServers": []})["result"]
sid = r["sessionId"]
ok([m["modelId"] for m in r["models"]["availableModels"]] == [Q4, PRO, FLASH], f"lista: {r['models']}")
ok(r["models"]["currentModelId"] == Q4, "modelo atual")
opt = [o for o in r["configOptions"] if o["id"] == "model"][0]
ok([o["value"] for o in opt["options"]] == [Q4, PRO, FLASH] and opt["currentValue"] == Q4, f"config option: {opt}")
print("  ok: T3 vê os 3 modelos (session/new e config option)")

ok("result" in call("session/set_mode", {"sessionId": sid, "modeId": "yolo"}), "set_mode")
ok(prompt(sid, "a") == f"{Q4}|yolo|0:a", f"1º prompt: {texto(sid)}")
r = call("session/set_model", {"sessionId": sid, "modelId": FLASH})
ok(r.get("result") == {}, f"set_model: {r}")
ok(prompt(sid, "b") == f"{FLASH}|yolo|1:b", f"depois do set_model: {texto(sid)}")
upd = [n for n in notes if n.get("method") == "session/update"
       and n["params"]["update"].get("sessionUpdate") == "config_option_update"]
ok(upd and [o for o in upd[-1]["params"]["update"]["configOptions"] if o["id"] == "model"][0]["currentValue"] == FLASH,
   "T3 não foi avisado do modelo novo")
print("  ok: set_model troca de processo com histórico e modo yolo mantidos")

r = call("session/set_config_option", {"sessionId": sid, "configId": "model", "value": PRO})
opt = [o for o in r["result"]["configOptions"] if o["id"] == "model"][0]
ok(opt["currentValue"] == PRO and len(opt["options"]) == 3, f"set_config_option: {r}")
ok(prompt(sid, "c") == f"{PRO}|yolo|2:c", f"depois do config option: {texto(sid)}")
r = call("session/set_model", {"sessionId": sid, "modelId": Q4})
ok(r.get("result") == {} and prompt(sid, "d") == f"{Q4}|yolo|3:d", f"volta ao padrão: {texto(sid)}")
print("  ok: set_config_option e volta ao modelo padrão")

r = call("session/new", {"cwd": "/tmp", "mcpServers": []})["result"]
sid2 = r["sessionId"]
r = call("session/set_model", {"sessionId": sid2, "modelId": FLASH})
ok(r.get("result") == {}, f"troca sem prompt: {r}")
ok(prompt(sid2, "z") == f"{FLASH}|default|0:z", f"sessão nova no flash: {texto(sid2)}")
print("  ok: sessão sem prompt troca abrindo outra; o T3 segue com o id dele")

r = call("session/set_model", {"sessionId": sid, "modelId": f"{P}/inexistente"})
ok("error" in r, "aceitou modelo fora da lista")

home = os.path.expanduser("~")
pasta = os.path.join(home, ".local/share/ai-launcher/qwen-acp", f"{P}_deepseek-v4.1-flash")
st = json.load(open(os.path.join(pasta, "settings.json")))
ok(st["model"]["name"] == FLASH and st["providers"][P]["models"] == [{"model": "deepseek-v4.1-flash"}],
   f"settings da pasta do modelo: {st['providers']}")
ok(st["mcpServers"] == {"x": {"command": "y"}}, "perdeu o MCP na pasta do modelo")
ok(oct(os.stat(os.path.join(pasta, "settings.json")).st_mode & 0o777) == "0o600", "settings da pasta não é 600")
ok(os.path.realpath(os.path.join(pasta, "projects")) == os.path.realpath(os.path.join(home, ".qwen/projects")),
   "projects da pasta do modelo não é o da ~/.qwen")
ok(os.path.exists(os.path.join(pasta, "memory/x.md")), "memória não compartilhada")
ok(os.path.exists(os.path.join(home, ".qwen/projects", sid + ".json")), "sessão não ficou na ~/.qwen")
print("  ok: pasta por modelo (600, um modelo só, sessões e memória da ~/.qwen)")

pr.stdin.close()
ok(pr.wait(timeout=15) == 0, "proxy não saiu limpo")
PY

# O T3 sobe várias instâncias do provider ao mesmo tempo (status + sessão):
# todas preparam a mesma pasta do modelo e nenhuma pode cair.
python3 -I - "$ROOT/mcp/qwen-acp-proxy.py" "$FAKE" "${TMP_DIR}/estado-novo" <<'PY'
import json, os, subprocess, sys
proxy, fake, estado = sys.argv[1:4]
for rodada in range(3):
    env = dict(os.environ, QWEN_ACP_PROXY_DIR=f"{estado}-{rodada}")
    ps = [subprocess.Popen([sys.executable, proxy, fake, "--acp"], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                           stderr=subprocess.PIPE, env=env, text=True) for _ in range(6)]
    init = json.dumps({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {}}) + "\n"
    for p in ps:  # todos já subiram juntos no Popen; a corrida é na partida
        out, err = p.communicate(input=init, timeout=30)
        if '"result"' not in out:
            raise SystemExit(f"FAIL: proxy concorrente caiu (rodada {rodada}): {err.strip().splitlines()[-1:]}")
print("  ok: 6 proxies ao mesmo tempo na mesma pasta, nenhum cai")
PY

# Um modelo só: nada a multiplexar, o proxy vira o próprio qwen.
cat > "$HOME/.qwen/settings.json" <<JSON
{"model": {"name": "$P/qwen4-max-preview"}, "providers": {"$P": {"models": [{"model": "qwen4-max-preview"}]}}}
JSON
saida=$(printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' |
    python3 -I "$ROOT/mcp/qwen-acp-proxy.py" "$FAKE" --acp)
[[ "$saida" == '{"jsonrpc": "2.0", "id": 1, "result": {"protocolVersion": 1}}' ]] ||
    { echo "FAIL: com um modelo só deveria rodar o qwen direto: $saida" >&2; exit 1; }
echo "  ok: um modelo só → qwen direto"

echo "PASS: qwen-acp-proxy"
