#!/usr/bin/env bash
# collect.sh — imprime o relatório do último run, ou de um run informado
#   uso: ai o collect [<run-dir>]
set -euo pipefail
HOME_DIR="${AI_ORCHESTRATION_HOME:-${HOME}/.ai-orchestration}"
RUNS="${HOME_DIR}/runs"

target="${1:-}"
if [[ -z "$target" ]]; then
  target=$(ls -td "$RUNS"/*/ 2>/dev/null | head -1 || true)
fi
[[ -n "$target" && -d "$target" ]] || { echo "Nenhum run encontrado em $RUNS" >&2; exit 1; }

report="${target%/}/report.md"
if [[ -f "$report" ]]; then
  cat "$report"
else
  echo "report.md ausente em $target; concatenando saídas:" >&2
  for f in "${target%/}"/[0-9]*-*.md; do
    [[ -f "$f" ]] && { echo "## $(basename "$f")"; cat "$f"; echo; }
  done
fi
