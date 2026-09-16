#!/usr/bin/env bash
# Camada de plataforma: as três suposições POSIX que falham em silêncio no
# Windows (permissão, Python, sistema operacional).

set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

# O bloco é exercitado sem rodar o dispatch do launcher, que abriria o menu
# interativo.
# shellcheck source=helpers/platform.sh
source "${ROOT}/tests/helpers/platform.sh"

# ── ai_os ────────────────────────────────────────────────
case "$(ai_os)" in
    macos|windows|linux|wsl|unknown) ;;
    *) fail "ai_os devolveu valor desconhecido: $(ai_os)" ;;
esac

# Git Bash reporta cygwin em alguns builds e msys em outros; os dois são
# Windows. Uma regressão aqui volta a silenciar o icacls.
for fake_ostype in msys cygwin msys2 win32; do
    AI_OS_CACHE="" OSTYPE="$fake_ostype" ai_os_result=$(OSTYPE="$fake_ostype" AI_OS_CACHE="" ai_os)
    [[ "$ai_os_result" == "windows" ]] ||
        fail "OSTYPE=$fake_ostype deveria ser windows, veio '$ai_os_result'"
done

# ── ai_python ────────────────────────────────────────────
# Regressão central: o alias da Microsoft Store existe no PATH, responde a
# `command -v` e falha só ao executar. Um guard por presença o aprova.
FAKE_BIN="${TMP_DIR}/bin"
mkdir -p "$FAKE_BIN"

cat > "${FAKE_BIN}/python3" <<'SH'
#!/bin/sh
echo "Python was not found; run without arguments to install from the Microsoft Store" >&2
exit 49
SH
cat > "${FAKE_BIN}/python" <<'SH'
#!/bin/sh
exit 0
SH
chmod +x "${FAKE_BIN}/python3" "${FAKE_BIN}/python"

resolved=$(AI_PYTHON_CACHE="" PATH="${FAKE_BIN}" ai_python) ||
    fail "ai_python não achou o python funcional ao lado do stub"
[[ "$(basename "$resolved")" == "python" ]] ||
    fail "ai_python escolheu '$resolved'; o stub da Store deveria ser rejeitado"

# O wrapper python3() tem que executar o interpretador resolvido, não o stub.
# Sem isso os ~40 call sites continuariam caindo no alias da Store.
cat > "${FAKE_BIN}/python" <<'SH'
#!/bin/sh
echo "python-real-ok"
SH
chmod +x "${FAKE_BIN}/python"
saida=$(AI_PYTHON_CACHE="" PATH="${FAKE_BIN}" python3 -c 'qualquer coisa') ||
    fail "wrapper python3() falhou onde o interpretador real funciona"
[[ "$saida" == "python-real-ok" ]] ||
    fail "wrapper python3() não usou o interpretador resolvido: '$saida'"

# Só o stub no PATH: nem ai_python nem o wrapper podem aceitá-lo. O wrapper
# precisa falhar explícito, não estourar um erro obscuro de heredoc adiante.
EMPTY_BIN="${TMP_DIR}/empty"
mkdir -p "$EMPTY_BIN"
cp "${FAKE_BIN}/python3" "${EMPTY_BIN}/python3"
if AI_PYTHON_CACHE="" PATH="${EMPTY_BIN}" python3 -c 'x' >/dev/null 2>&1; then
    fail "wrapper python3() deveria falhar quando só há o stub da Store"
fi
if AI_PYTHON_CACHE="" PATH="${EMPTY_BIN}" ai_python >/dev/null 2>&1; then
    fail "ai_python aceitou o stub quando não havia Python real"
fi

# ── secure_file ──────────────────────────────────────────
secret="${TMP_DIR}/providers.conf"
printf 'sakana=chave-de-teste\n' > "$secret"
secure_file "$secret"
[[ -f "$secret" ]] || fail "secure_file destruiu o arquivo"
grep -q '^sakana=chave-de-teste$' "$secret" ||
    fail "secure_file corrompeu o conteúdo"

assert_secret_file "$secret" || fail "secure_file não restringiu o arquivo ao dono"

# Contraprova: só `chmod 600` — o que o launcher fazia antes — tem que ser
# REPROVADO no Windows. Sem isto o teste passaria mesmo se secure_file virasse
# um no-op, que é exatamente o modo como o bug original passava despercebido.
frouxo="${TMP_DIR}/frouxo.conf"
printf 'k=v\n' > "$frouxo"
chmod 600 "$frouxo"
if [[ "$(ai_os)" == "windows" ]]; then
    if assert_secret_file "$frouxo" 2>/dev/null; then
        fail "assert_secret_file aprovou um arquivo protegido só por chmod"
    fi
fi

# secure_file em caminho inexistente não pode abortar o launcher (set -e).
secure_file "${TMP_DIR}/nao-existe" || fail "secure_file falhou em caminho ausente"
secure_dir "${TMP_DIR}/nao-existe-dir" || fail "secure_dir falhou em caminho ausente"

echo "PASS: camada de plataforma"
