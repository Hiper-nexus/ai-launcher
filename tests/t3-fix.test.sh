#!/usr/bin/env bash

# `ai t3 fix`: agente do ACP Registry quebrado no T3 passa a rodar o CLI local
# quando o CLI está instalado E responde ACP. O teste trava:
#  - Devin "unprepared" + devin local que responde → entrada convertida para
#    local, mesmo id/nome/ícone/enabled;
#  - MiniMax quebrado + mcode local que NÃO responde ACP → nada muda (não
#    troca um quebrado por outro) e aparece como pendente;
#  - agente pronto (Kimi) e agente sem CLI conhecido (GLM) → intocados;
#  - Cursor com login expirado → listado com a dica de login;
#  - backup do settings.json, código de saída 1 com pendências, idempotente.

set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "  ok: $*"; }

T3="${TMP_DIR}/t3"
BIN="${TMP_DIR}/bin"
mkdir -p "$T3/userdata" "$T3/caches" "$BIN"

cat > "$T3/userdata/settings.json" <<'JSON'
{"defaultAutoPull": true, "providerInstances": {
  "acpRegistry_devin": {"driver": "acpRegistry", "displayName": "Devin", "enabled": true,
    "config": {"agentId": "devin", "distribution": "auto", "registryIconUrl": "https://x/devin.svg"}},
  "acpRegistry_minimax_code": {"driver": "acpRegistry", "displayName": "MiniMax Code", "enabled": true,
    "config": {"agentId": "minimax-code", "distribution": "auto"}},
  "acpRegistry_kimi_cli": {"driver": "acpRegistry", "displayName": "Kimi CLI", "enabled": true,
    "config": {"agentId": "kimi", "distribution": "auto"}},
  "acpRegistry_glm_agent": {"driver": "acpRegistry", "displayName": "GLM Agent", "enabled": true,
    "config": {"agentId": "glm-acp-agent", "distribution": "auto"}},
  "cursor": {"driver": "cursor", "enabled": true}
}}
JSON
chmod 644 "$T3/userdata/settings.json"
st() { printf '{"status": "%s", "message": "%s"}' "$2" "${3:-}" > "$T3/caches/$1.json"; }
st acpRegistry_devin warning "ACP Registry agent 'devin' has not been prepared on this environment."
st acpRegistry_minimax_code warning "The ACP agent could not create a test session."
st acpRegistry_kimi_cli ready
st acpRegistry_glm_agent error "boom"
st cursor error "Cursor sign-in expired or was rejected."

# devin falso que fala ACP (initialize + session/new)
cat > "$BIN/devin" <<'PY'
#!/usr/bin/env python3
import json, sys
for l in sys.stdin:
    d = json.loads(l)
    r = {"protocolVersion": 1} if d["method"] == "initialize" else {"sessionId": "s1"}
    print(json.dumps({"jsonrpc": "2.0", "id": d["id"], "result": r}), flush=True)
PY
# mcode falso quebrado (como o 0.2.7 sem better-sqlite3)
printf '#!/bin/sh\necho "Could not locate the bindings file" >&2\nexit 1\n' > "$BIN/mcode"
chmod +x "$BIN/devin" "$BIN/mcode"

roda() {
    HOME="${TMP_DIR}/home" T3CODE_HOME="$T3" PATH="${BIN}:$PATH" "$ROOT/ai" t3 fix 2>&1
}

set +e
saida=$(roda); rc=$?
set -e
[[ $rc -eq 1 ]] || fail "com pendências deveria sair 1, saiu $rc: $saida"

python3 -I - "$T3/userdata/settings.json" "$BIN/devin" <<'PY' || fail "conversão errada. Saída: $saida"
import json, sys
d = json.load(open(sys.argv[1]))
i = d["providerInstances"]
dv = i["acpRegistry_devin"]
assert dv["config"] == {"source": "local", "commandPath": sys.argv[2], "commandArgs": ["acp"],
                        "registryIconUrl": "https://x/devin.svg"}, dv
assert dv["displayName"] == "Devin" and dv["enabled"] is True, dv
assert i["acpRegistry_minimax_code"]["config"]["agentId"] == "minimax-code", "trocou MiniMax por um CLI que não responde"
assert i["acpRegistry_kimi_cli"]["config"]["agentId"] == "kimi", "mexeu no Kimi que estava pronto"
assert i["acpRegistry_glm_agent"]["config"]["agentId"] == "glm-acp-agent", "mexeu no GLM sem CLI conhecido"
assert d["defaultAutoPull"] is True, "perdeu config do T3"
PY
[[ -f "$T3/userdata/settings.json.bak-t3fix" ]] || fail "sem backup do settings.json"
perm=$(stat -f '%Lp' "$T3/userdata/settings.json" 2>/dev/null || stat -c '%a' "$T3/userdata/settings.json")
[[ "$perm" == "644" ]] || fail "permissão do settings.json mudou para $perm"
echo "$saida" | grep -q "MiniMax Code.*não respondeu ACP" || fail "MiniMax não aparece como pendente: $saida"
echo "$saida" | grep -q "Cursor.*login" || fail "Cursor sem dica de login: $saida"
ok "Devin convertido para o CLI local; MiniMax (CLI quebrado), Kimi (pronto) e GLM (sem CLI) intocados; Cursor com dica"

# Depois que o T3 rechecar, o Devin fica pronto: rodar de novo não muda nada.
st acpRegistry_devin ready
antes=$(cksum < "$T3/userdata/settings.json")
roda >/dev/null 2>&1 || true
[[ "$(cksum < "$T3/userdata/settings.json")" == "$antes" ]] || fail "segunda execução mudou o settings.json"
ok "idempotente"

# Kimi do Registry pedindo login, sem `kimi` no PATH, mas com outro provider
# local pronto do Kimi (o caso do t1): reaproveita o comando dele.
T3K="${TMP_DIR}/t3k"; mkdir -p "$T3K/userdata" "$T3K/caches"
cat > "$T3K/userdata/settings.json" <<JSON
{"providerInstances": {
  "acpRegistry_kimi_cli": {"driver": "acpRegistry", "displayName": "Kimi CLI", "enabled": true,
    "config": {"agentId": "kimi", "distribution": "auto"}},
  "kimi_code_internacional": {"driver": "acpRegistry", "enabled": true,
    "config": {"source": "local", "commandPath": "${BIN}/node-fake", "commandArgs": ["/opt/kimi-code/dist/main.mjs", "acp"]}}
}}
JSON
printf '{"status": "warning", "message": "Sign in in provider settings using Login with Kimi account."}' > "$T3K/caches/acpRegistry_kimi_cli.json"
printf '{"status": "ready"}' > "$T3K/caches/kimi_code_internacional.json"
cp "$BIN/devin" "$BIN/node-fake"
PY_DIR=$(dirname "$(command -v python3)"); BASH_DIR=$(dirname "$(command -v bash)")
HOME="${TMP_DIR}/home" T3CODE_HOME="$T3K" PATH="${BIN}:${BASH_DIR}:${PY_DIR}:/usr/bin:/bin" "$ROOT/ai" t3 fix >/dev/null 2>&1 ||
    fail "t3 fix com doador saiu com erro"
python3 -I - "$T3K/userdata/settings.json" "$BIN/node-fake" <<'PY' || fail "não reaproveitou o Kimi local"
import json, sys
c = json.load(open(sys.argv[1]))["providerInstances"]["acpRegistry_kimi_cli"]["config"]
assert c == {"source": "local", "commandPath": sys.argv[2], "commandArgs": ["/opt/kimi-code/dist/main.mjs", "acp"]}, c
PY
echo "  ok: Registry pedindo login sem CLI no PATH → reaproveita o provider local pronto do mesmo agente"

echo "PASS: ai t3 fix"
