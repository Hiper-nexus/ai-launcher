#!/usr/bin/env bash
# Runner da suíte. Roda todos os tests/*.test.sh e agrega o resultado.
#
#   bash tests/run-all.sh            # roda tudo
#   bash tests/run-all.sh jev ask    # roda só os que casam com os filtros
#
# Exit code: 0 se todos passarem, 1 se algum falhar (o que o CI usa).

set -uo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT" || exit 1

# Filtros opcionais: cada argumento é um pedaço de nome (grep -E).
FILTROS=("$@")
casa() {
    [[ ${#FILTROS[@]} -eq 0 ]] && return 0
    local f
    for f in "${FILTROS[@]}"; do
        [[ "$1" == *"$f"* ]] && return 0
    done
    return 1
}

mapfile -t ARQUIVOS < <(find tests -maxdepth 1 -name '*.test.sh' | sort)
[[ ${#ARQUIVOS[@]} -gt 0 ]] || { echo "nenhum teste encontrado em tests/"; exit 1; }

passou=0; falhou=0; pulou=0
FALHAS=()

echo "════════════════════════════════════════════════"
echo "  suíte do ai-launcher"
echo "════════════════════════════════════════════════"
echo

for t in "${ARQUIVOS[@]}"; do
    nome=$(basename "$t" .test.sh)
    if ! casa "$nome"; then
        ((pulou++))
        continue
    fi

    printf '  %-26s ' "$nome"
    # timeout portátil: `timeout` não existe no macOS de fábrica; o launcher
    # tem run_with_timeout(), mas aqui precisamos antes de qualquer coisa.
    if timeout_bin=$(command -v timeout || command -v gtimeout); then
        saida=$("$timeout_bin" 300 bash "$t" 2>&1) && rc=0 || rc=$?
    else
        saida=$(bash "$t" 2>&1) && rc=0 || rc=$?
    fi

    if [[ $rc -eq 0 ]]; then
        echo "PASS"
        ((passou++))
    else
        echo "FAIL (rc=$rc)"
        ((falhou++))
        FALHAS+=("$nome")
        # guarda a saída para o resumo (limitada, para não virar parede)
        printf '%s\n' "$saida" | tail -12 | sed 's/^/        /'
    fi
done

echo
echo "════════════════════════════════════════════════"
printf '  %d passaram · %d falharam' "$passou" "$falhou"
[[ $pulou -gt 0 ]] && printf ' · %d fora do filtro' "$pulou"
echo
if [[ $falhou -gt 0 ]]; then
    echo "  falhas: ${FALHAS[*]}"
    echo "════════════════════════════════════════════════"
    exit 1
fi
echo "════════════════════════════════════════════════"
exit 0
