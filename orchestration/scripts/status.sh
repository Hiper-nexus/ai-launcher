#!/usr/bin/env bash
# status.sh — estado da camada de orquestração (chamado por: ai o status)
set -euo pipefail
HOME_DIR="${AI_ORCHESTRATION_HOME:-${HOME}/.ai-orchestration}"
RUNS="${HOME_DIR}/runs"

echo "Camada de orquestração: ${HOME_DIR}"
echo
echo "CLIs:"
for c in codex agy claude gemini; do
  if command -v "$c" >/dev/null 2>&1; then
    printf '  \xE2\x9C\x93 %-8s %s\n' "$c" "$(command -v "$c")"
  else
    printf '  \xE2\x9C\x97 %-8s (ausente)\n' "$c"
  fi
done
echo
if [[ -d "$RUNS" ]] && [[ -n "$(ls -A "$RUNS" 2>/dev/null || true)" ]]; then
  n=$(find "$RUNS" -maxdepth 1 -mindepth 1 -type d | wc -l | tr -d ' ')
  echo "Runs registrados: $n"
  echo "Últimos 5:"
  ls -td "$RUNS"/*/ 2>/dev/null | head -5 | while read -r d; do
    meta="${d}meta.json"
    if [[ -f "$meta" ]]; then
      preset=$(grep '"preset"' "$meta" | sed 's/.*: *"\(.*\)".*/\1/')
      task=$(grep '"task"' "$meta" | sed 's/.*: *"\(.*\)".*/\1/')
      printf '  %s  [%s] %s\n' "$(basename "$d")" "$preset" "$task"
    else
      printf '  %s\n' "$(basename "$d")"
    fi
  done
else
  echo "Nenhum run ainda."
fi
