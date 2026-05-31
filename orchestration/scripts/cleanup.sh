#!/usr/bin/env bash
# cleanup.sh — remove runs antigos, mantendo os N mais recentes (default 20)
#   uso: ai o cleanup [N]
set -euo pipefail
HOME_DIR="${AI_ORCHESTRATION_HOME:-${HOME}/.ai-orchestration}"
RUNS="${HOME_DIR}/runs"
KEEP="${1:-20}"

[[ -d "$RUNS" ]] || { echo "Nada a limpar ($RUNS não existe)."; exit 0; }

i=0; removed=0
while read -r d; do
  [[ -n "$d" ]] || continue
  i=$((i+1))
  if [[ "$i" -gt "$KEEP" ]]; then
    rm -rf "$d" && removed=$((removed+1))
  fi
done < <(ls -td "$RUNS"/*/ 2>/dev/null)

echo "Mantidos: até $KEEP mais recentes. Removidos: $removed."
