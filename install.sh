#!/usr/bin/env bash
# Instalador do AI CLI Launcher
# Uso: curl -fsSL https://raw.githubusercontent.com/Hiper-nexus/ai-launcher/main/install.sh | bash

set -euo pipefail

BOLD='\033[1m'
GREEN='\033[32m'
YELLOW='\033[33m'
CYAN='\033[36m'
RED='\033[31m'
DIM='\033[2m'
RESET='\033[0m'

INSTALL_DIR="${AI_LAUNCHER_INSTALL_DIR:-${HOME}/.local/bin}"
REPO_RAW="${AI_LAUNCHER_REPO_RAW:-https://raw.githubusercontent.com/Hiper-nexus/ai-launcher/main}"

echo -e "${BOLD}${CYAN}"
echo "  ┌──────────────────────────────────────┐"
echo "  │   AI CLI Launcher - Instalador       │"
echo "  └──────────────────────────────────────┘"
echo -e "${RESET}"

# Criar diretório se não existir
mkdir -p "$INSTALL_DIR"

# Verificar se já está instalado (backup)
if [[ -f "${INSTALL_DIR}/ai" ]]; then
    echo -e "${YELLOW}Versão anterior encontrada. Fazendo backup...${RESET}"
    cp "${INSTALL_DIR}/ai" "${INSTALL_DIR}/ai.bak"
fi

# Baixar o script
echo -e "${GREEN}Baixando ai-launcher...${RESET}"
if command -v curl &>/dev/null; then
    if ! curl -fsSL "${REPO_RAW}/ai" -o "${INSTALL_DIR}/ai"; then
        echo -e "${RED}Erro ao baixar. Verifique sua conexão.${RESET}"
        # Restaurar backup se existir
        [[ -f "${INSTALL_DIR}/ai.bak" ]] && mv "${INSTALL_DIR}/ai.bak" "${INSTALL_DIR}/ai"
        exit 1
    fi
elif command -v wget &>/dev/null; then
    if ! wget -qO "${INSTALL_DIR}/ai" "${REPO_RAW}/ai"; then
        echo -e "${RED}Erro ao baixar. Verifique sua conexão.${RESET}"
        [[ -f "${INSTALL_DIR}/ai.bak" ]] && mv "${INSTALL_DIR}/ai.bak" "${INSTALL_DIR}/ai"
        exit 1
    fi
else
    echo -e "${RED}Erro: curl ou wget necessário.${RESET}"
    exit 1
fi

chmod +x "${INSTALL_DIR}/ai"

# Limpar backup se tudo deu certo
rm -f "${INSTALL_DIR}/ai.bak"

# Verificar se ~/.local/bin está no PATH
if ! echo "$PATH" | tr ':' '\n' | grep -q "^${HOME}/.local/bin$"; then
    echo ""
    echo -e "${YELLOW}~/.local/bin não está no PATH.${RESET}"

    # Detectar shell config
    SHELL_RC=""
    if [[ -f "${HOME}/.zshrc" ]]; then
        SHELL_RC="${HOME}/.zshrc"
    elif [[ -f "${HOME}/.bashrc" ]]; then
        SHELL_RC="${HOME}/.bashrc"
    fi

    if [[ -n "$SHELL_RC" ]]; then
        # Evitar duplicatas
        if ! grep -q 'HOME/.local/bin' "$SHELL_RC" 2>/dev/null; then
            read -rp "Adicionar ao ${SHELL_RC} automaticamente? [s/N]: " yn
            if [[ "$yn" == [sS] ]]; then
                echo '' >> "$SHELL_RC"
                echo '# AI CLI Launcher' >> "$SHELL_RC"
                echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$SHELL_RC"
                echo -e "${GREEN}Adicionado! Rode: source ${SHELL_RC}${RESET}"
            fi
        else
            echo -e "${DIM}PATH já configurado em ${SHELL_RC}, mas shell atual não carregou.${RESET}"
            echo -e "  Rode: source ${SHELL_RC}"
        fi
    else
        echo "  Adicione manualmente ao seu shell config:"
        echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
    fi
fi

# Aviso sobre bash 4+ (macOS vem com 3.2)
if (( BASH_VERSINFO[0] < 4 )); then
    _has_new_bash=false
    for _b in /opt/homebrew/bin/bash /usr/local/bin/bash /opt/local/bin/bash; do
        [[ -x "$_b" ]] && "$_b" -c '(( BASH_VERSINFO[0] >= 4 ))' 2>/dev/null && _has_new_bash=true && break
    done
    if ! "$_has_new_bash"; then
        echo ""
        echo -e "${YELLOW}⚠ Bash 4+ não encontrado. O launcher precisa de bash moderno.${RESET}"
        echo -e "  Instale via: ${BOLD}brew install bash${RESET}"
    fi
fi

echo ""
echo -e "${GREEN}Instalado com sucesso!${RESET}"
echo ""
echo "Uso:"
echo "  ai          Menu interativo"
echo "  ai c        Claude Code"
echo "  ai x        Codex"
echo "  ai fugu     Sakana Fugu"
echo "  ai fugu-ultra  Sakana Fugu Ultra V1.1"
echo "  ai fugu-cyber  Sakana Fugu Cyber (pede liberação)"
echo "  ai g        Gemini"
echo "  ai k        Kimi Code"
echo "  ai gr       Grok (xAI)"
echo "  ai --help   Ajuda completa"
echo ""
echo -e "${YELLOW}Pré-requisitos (instale os que quiser usar):${RESET}"
echo "  npm install -g @anthropic-ai/claude-code   # Claude"
echo "  npm install -g @openai/codex               # Codex"
echo "  npm install -g @google/gemini-cli           # Gemini"
echo "  curl -fsSL https://code.kimi.com/kimi-code/install.sh | bash  # Kimi Code"
echo "  curl -fsSL https://x.ai/cli/install.sh | bash                 # Grok (xAI)"
