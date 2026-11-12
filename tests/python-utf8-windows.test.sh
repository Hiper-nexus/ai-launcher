#!/usr/bin/env bash
# No Windows o stdout do Python é cp1252: um print com "→" ou "✔" morre com
# UnicodeEncodeError. O `ai qw t3` gravava o settings do T3 e quebrava no
# print final. Os heredocs rodam `python3 -I`, que ignora PYTHONUTF8 e
# PYTHONIOENCODING, então quem resolve é o wrapper python3(): no Windows ele
# liga o modo UTF-8 do Python (-X utf8). Fora do Windows nada muda.

set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=helpers/platform.sh
source "${ROOT}/tests/helpers/platform.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }

modo=$(AI_OS_CACHE=windows python3 -I -c 'import sys; print(sys.flags.utf8_mode)')
[[ "$modo" == 1 ]] || fail "no Windows o python3 -I deveria rodar em modo UTF-8 (veio utf8_mode=$modo)"

saida=$(AI_OS_CACHE=windows python3 -I - <<'PY'
import sys
print(sys.stdout.encoding.lower().replace("-", ""), "→ ✔")
PY
)
[[ "$saida" == "utf8 → ✔" ]] || fail "print com → no Windows: '$saida'"
echo "  ok: Windows → python3 -I em UTF-8 (print com → não quebra)"

if [[ "$(ai_os)" != windows ]]; then
    AI_OS_CACHE=""
    modo=$(python3 -I -c 'import sys; print(sys.flags.utf8_mode)')
    [[ "$modo" == 0 ]] || fail "fora do Windows o wrapper não deveria mudar o modo (utf8_mode=$modo)"
    echo "  ok: fora do Windows o python3 roda como antes"
fi

echo "PASS: python3 em UTF-8 no Windows"
