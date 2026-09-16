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

# O bloco é auto-contido de propósito: dá para exercitá-lo sem rodar o
# dispatch do launcher, que abriria o menu interativo.
PLATFORM_LIB="${TMP_DIR}/platform.sh"
sed -n '/^# ── Camada de plataforma/,/^# ── Providers alternativos/p' "$ROOT/ai" \
    | sed '$d' > "$PLATFORM_LIB"
grep -q '^ai_python()' "$PLATFORM_LIB" ||
    fail "não consegui extrair a camada de plataforma do ai"

# shellcheck source=/dev/null
source "$PLATFORM_LIB"

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
[[ "$resolved" == "python" ]] ||
    fail "ai_python escolheu '$resolved'; o stub da Store deveria ser rejeitado"

# Sem nenhum Python utilizável, tem que falhar — não devolver o stub.
EMPTY_BIN="${TMP_DIR}/empty"
mkdir -p "$EMPTY_BIN"
cp "${FAKE_BIN}/python3" "${EMPTY_BIN}/python3"
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

if [[ "$(ai_os)" == "windows" ]]; then
    # No NTFS o bit POSIX é inútil; o que vale é a ACL. Só `chmod 600` deixa
    # para trás tudo que foi herdado — numa máquina real isso incluía um grupo
    # de sandbox com Modify sobre o arquivo de keys.
    acl=$(icacls.exe "$(cygpath -w "$secret")" 2>/dev/null) ||
        fail "icacls não conseguiu ler a ACL"
    # Asserção forte: depois de /inheritance:r tem que sobrar UMA ACE, a do
    # dono. Qualquer grupo herdado que sobreviva é key legível por quem não
    # devia, e o nome do grupo varia por máquina e por idioma do Windows —
    # contar ACEs é o que não depende disso.
    mapfile -t aces < <(grep -oE '[^ ]+:\([^)]*\)' <<<"$acl" || true)
    (( ${#aces[@]} == 1 )) ||
        fail "esperada 1 ACE após secure_file, obtidas ${#aces[@]}: ${aces[*]-}"
    grep -qi "${USERNAME}" <<<"${aces[0]}" ||
        fail "a única ACE não é a do dono: ${aces[0]}"
else
    perms=$(stat -c '%a' "$secret" 2>/dev/null || stat -f '%Lp' "$secret")
    [[ "$perms" == "600" ]] || fail "esperado 600, obtido $perms"
fi

# secure_file em caminho inexistente não pode abortar o launcher (set -e).
secure_file "${TMP_DIR}/nao-existe" || fail "secure_file falhou em caminho ausente"
secure_dir "${TMP_DIR}/nao-existe-dir" || fail "secure_dir falhou em caminho ausente"

echo "PASS: camada de plataforma"
