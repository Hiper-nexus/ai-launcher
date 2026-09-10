#!/usr/bin/env bash

# Yolo do Qwen Code: o qwen_launch() fazia exec puro sem flags de aprovação,
# então cada edição/comando pedia confirmação. Este teste trava que o launcher
# passa --yolo (auto-accept all) no interativo e no one-shot posicional.

set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

TEST_HOME="${TMP_DIR}/home"
FAKE_BIN="${TMP_DIR}/bin"
CAPTURE_ARGS="${TMP_DIR}/qwen-args"
mkdir -p "$TEST_HOME" "$FAKE_BIN"

cat > "${FAKE_BIN}/qwen" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
: "${CAPTURE_ARGS:?}"
printf '%s\n' "$@" > "$CAPTURE_ARGS"
SH
chmod +x "${FAKE_BIN}/qwen"

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

run_qw() {
    : > "$CAPTURE_ARGS"
    (
        cd "$ROOT"
        HOME="$TEST_HOME" \
        PATH="${FAKE_BIN}:$PATH" \
        CAPTURE_ARGS="$CAPTURE_ARGS" \
        DASHSCOPE_API_KEY="fake-key-pra-teste" \
        "$ROOT/ai" "$@" >/dev/null
    )
    tr '\n' '|' < "$CAPTURE_ARGS"
}

assert_args() {
    local expected="$1"; shift
    local got
    got=$(run_qw "$@")
    [[ "$got" == "$expected" ]] ||
        fail "ai $*: esperado '${expected}', obtido '${got}'"
}

# Interativo: com --yolo.
assert_args '--yolo|' qw
assert_args '--yolo|' qwen

# One-shot posicional: --yolo antes do prompt (qwen aceita --yolo com query,
# ao contrário do kimi que rejeita permissão + prompt).
assert_args '--yolo|refatora isso|' qw "refatora isso"

echo "PASS: yolo do qwen"
