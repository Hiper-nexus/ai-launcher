#!/usr/bin/env bash

# `ai qw t3` liga o Qwen Code 1.0 no T3 Code da máquina. Este teste trava:
#  - o agente "qwen-code" do ACP Registry (que baixa o npm 0.x) é desativado,
#    não apagado;
#  - o provider local que já roda `qwen` é reaproveitado: caminho absoluto,
#    --acp garantido, args extras preservados, modelo do launcher no topo;
#  - sem provider local, cria um; rodar duas vezes não duplica nada;
#  - o resto do settings.json do T3 (outros providers, chaves) fica intacto;
#  - sem T3 ou com o Qwen 0.x, recusa e não toca em arquivo nenhum.

set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

TEST_HOME="${TMP_DIR}/home"
FAKE_BIN="${TMP_DIR}/bin"
FAKE_VERSION_FILE="${TMP_DIR}/qwen-version"
SETTINGS="${TEST_HOME}/.t3/userdata/settings.json"
MODEL="alibaba-token-plan/qwen4-max-preview"
mkdir -p "$TEST_HOME/.t3/userdata" "$FAKE_BIN"
echo "1.0.0-preview" > "$FAKE_VERSION_FILE"

cat > "${FAKE_BIN}/qwen" <<'SH'
#!/usr/bin/env bash
if [[ "${1:-}" == "--version" ]]; then cat "$FAKE_VERSION_FILE"; exit 0; fi
exit 0
SH
chmod +x "${FAKE_BIN}/qwen"

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

run_t3() {
    (
        cd "$ROOT"
        HOME="$TEST_HOME" \
        PATH="${FAKE_BIN}:$PATH" \
        FAKE_VERSION_FILE="$FAKE_VERSION_FILE" \
        "$ROOT/ai" qw t3 >/dev/null 2>&1
    )
}

json_get() {
    python3 -I -c 'import json,sys
d=json.load(open(sys.argv[1]))
for k in sys.argv[2].split("."):
    d=d[int(k)] if isinstance(d,list) else d[k]
print(json.dumps(d) if isinstance(d,(list,dict,bool)) else d)' "$SETTINGS" "$1"
}

# Como o T3 deixa o arquivo: registry do qwen ligado, um local antigo no
# `qwen` com args extras, e outro provider que não pode ser tocado.
cat > "$SETTINGS" <<'JSON'
{
  "defaultAutoPull": true,
  "providerModelPreferences": {
    "qwen_local": {"hiddenModels": [], "modelOrder": ["qwen3.8-max(openai)"]}
  },
  "providerInstances": {
    "acpRegistry_qwen_code": {"driver": "acpRegistry", "displayName": "Qwen Code", "enabled": true,
      "config": {"agentId": "qwen-code", "distribution": "auto"}},
    "qwen_local": {"driver": "acpRegistry", "displayName": "Qwen local", "enabled": true,
      "environment": [{"name": "X", "value": "", "sensitive": true}],
      "config": {"source": "local", "commandPath": "qwen", "commandArgs": ["--mcp-config", "/tmp/m.json"]}},
    "acpRegistry_kimi_cli": {"driver": "acpRegistry", "displayName": "Kimi", "enabled": true,
      "config": {"agentId": "kimi-cli", "distribution": "auto"}}
  }
}
JSON
chmod 644 "$SETTINGS"

run_t3 || fail "ai qw t3 falhou num T3 válido"

[[ "$(json_get providerInstances.acpRegistry_qwen_code.enabled)" == "false" ]] ||
    fail "o qwen-code do registry (npm 0.x) continua ligado"
[[ "$(json_get providerInstances.acpRegistry_kimi_cli.enabled)" == "true" ]] ||
    fail "desativou provider que não é o Qwen"
[[ "$(json_get providerInstances.qwen_local.config.commandPath)" == "${FAKE_BIN}/qwen" ]] ||
    fail "provider local não aponta para o caminho absoluto do qwen"
[[ "$(json_get providerInstances.qwen_local.config.commandArgs)" == '["--acp", "--mcp-config", "/tmp/m.json"]' ]] ||
    fail "args do provider local errados: $(json_get providerInstances.qwen_local.config.commandArgs)"
[[ "$(json_get providerInstances.qwen_local.enabled)" == "true" ]] || fail "provider local desligado"
[[ "$(json_get providerInstances.qwen_local.environment.0.name)" == "X" ]] ||
    fail "perdeu o environment do provider local"
[[ "$(json_get providerModelPreferences.qwen_local.modelOrder.0)" == "$MODEL" ]] ||
    fail "${MODEL} não ficou no topo do modelOrder"
[[ "$(json_get defaultAutoPull)" == "true" ]] || fail "perdeu configuração do T3 alheia ao Qwen"
perm=$(stat -f '%Lp' "$SETTINGS" 2>/dev/null || stat -c '%a' "$SETTINGS")
[[ "$perm" == "644" ]] || fail "mudou a permissão do settings.json do T3 para ${perm}"

# Idempotente: rodar de novo não duplica modelo nem --acp.
run_t3 || fail "segunda execução falhou"
[[ "$(json_get providerModelPreferences.qwen_local.modelOrder)" == "[\"${MODEL}\", \"qwen3.8-max(openai)\"]" ]] ||
    fail "modelOrder duplicou: $(json_get providerModelPreferences.qwen_local.modelOrder)"
[[ "$(json_get providerInstances.qwen_local.config.commandArgs)" == '["--acp", "--mcp-config", "/tmp/m.json"]' ]] ||
    fail "--acp duplicou na segunda execução"

# Sem provider local: cria um.
cat > "$SETTINGS" <<'JSON'
{"providerInstances": {"acpRegistry_qwen_code": {"driver": "acpRegistry", "enabled": true,
  "config": {"agentId": "qwen-code"}}}}
JSON
run_t3 || fail "ai qw t3 falhou sem provider local"
[[ "$(json_get providerInstances.qwen_local.config.source)" == "local" ]] ||
    fail "não criou o provider local"
[[ "$(json_get providerInstances.qwen_local.config.commandArgs)" == '["--acp"]' ]] ||
    fail "provider criado sem --acp"
[[ "$(json_get providerInstances.qwen_local.displayName)" == "Qwen Code 1.0" ]] ||
    fail "provider criado sem nome"

# Qwen 0.x no PATH: recusa e não mexe no arquivo.
before=$(cat "$SETTINGS")
echo "0.27.2" > "$FAKE_VERSION_FILE"
if run_t3; then fail "ai qw t3 aceitou o Qwen 0.x"; fi
[[ "$(cat "$SETTINGS")" == "$before" ]] || fail "mexeu no T3 com o Qwen 0.x"
echo "1.0.0-preview" > "$FAKE_VERSION_FILE"

# Sem T3 na máquina: erro, e não cria nada.
rm -rf "${TEST_HOME}/.t3"
if run_t3; then fail "ai qw t3 passou sem T3 instalado"; fi
[[ ! -e "$SETTINGS" ]] || fail "criou settings.json do T3 do nada"

echo "PASS: ai qw t3 (registry desligado, provider local no 1.0)"
