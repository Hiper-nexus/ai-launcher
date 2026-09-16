#!/usr/bin/env bash
# Carrega a camada de plataforma do `ai` dentro de um teste.
#
# O `ai` é distribuído como script único (o install.sh baixa um arquivo só para
# ~/.local/bin/ai), então a camada não pode virar um lib/ que ele sourceia. Os
# testes extraem o bloco em vez de duplicar a lógica — se ele mudar de forma,
# a extração falha alto aqui em vez de silenciosamente testar outra coisa.
#
# Uso:
#   source "${ROOT}/tests/helpers/platform.sh"
#
# Depois disso o teste tem ai_os/secure_file/ai_python e, principalmente, o
# wrapper python3() — sem ele, no Windows os heredocs Python dos testes caem no
# App Execution Alias da Microsoft Store e morrem com exit 49.

ai_platform_load() {
    local root="${1:-${ROOT:-}}"
    [[ -n "$root" ]] || { echo "ai_platform_load: ROOT não definido" >&2; return 1; }

    local lib
    lib=$(mktemp) || return 1
    sed -n '/^# ── Camada de plataforma/,/^# ── Providers alternativos/p' "${root}/ai" \
        | sed '$d' > "$lib"

    if ! grep -q '^ai_python()' "$lib"; then
        rm -f "$lib"
        echo "ai_platform_load: não achei a camada de plataforma em ${root}/ai" >&2
        return 1
    fi

    # shellcheck source=/dev/null
    source "$lib"
    rm -f "$lib"
}

ai_platform_load "${ROOT:-}"

# Afirma que um arquivo que carrega segredo está restrito ao dono.
#
# No POSIX isso é o modo 600. No NTFS o modo é decorativo — `stat` devolve 644
# mesmo depois de um chmod bem-sucedido —, então o que vale é a ACL: depois de
# /inheritance:r tem que sobrar uma ACE só, a do dono. Contar ACEs em vez de
# procurar nomes de grupo é o que não depende de máquina nem do idioma do
# Windows.
#
# Ecoa o motivo em stderr e devolve 1; quem chama decide como falhar.
assert_secret_file() {
    local target="$1"

    if [[ ! -f "$target" ]]; then
        echo "assert_secret_file: ${target} não existe" >&2
        return 1
    fi

    if [[ "$(ai_os)" != "windows" ]]; then
        local perms
        perms=$(stat -c '%a' "$target" 2>/dev/null || stat -f '%Lp' "$target")
        [[ "$perms" == "600" ]] && return 0
        echo "assert_secret_file: ${target} deveria ser 600, obtido ${perms}" >&2
        return 1
    fi

    local acl
    if ! acl=$(icacls.exe "$(cygpath -w "$target")" 2>/dev/null); then
        echo "assert_secret_file: icacls não leu a ACL de ${target}" >&2
        return 1
    fi

    local -a aces
    mapfile -t aces < <(grep -oE '[^ ]+:\([^)]*\)' <<<"$acl" || true)
    if (( ${#aces[@]} != 1 )); then
        echo "assert_secret_file: ${target} com ${#aces[@]} ACEs (esperada 1): ${aces[*]-}" >&2
        return 1
    fi
    if ! grep -qi "${USERNAME}" <<<"${aces[0]}"; then
        echo "assert_secret_file: a única ACE de ${target} não é a do dono: ${aces[0]}" >&2
        return 1
    fi
    return 0
}

# Carrega o cofre de segredos (secret_has/get/set/delete) e as constantes de
# conta que ele usa. Separado de ai_platform_load porque as constantes derivam
# de $HOME: o teste define HOME primeiro para o cofre cair dentro do TMP_DIR.
ai_secrets_load() {
    local root="${1:-${ROOT:-}}"
    [[ -n "$root" ]] || { echo "ai_secrets_load: ROOT não definido" >&2; return 1; }

    local lib
    lib=$(mktemp) || return 1
    # O `q` fecha no PRIMEIRO fim de range. "# ── Contas Claude" aparece duas
    # vezes no arquivo; sem ele o sed reabre o range na segunda ocorrência e
    # despeja o launcher inteiro — e sourcear isso executa o dispatch.
    sed -n '/^# ── Contas Claude/,/^# ── GLM (Z.ai)/p; /^# ── GLM (Z.ai)/q' "${root}/ai" \
        | sed '$d' > "$lib"

    if ! grep -q '^secret_set()' "$lib"; then
        rm -f "$lib"
        echo "ai_secrets_load: não achei o cofre de segredos em ${root}/ai" >&2
        return 1
    fi

    # shellcheck source=/dev/null
    source "$lib"
    rm -f "$lib"
}
