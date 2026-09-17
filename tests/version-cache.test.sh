#!/usr/bin/env bash

# Cache de versões + renderização do menu.
#
# Cobre dois comportamentos:
#
#   1. Cache FRESCO (mtime < TTL) com chave FALTANDO para um comando que o menu
#      consulta: o menu tem que renderizar e mostrar '-' nesse comando, em vez
#      de morrer. O estado acontece na prática quando a lista de cmds do
#      preload_versions() e a do menu divergem (já aconteceu: 'muse' ficou fora
#      do preload), ou quando você edita o script e roda de novo dentro do TTL.
#
#      Nota de honestidade: o `|| true` que existe hoje em get_version() é
#      DEFENSIVO. O menu chama get_version via `x=$(get_version cmd)`, e o
#      errexit não atua dentro da subshell de command substitution nessa forma
#      (verificado empiricamente). Chamado no top-level, abortaria.
#
#   2. clean_version() com um `--version` fora do padrão `X.Y`: ESSE tem dentes.
#      Ela é chamada como statement puro (get_version_raw), então o grep sem
#      match abortava o shell e o job de background morria — deixando a célula
#      de versão VAZIA no menu até o TTL expirar. O assert 4 é o que pega isso.
#
# O menu exige TTY, então o teste roda sob `script(1)`, que aloca um pty.

set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

BASH_BIN="$(command -v bash)"
[[ -n "$BASH_BIN" ]] || { echo "FAIL: bash não encontrado" >&2; exit 1; }

TEST_HOME="${TMP_DIR}/home"
# TMPDIR isola o cache; o launcher usa ${TMPDIR}/ai-launcher-cache/versions.cache
TMPDIR_TEST="${TMP_DIR}/tmp"
CACHE_DIR="${TMPDIR_TEST}/ai-launcher-cache"
mkdir -p "$TEST_HOME" "$CACHE_DIR"

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "  ok: $*"; }

# Cache FRESCO (mtime agora) com APENAS a chave 'codex'. Todas as outras que o
# menu consulta (claude, gemini, kimi…) estão faltando — é exatamente o estado
# que derrubava o script.
printf 'codex=1.2.3\n' > "${CACHE_DIR}/versions.cache"

# Roda o menu num pty e manda "0" (Sair) como primeira entrada.
# TMPDIR isola o cache; HOME isola providers.conf/contas/histórico.
#
# O input é reenviado em intervalos em vez de uma vez só com sleep fixo: se o
# "0" chegar antes de o menu chamar o read(), ele é ecoado e perdido, e o menu
# fica esperando para sempre (era um flake). Reenviar dá várias chances ao
# read(), e os "0" extras depois da saída não têm efeito.
run_menu() {
    EXTRA_PATH="${1:-}"
    # $2 = "wait-cache" espera o preload (background, disparado no topo do loop
    # do menu) terminar de escrever o cache antes de mandar o "0". Sem isso o
    # menu sai antes do preload e o cache nunca aparece — era flake quando o
    # script cresceu e o preload ficou mais lento. Esperar o SINAL (o arquivo)
    # é determinístico; sleep fixo não é.
    WAIT_CACHE="${2:-no}"
    (
        if [[ "$WAIT_CACHE" == "wait-cache" ]]; then
            for _ in $(seq 1 60); do
                [[ -s "${CACHE_DIR}/versions.cache" ]] && break
                sleep 0.5
            done
            sleep 0.7
            printf '0\n'
        fi
        for _ in 1 2 3 4 5 6 7 8; do sleep 0.7; printf '0\n'; done
    ) | env -i \
        HOME="$TEST_HOME" \
        TMPDIR="$TMPDIR_TEST" \
        PATH="${EXTRA_PATH:+${EXTRA_PATH}:}$(dirname "$BASH_BIN"):/usr/bin:/bin:/usr/sbin:/sbin" \
        TERM="${TERM:-xterm}" \
        script -q /dev/null "$BASH_BIN" "$ROOT/ai" 2>&1 || true
}

echo "── menu com cache fresco faltando chaves"
out=$(run_menu)

# 1. o menu TEM que ter sido renderizado (é o que o bug impedia)
echo "$out" | grep -q "Sair" \
    || fail "o menu não foi renderizado — morreu antes. Saída: $(echo "$out" | head -5)"
ok "menu renderizou (não abortou)"

# 2. a coluna de versão do codex (que ESTÁ no cache) tem que mostrar o valor
echo "$out" | grep -q "1\.2\.3" \
    || fail "versão do codex não apareceu — cache não foi lido. Saída: $(echo "$out" | head -10)"
ok "versão do codex veio do cache (1.2.3)"

# 3. a chave ausente vira '-' em vez de matar o script
echo "$out" | grep -qE "Claude Code.*-" \
    || fail "o comando sem chave no cache deveria mostrar '-'. Saída: $(echo "$out" | head -10)"
ok "chave ausente no cache virou '-' (o fallback agora é alcançável)"

# 4. e o menu saiu direito
echo "$out" | grep -q "Saindo" \
    || fail "não chegou no 'Saindo.' do 0) Sair"
ok "saiu pelo 0) Sair"

# Controle: cache AUSENTE também tem que renderizar (o caminho antigo, que já
# funcionava — garante que a correção não quebrou o caso normal).
echo
echo "── controle: sem cache nenhum"
rm -f "${CACHE_DIR}/versions.cache"
out=$(run_menu)
echo "$out" | grep -q "Sair" || fail "sem cache também deveria renderizar o menu. Saída: $(echo "$out" | head -5)"
echo "$out" | grep -q "Saindo" || fail "sem cache: não chegou no 'Saindo.'"
ok "sem cache: menu renderiza e sai normalmente"

# ── 4. clean_version com --version fora do padrão X.Y ────
# ESTE é o assert que pega o bug de verdade: clean_version é chamada como
# statement puro, então o grep sem match abortava o shell, o job de background
# de get_version_raw morria, e o arquivo (já pré-criado pelo `>` da linha do
# preload) ficava VAZIO — menu mostrando célula em branco por 5 min.
echo
echo "── clean_version com --version fora do padrão X.Y"
FAKE_BIN="${TMP_DIR}/bin"
mkdir -p "$FAKE_BIN"
cat > "${FAKE_BIN}/gemini" <<'SH'
#!/usr/bin/env bash
# sem padrão X.Y de propósito: é o caso que derrubava o job de background
echo "gemini-cli sem-versao-legivel"
SH
chmod +x "${FAKE_BIN}/gemini"

# O lock TAMBÉM precisa sair: as execuções anteriores do menu podem ter sido
# interrompidas no meio do preload, e um lock com menos de 1 min faz o
# preload_versions() retornar cedo ("já tem um em andamento") sem escrever nada.
rm -f "${CACHE_DIR}/versions.cache" "${CACHE_DIR}/versions.cache.lock"
out=$(run_menu "$FAKE_BIN" wait-cache)

[[ -f "${CACHE_DIR}/versions.cache" ]] || fail "o preload não escreveu o cache"
gem=$(grep -E "^gemini=" "${CACHE_DIR}/versions.cache" || true)
[[ -n "$gem" ]] || fail "não há linha gemini= no cache"
[[ "$gem" != "gemini=" ]] \
    || fail "célula VAZIA no cache — o job de background morreu (bug do clean_version): $gem"
echo "$gem" | grep -q "sem-versao-legivel" \
    || fail "deveria ter caído no fallback (texto cru), veio: $gem"
ok "cache guardou o texto cru em vez de morrer: ${gem#gemini=}"

echo
echo "PASS: version-cache (7/7)"
