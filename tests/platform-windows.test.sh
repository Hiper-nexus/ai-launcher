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

# Arquivo Windows-only: o que ele exercita (wrapper .cmd via cmd.exe, icacls,
# caminhos do perfil do Windows) não existe em macOS/Linux. Sem esta guarda,
# essas asserções falham por AMBIENTE e não por regressão — o que fazia a
# suíte reprovar fora do Windows e inutilizava o runner como sinal de CI.
#
# Rodar só no Windows é o escopo correto deste arquivo. Nota: as partes
# independentes de plataforma (classificação do ai_os por OSTYPE, por
# exemplo) ficam sem cobertura fora do Windows por causa desta guarda.
if [[ "$(ai_os)" != "windows" ]]; then
    echo "  (pulado: $(ai_os) não é Windows; este arquivo testa o Windows)"
    exit 0
fi

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

# ── win_bin_path ─────────────────────────────────────────
# cursor-agent instala só cursor-agent.cmd e cursor-agent.ps1; sem isto ele
# fica invisível ao launcher para sempre, mesmo instalado e funcionando.
WRAP_BIN="${TMP_DIR}/wrappers"
mkdir -p "$WRAP_BIN"
: > "${WRAP_BIN}/soh-cmd.cmd"
: > "${WRAP_BIN}/soh-ps1.ps1"
: > "${WRAP_BIN}/soh-exe.exe"

for nome in soh-cmd soh-ps1 soh-exe; do
    achado=$(PATH="${WRAP_BIN}" win_bin_path "$nome") ||
        fail "win_bin_path não achou ${nome} pelo wrapper"
    [[ "$achado" == "${WRAP_BIN}/${nome}."* ]] ||
        fail "win_bin_path devolveu caminho inesperado para ${nome}: ${achado}"
done

if PATH="${WRAP_BIN}" win_bin_path nao-existe >/dev/null 2>&1; then
    fail "win_bin_path inventou um binário inexistente"
fi

# Ordem de AI_WIN_BIN_EXTS importa: .exe é o executável de verdade e tem que
# ganhar do wrapper quando os dois existem.
: > "${WRAP_BIN}/ambos.ps1"
: > "${WRAP_BIN}/ambos.exe"
achado=$(PATH="${WRAP_BIN}" win_bin_path ambos) ||
    fail "win_bin_path não achou 'ambos'"
[[ "$achado" == *".exe" ]] ||
    fail "win_bin_path preferiu o wrapper ao .exe: ${achado}"

# Fallback de PATH velho: janela aberta antes de o instalador gravar o PATH no
# registro não pode ver "não instalado" com o binário no disco.
STALE_HOME="${TMP_DIR}/stale-home"
mkdir -p "${STALE_HOME}/AppData/Local/agy/bin"
: > "${STALE_HOME}/AppData/Local/agy/bin/agy.exe"
AI_WIN_EXTRA_DIRS=()   # solta o cache: chamadas anteriores encheram com o HOME real
achado=$(HOME="$STALE_HOME" PATH="/nonexistent" win_bin_path agy) ||
    fail "win_bin_path não usou o fallback de diretório conhecido com PATH velho"
[[ "$achado" == "${STALE_HOME}/AppData/Local/agy/bin/agy.exe" ]] ||
    fail "fallback devolveu caminho inesperado: ${achado}"

# ── exec_cli ─────────────────────────────────────────────
# O bug que este bloco trava: check_installed achava o binário pelo fallback,
# mas o exec pelo nome cru morria com "devin: not found" em janela de PATH
# velho. Detecção e exec têm que usar o mesmo caminho.
# O fake mora num dos diretórios CONHECIDOS (o fallback não varre o disco
# inteiro, só onde os instaladores costumam deixar o binário).
EXEC_HOME="${TMP_DIR}/exec-home"
mkdir -p "${EXEC_HOME}/AppData/Local/agy/bin"
printf '@echo hi-from-cmd %%*\r\n' > "${EXEC_HOME}/AppData/Local/agy/bin/agy.cmd"

AI_WIN_EXTRA_DIRS=()
saida=$(HOME="$EXEC_HOME" PATH="/nonexistent:/c/WINDOWS/system32" exec_cli agy um dois </dev/null) ||
    fail "exec_cli não resolveu wrapper .cmd fora do PATH"
[[ "$saida" == "hi-from-cmd um dois" ]] ||
    fail "exec_cli não passou argumentos pelo cmd.exe: '$saida'"

# Nome no PATH continua executando direto, sem passar pelo fallback.
saida=$(exec_cli printf 'alo') || fail "exec_cli falhou para comando no PATH"
[[ "$saida" == "alo" ]] || fail "exec_cli corrompeu saída do comando no PATH"

# CLI inexistente: 127 e mensagem, não um exec vazio.
if ( exec_cli cli-fantasma >/dev/null 2>&1 ); then
    fail "exec_cli executou CLI inexistente"
fi

# ── ai_win_path / ai_posix_path ──────────────────────────
# Programa nativo não entende /c/Users/... e o Git Bash não entende C:\... .
# Quem converte é o cygpath; a conversão à mão não serve porque /tmp não é
# unidade, é um mount do MSYS para o Temp do Windows.
convertido=$(ai_win_path "$TMP_DIR") || fail "ai_win_path falhou em $TMP_DIR"
[[ "$convertido" == ?:'\'* ]] || fail "ai_win_path não devolveu caminho do Windows: $convertido"
de_volta=$(ai_posix_path "$convertido") || fail "ai_posix_path falhou em $convertido"
[[ "$de_volta" == /* ]] || fail "ai_posix_path não devolveu caminho POSIX: $de_volta"
[[ -d "$de_volta" ]] || fail "a ida e volta perdeu o diretório: $TMP_DIR → $de_volta"

# As envs do Windows chegam em formato nativo; sem conversão nenhum teste -x
# passa nelas, e era assim que o Chrome ficava "não instalado" com o binário
# no disco.
if [[ -n "${LOCALAPPDATA:-}" ]]; then
    lad=$(ai_posix_path "$LOCALAPPDATA")
    [[ -d "$lad" ]] || fail "ai_posix_path não resolveu LOCALAPPDATA: $lad"
fi

# ── ai_pid_na_porta / ai_win_proc_info ───────────────────
# A cadeia de confiança do `ai jb` se apoia nas duas: quem escuta a porta, e
# qual é o argv desse processo. No Windows nenhuma das fontes POSIX serve —
# não há lsof, e o `ps` do Git Bash só enxerga processo MSYS enquanto o PID
# vem do netstat, que é do Windows.
PY_BIN="$(ai_python)" || fail "nenhum Python utilizável"
# Porta EFÊMERA anunciada em arquivo, e não um número fixo: porta fixa colide
# com processo vivo de uma execução anterior, e aí a inspeção cai no processo
# errado. O >/dev/null é o que impede o processo de fundo de segurar o stdout
# do teste — com ele aberto, a suíte trava em vez de falhar.
cat > "${TMP_DIR}/listener.py" <<'PY'
import http.server, os
srv = http.server.HTTPServer(("127.0.0.1", 0),
                             http.server.BaseHTTPRequestHandler)
with open(os.environ["PORT_FILE"], "w") as fh:
    fh.write(str(srv.server_address[1]))
srv.serve_forever()
PY
PORT_FILE="${TMP_DIR}/porta" PYTHONIOENCODING=utf-8 \
    "$PY_BIN" "${TMP_DIR}/listener.py" --marca-do-teste=xyz >/dev/null 2>&1 &
LISTENER=$!
trap 'kill "$LISTENER" 2>/dev/null || true; rm -rf "$TMP_DIR"' EXIT

PORTA_TESTE=""
for _ in $(seq 1 60); do
    [[ -s "${TMP_DIR}/porta" ]] && { PORTA_TESTE=$(cat "${TMP_DIR}/porta"); break; }
    sleep 0.2
done
[[ -n "$PORTA_TESTE" ]] || fail "o listener de teste não subiu"

pid_achado=$(ai_pid_na_porta "$PORTA_TESTE" || true)
if [[ -z "$pid_achado" ]]; then
    kill "$LISTENER" 2>/dev/null || true
    fail "ai_pid_na_porta não achou quem escuta a ${PORTA_TESTE}"
fi
[[ "$pid_achado" =~ ^[0-9]+$ ]] || { kill "$LISTENER" 2>/dev/null; fail "PID inválido: '$pid_achado'"; }

info=$(ai_win_proc_info "$pid_achado") || {
    kill "$LISTENER" 2>/dev/null || true
    fail "ai_win_proc_info não leu o processo $pid_achado"
}
dono=$(printf '%s\n' "$info" | sed -n '1p')
argv=$(printf '%s\n' "$info" | sed -n '2p')
[[ "${dono#*|}" == "${USERNAME}" ]] || { kill "$LISTENER" 2>/dev/null; fail "dono veio '$dono', esperado ${USERNAME}"; }
[[ "$argv" == *"--marca-do-teste=xyz"* ]] || {
    kill "$LISTENER" 2>/dev/null || true
    fail "o argv não veio completo (é nele que a verificação do perfil se apoia): $argv"
}

kill "$LISTENER" 2>/dev/null || true
wait "$LISTENER" 2>/dev/null || true
trap 'rm -rf "$TMP_DIR"' EXIT

# Porta que ninguém escuta não pode inventar PID, e PID inexistente não pode
# virar "processo confiável". A porta livre é a que acabou de ser liberada:
# qualquer número fixo aqui pode estar em uso por outro programa da máquina.
sleep 0.5
[[ -z "$(ai_pid_na_porta "$PORTA_TESTE" || true)" ]] ||
    fail "ai_pid_na_porta inventou dono para porta livre"
if ai_win_proc_info 4294967000 >/dev/null 2>&1; then
    fail "ai_win_proc_info aprovou um PID inexistente"
fi
if ai_pid_na_porta "nao-e-porta" >/dev/null 2>&1; then
    fail "ai_pid_na_porta aceitou porta não numérica"
fi

# ── python3(): encoding travado em UTF-8 ─────────────────
# O Python do Windows escreve no encoding da locale (cp1252) e morria com
# UnicodeEncodeError em qualquer print com acento — "réplicas:", "confiança →".
saida=$(python3 -c 'print("confiança → ok")') ||
    fail "wrapper python3() falhou ao imprimir texto com acento"
[[ "$saida" == "confiança → ok" ]] ||
    fail "wrapper python3() corrompeu o texto: '$saida'"

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

# ── cli_install_hint ─────────────────────────────────────
# Os hints eram todos macOS/Linux. No Windows mandavam rodar `brew`, que não
# existe lá, ou `curl | bash`, que baixa instalador de binário Linux.
: "${YELLOW:=}" "${RESET:=}"

# uv não é CLI de agente: é o runner do `ai jb`. Está aqui porque o hint dele
# também era `brew install` fixo.
CLIS_COM_HINT=(claude codex gemini deepcode qodercli kimi grok opencode omp
               agy devin cursor-agent prime-agent muse ollama uv)

for cli in "${CLIS_COM_HINT[@]}"; do
    hint=$(cli_install_hint "$cli") ||
        fail "cli_install_hint não tem entrada para $cli"
    [[ -n "$hint" ]] || fail "hint vazio para $cli"

    if [[ "$(ai_os)" == "windows" ]]; then
        if grep -q "brew " <<<"$hint"; then
            fail "hint de $cli manda usar brew no Windows: $hint"
        fi
        if grep -qE "curl .*\| *(bash|sh)" <<<"$hint"; then
            fail "hint de $cli manda usar curl | bash no Windows: $hint"
        fi
    fi
done

if cli_install_hint cli-que-nao-existe >/dev/null 2>&1; then
    fail "cli_install_hint inventou hint para CLI desconhecida"
fi

echo "PASS: camada de plataforma"
