#!/usr/bin/env bash

# Yolo do Kimi Code: o launcher promete modo sem aprovação, mas o --yolo do
# kimi é só "Ask When Needed" (rotina auto; ação arriscada/plano/pergunta
# ainda pede yes). O never-ask de verdade é --auto. Este teste trava que o
# modo interativo usa --auto, e que o headless omite as flags de permissão
# (kimi rejeita --auto/--yolo combinado com --prompt).

set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

TEST_HOME="${TMP_DIR}/home"
FAKE_BIN="${TMP_DIR}/bin"
CAPTURE_ARGS="${TMP_DIR}/kimi-args"
mkdir -p "$TEST_HOME" "$FAKE_BIN"

cat > "${FAKE_BIN}/kimi" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
: "${CAPTURE_ARGS:?}"
printf '%s\n' "$@" > "$CAPTURE_ARGS"
SH
chmod +x "${FAKE_BIN}/kimi"

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

run_kimi() {
    : > "$CAPTURE_ARGS"
    (
        cd "$ROOT"
        HOME="$TEST_HOME" \
        PATH="${FAKE_BIN}:$PATH" \
        CAPTURE_ARGS="$CAPTURE_ARGS" \
        "$ROOT/ai" "$@" >/dev/null
    )
    tr '\n' '|' < "$CAPTURE_ARGS"
}

assert_args() {
    local expected="$1"; shift
    local got
    got=$(run_kimi "$@")
    [[ "$got" == "$expected" ]] ||
        fail "ai $*: esperado '${expected}', obtido '${got}'"
}

# Interativo: never-ask (--auto), não o --yolo fraco (ask-when-needed).
assert_args '--auto|' kimi
assert_args '--auto|' k

# Headless: sem flags de permissão (conflitam com -p), só o prompt.
assert_args '-p|refatora isso|' kimi "refatora isso"
assert_args '-p|refatora isso|' k "refatora isso"

echo "PASS: yolo do kimi"
