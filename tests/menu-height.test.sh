#!/usr/bin/env bash

# O menu tem de mostrar o grupo CLAUDE CODE sem rolar. Em 04/11/2026, numa janela
# de 57 linhas, as 78 linhas impressas empurravam os grupos do topo para fora da
# tela e o Hy4 (item 8) parecia não existir. A lista de flags só entra quando o
# menu inteiro cabe; ela segue disponível no Toggle Flags.

set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

TEST_HOME="${TMP_DIR}/home"
mkdir -p "${TEST_HOME}/.local/share/ai-launcher"

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "  ok: $*"; }

# Abre o menu num pty do tamanho pedido e devolve só o que fica na tela.
visible_menu() {
    local rows="$1"
    TEST_HOME="$TEST_HOME" ROOT="$ROOT" python3 - "$rows" <<'PY'
import fcntl, os, pty, re, select, struct, subprocess, sys, termios, time

rows = int(sys.argv[1])
master, slave = pty.openpty()
fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", rows, 120, 0, 0))
env = os.environ.copy()
env["HOME"] = os.environ["TEST_HOME"]
env["TERM"] = "xterm-256color"
env.pop("LINES", None)
env.pop("COLUMNS", None)
proc = subprocess.Popen([os.environ["ROOT"] + "/ai"], stdin=slave, stdout=slave,
                        stderr=slave, env=env, cwd=os.environ["ROOT"])
os.close(slave)
buf = b""
end = time.time() + 25
while time.time() < end and b"Escolha [" not in buf:
    if select.select([master], [], [], 0.2)[0]:
        try:
            buf += os.read(master, 65536)
        except OSError:
            break
if b"Escolha [" not in buf:
    proc.kill()
    sys.exit("o menu não chegou ao prompt")
os.write(master, b"0\n")
try:
    proc.wait(timeout=8)
except subprocess.TimeoutExpired:
    proc.kill()
text = re.sub(r"\x1b\[[0-9;?]*[A-Za-z]", "", buf.decode(errors="replace")).replace("\r", "")
print("\n".join(text.split("\n")[-rows:]))
PY
}

echo "── 1. janela de 57 linhas: CLAUDE CODE aparece sem rolar"
screen=$(visible_menu 57)
[[ "$screen" == *"CLAUDE CODE"* ]] || fail "o grupo CLAUDE CODE rolou para fora da tela"
[[ "$screen" == *"Hy4 Tencent"* ]] || fail "o Hy4 rolou para fora da tela"
[[ "$screen" != *"FLAGS"* ]] || fail "a lista de flags ainda ocupa a tela"
[[ "$screen" == *"Toggle Flags"* ]] || fail "sumiu o caminho para ver as flags"
ok "57 linhas: Hy4 visível, flags recolhidas"

echo "── 2. janela alta: a lista de flags continua aparecendo"
screen=$(visible_menu 90)
[[ "$screen" == *"FLAGS"* ]] || fail "a lista de flags sumiu mesmo cabendo"
[[ "$screen" == *"CLAUDE CODE"* ]] || fail "CLAUDE CODE fora da tela em janela alta"
ok "90 linhas: flags e topo visíveis"

echo "PASS: menu-height (CLAUDE CODE visível sem rolar)"
