#!/usr/bin/env bash

# Dispatch do DeepSeek Harness (dsh). O ponto delicado: o dsh não tem flag de
# prompt nem subcomando 'run' — o one-shot é um PERFIL
# ('dsh --profile headless "msg"'), e 'web' é o único alias de perfil que a
# CLI reconhece como subcomando. Sem tradução, 'dsh "msg"' morre com
# "--profile <name> is required". Este teste trava a tradução e o passthrough.

set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

TEST_HOME="${TMP_DIR}/home"
FAKE_BIN="${TMP_DIR}/bin"
CAPTURE_ARGS="${TMP_DIR}/dsh-args"
CAPTURE_ENV="${TMP_DIR}/dsh-env"
mkdir -p "$TEST_HOME/.local/share/ai-launcher" "$FAKE_BIN"

# providers.conf com a key do slot 'deepseek' — a mesma que o 'ai ds' usa.
printf 'deepseek=sk-teste-123\n' > "$TEST_HOME/.local/share/ai-launcher/providers.conf"
chmod 600 "$TEST_HOME/.local/share/ai-launcher/providers.conf"

cat > "${FAKE_BIN}/dsh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
: "${CAPTURE_ARGS:?}"
printf '%s\n' "$@" > "$CAPTURE_ARGS"
printf '%s\n' "${DEEPSEEK_API_KEY:-}" "${DSH_TELEMETRY_DISABLED:-}" > "${CAPTURE_ENV:-/dev/null}"
# Payload determinístico: o caso do --dump-config exige stdout SÓ com isto.
printf '{"dsh":"stub"}\n'
SH
chmod +x "${FAKE_BIN}/dsh"

fail() { echo "FAIL: $*" >&2; exit 1; }

run_dsh() {
    : > "$CAPTURE_ARGS"
    (
        cd "$ROOT"
        HOME="$TEST_HOME" \
        PATH="${FAKE_BIN}:$PATH" \
        CAPTURE_ARGS="$CAPTURE_ARGS" \
        CAPTURE_ENV="$CAPTURE_ENV" \
        DEEPSEEK_API_KEY="" \
        "$ROOT/ai" "$@" >/dev/null
    )
    tr '\n' '|' < "$CAPTURE_ARGS"
}

assert_args() {
    local expected="$1"; shift
    local got
    got=$(run_dsh "$@")
    [[ "$got" == "$expected" ]] ||
        fail "ai $*: esperado '${expected}', obtido '${got}'"
}

# Sem argumento: a UI web, que é o modo padrão do produto.
assert_args 'web|' dsh
assert_args 'web|' harness

# Com prompt: one-shot no perfil headless, com o prompt como UM argumento.
assert_args '--profile|headless|roda os testes|' dsh "roda os testes"
assert_args '--profile|headless|roda os testes|' dsh roda os testes

# Atalho de perfil: 'headless'/'tui' viram --profile <nome> e o resto segue.
assert_args '--profile|headless|job|' dsh headless "job"
assert_args '--profile|tui|--resume|abc|' dsh tui --resume abc

# 'web' é subcomando nativo: passa verbatim, com as flags do app web junto.
assert_args 'web|--port|8080|' dsh web --port 8080

# --profile/--patch explícitos são gramática do dsh: passam verbatim.
assert_args '--profile|tui|--resume|abc|' dsh --profile tui --resume abc

# Qualquer OUTRA flag também é gramática do dsh, não prompt. Virando prompt,
# 'ai dsh --resume abc123' abriria uma sessão nova (cobrada) com o texto
# "--resume abc123" em vez de retomar a antiga — silenciosamente.
assert_args '--resume|abc123|' dsh --resume abc123
assert_args '--port|8080|'     dsh --port 8080

# Gerência e informativas passam verbatim e não viram prompt.
assert_args 'plugin|--profile|tui|add|@algum/plugin|' dsh plugin --profile tui add @algum/plugin
assert_args '--version|' dsh --version
assert_args '--help|'    dsh --help
assert_args '--dump-config|' dsh --dump-config

# A key sai do providers.conf para o ambiente do processo (o dsh lê env antes
# de qualquer arquivo), e a telemetria entra desligada por padrão.
run_dsh dsh "oi" >/dev/null
got_env=$(tr '\n' '|' < "$CAPTURE_ENV")
[[ "$got_env" == 'sk-teste-123|1|' ]] ||
    fail "env repassada ao dsh: esperado 'sk-teste-123|1|', obtido '${got_env}'"

# Sem key e sem TTY: erro claro em vez de abrir sessão que falharia na API.
NO_KEY_HOME="${TMP_DIR}/home-sem-key"
mkdir -p "$NO_KEY_HOME"
set +e
out=$(cd "$ROOT" && HOME="$NO_KEY_HOME" PATH="${FAKE_BIN}:$PATH" \
      CAPTURE_ARGS="$CAPTURE_ARGS" DEEPSEEK_API_KEY="" \
      "$ROOT/ai" dsh "tarefa" 2>&1 </dev/null)
rc=$?
set -e
[[ $rc -ne 0 ]] || fail "sem key deveria falhar, mas saiu 0"
grep -q "ai p add deepseek" <<<"$out" ||
    fail "sem key: faltou a dica 'ai p add deepseek' na saída: ${out}"

# ...mas uma informativa continua funcionando sem key nenhuma.
: > "$CAPTURE_ARGS"
(cd "$ROOT" && HOME="$NO_KEY_HOME" PATH="${FAKE_BIN}:$PATH" \
    CAPTURE_ARGS="$CAPTURE_ARGS" DEEPSEEK_API_KEY="" \
    "$ROOT/ai" dsh --version >/dev/null)
got=$(tr '\n' '|' < "$CAPTURE_ARGS")
[[ "$got" == '--version|' ]] || fail "ai dsh --version sem key: obtido '${got}'"

# ── informativa não pode passar pelo picker de repo ───────
# 'ai dsh --dump-config' é lido por máquina. Fora de um repo git e com TTY, o
# picker escreveria prosa em português no stdout e travaria esperando um
# caminho — antes de o dsh sequer rodar. Provar isso exige um pty, então o caso
# depende de python3; sem ele fica registrado como pulado, não passa de graça.
NOT_A_REPO="${TMP_DIR}/fora-de-repo"
mkdir -p "$NOT_A_REPO"
if command -v python3 >/dev/null 2>&1; then
    cat > "${TMP_DIR}/pty-run.py" <<'PYEOF'
import os, pty, subprocess, sys

master, slave = pty.openpty()  # stdin vira TTY: o picker se acharia no direito de perguntar
try:
    proc = subprocess.Popen(
        [os.environ["AI_BIN"], "dsh", "--dump-config"],
        stdin=slave, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
        cwd=os.environ["WORKDIR"], env=os.environ.copy(),
    )
    try:
        out, _ = proc.communicate(timeout=30)
    except subprocess.TimeoutExpired:
        proc.kill()
        print("TIMEOUT-BLOQUEADO-NO-PROMPT")
        sys.exit(0)
finally:
    os.close(master)
    os.close(slave)
sys.stdout.write(out.decode(errors="replace"))
PYEOF
    : > "$CAPTURE_ARGS"
    out=$(HOME="$TEST_HOME" PATH="${FAKE_BIN}:$PATH" CAPTURE_ARGS="$CAPTURE_ARGS" \
          CAPTURE_ENV="$CAPTURE_ENV" DEEPSEEK_API_KEY="" \
          AI_BIN="$ROOT/ai" WORKDIR="$NOT_A_REPO" \
          python3 "${TMP_DIR}/pty-run.py")
    [[ "$out" == '{"dsh":"stub"}' ]] ||
        fail "ai dsh --dump-config fora de repo: stdout deveria ser só o payload, veio '${out}'"
    got=$(tr '\n' '|' < "$CAPTURE_ARGS")
    [[ "$got" == '--dump-config|' ]] ||
        fail "ai dsh --dump-config fora de repo: args '${got}'"
else
    echo "SKIP: caso do picker de repo (precisa de python3 para o pty)"
fi

# ── ordem de resolução do binário ────────────────────────
# Sem 'dsh' no PATH, o launcher precisa cair no pnpm ANTES do npx: a árvore do
# dsh (~500 pacotes com versões rc) faz o resolvedor do npm engasgar por
# dezenas de minutos, enquanto o pnpm resolve em segundos.
ONLY_PNPM="${TMP_DIR}/only-pnpm"
ONLY_NPX="${TMP_DIR}/only-npx"
mkdir -p "$ONLY_PNPM" "$ONLY_NPX"
for bin in "${ONLY_PNPM}/pnpm" "${ONLY_NPX}/npx"; do
    cat > "$bin" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
: "${CAPTURE_ARGS:?}"
printf '%s\n' "$@" > "$CAPTURE_ARGS"
SH
    chmod +x "$bin"
done

run_with_path() {
    local bindir="$1"; shift
    : > "$CAPTURE_ARGS"
    (
        cd "$ROOT"
        HOME="$TEST_HOME" \
        PATH="${bindir}:/usr/bin:/bin" \
        CAPTURE_ARGS="$CAPTURE_ARGS" \
        DEEPSEEK_API_KEY="" \
        "$ROOT/ai" "$@" >/dev/null 2>&1
    )
    tr '\n' '|' < "$CAPTURE_ARGS"
}

got=$(run_with_path "$ONLY_PNPM" dsh "tarefa")
[[ "$got" == 'dlx|@deepseek-ai/dsh@latest|--profile|headless|tarefa|' ]] ||
    fail "sem dsh no PATH deveria usar 'pnpm dlx', obtido '${got}'"

got=$(run_with_path "$ONLY_NPX" dsh "tarefa")
[[ "$got" == '-y|@deepseek-ai/dsh@latest|--profile|headless|tarefa|' ]] ||
    fail "sem dsh e sem pnpm deveria cair no npx, obtido '${got}'"

# O aviso do fallback é conselho, não resultado: sai em stderr, senão entra no
# meio de um '--dump-config' redirecionado para arquivo.
: > "$CAPTURE_ARGS"
stdout_only=$(cd "$ROOT" && HOME="$TEST_HOME" PATH="${ONLY_NPX}:/usr/bin:/bin" \
    CAPTURE_ARGS="$CAPTURE_ARGS" DEEPSEEK_API_KEY="" \
    "$ROOT/ai" dsh --version 2>/dev/null)
[[ "$stdout_only" != *"pnpm"* && "$stdout_only" != *"Instale"* ]] ||
    fail "aviso do fallback npx vazou para o stdout: '${stdout_only}'"

# AI_DSH_PKG fixa a versão que o dlx baixa.
: > "$CAPTURE_ARGS"
(cd "$ROOT" && HOME="$TEST_HOME" PATH="${ONLY_PNPM}:/usr/bin:/bin" \
    CAPTURE_ARGS="$CAPTURE_ARGS" DEEPSEEK_API_KEY="" \
    AI_DSH_PKG="@deepseek-ai/dsh@0.1.1-rc.2" \
    "$ROOT/ai" dsh "tarefa" >/dev/null 2>&1)
got=$(tr '\n' '|' < "$CAPTURE_ARGS")
[[ "$got" == 'dlx|@deepseek-ai/dsh@0.1.1-rc.2|--profile|headless|tarefa|' ]] ||
    fail "AI_DSH_PKG deveria trocar o pacote, obtido '${got}'"

echo "PASS: dispatch do dsh"
