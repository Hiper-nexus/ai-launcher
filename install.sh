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

# Instalar o script
if [[ -f "$(dirname "${BASH_SOURCE[0]}")/ai" && -z "${AI_LAUNCHER_FORCE_DOWNLOAD:-}" ]]; then
    echo -e "${GREEN}Instalando a partir dos arquivos locais do repositório...${RESET}"
    cp "$(dirname "${BASH_SOURCE[0]}")/ai" "${INSTALL_DIR}/ai"
elif command -v curl &>/dev/null; then
    echo -e "${GREEN}Baixando ai-launcher...${RESET}"
    if ! curl -fsSL "${REPO_RAW}/ai" -o "${INSTALL_DIR}/ai"; then
        echo -e "${RED}Erro ao baixar. Verifique sua conexão.${RESET}"
        # Restaurar backup se existir
        [[ -f "${INSTALL_DIR}/ai.bak" ]] && mv "${INSTALL_DIR}/ai.bak" "${INSTALL_DIR}/ai"
        exit 1
    fi
elif command -v wget &>/dev/null; then
    echo -e "${GREEN}Baixando ai-launcher...${RESET}"
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

# Scripts Python num caminho estável (git pull no repo não quebra nada): o
# servidor MCP do Gemini Decision, que `ai gd setup` grava no config das CLIs,
# e o proxy ACP que o `ai qw t3` põe no provider do Qwen no T3 (todos os
# modelos do Token Plan). Falha aqui não é fatal: os comandos baixam se faltar.
MCP_DIR="${HOME}/.local/share/ai-launcher/mcp"
mkdir -p "$MCP_DIR"
for _mcp in gemini-decision-server.py qwen-acp-proxy.py; do
    _local="$(dirname "${BASH_SOURCE[0]}")/mcp/${_mcp}"
    if [[ -f "$_local" && -z "${AI_LAUNCHER_FORCE_DOWNLOAD:-}" ]]; then
        cp "$_local" "${MCP_DIR}/${_mcp}"
    elif command -v curl &>/dev/null &&
        curl -fsSL "${REPO_RAW}/mcp/${_mcp}" -o "${MCP_DIR}/${_mcp}.tmp"; then
        mv "${MCP_DIR}/${_mcp}.tmp" "${MCP_DIR}/${_mcp}"
    else
        rm -f "${MCP_DIR}/${_mcp}.tmp"
        echo -e "${YELLOW}Aviso: mcp/${_mcp} não instalado (ai gd setup / ai qw t3 baixam depois).${RESET}"
    fi
done

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
            # Sem terminal (ssh host ./install.sh, T3, CI) não pergunta: o read
            # travaria com a entrada aberta ou, fechada, o set -e encerraria o
            # script antes de reaplicar o Gemini Decision e o Qwen no T3.
            yn=""
            if [[ -t 0 ]]; then
                read -rp "Adicionar ao ${SHELL_RC} automaticamente? [s/N]: " yn || yn=""
            else
                echo "  Para pôr no PATH: echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ${SHELL_RC}"
            fi
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

# Máquina que já tem a key do Gemini Decision: reaplica o MCP e o bloco de
# instruções em todas as CLIs a cada atualização (idempotente). Sem key, nada
# muda — quem só usa o launcher não ganha MCP que não pediu.
if grep -q '^gemini-decision=' "${HOME}/.local/share/ai-launcher/providers.conf" 2>/dev/null; then
    # As CLIs (qwen, devin, kimi...) moram ao lado do ai; sem terminal (ssh)
    # o ~/.local/bin costuma estar fora do PATH e o `ai qw t3` não acharia o qwen.
    export PATH="${INSTALL_DIR}:${PATH}"
    echo ""
    echo -e "${CYAN}Gemini Decision: atualizando o MCP nas CLIs desta máquina...${RESET}"
    "${INSTALL_DIR}/ai" gd setup || echo -e "${YELLOW}Aviso: ai gd setup terminou com erro (acima).${RESET}"
    # Mesma máquina "da casa": modelos do Token Plan (Qwen + DeepSeek) no
    # Qwen 1.0 e agentes do Registry quebrados no T3 trocados pelo CLI local.
    "${INSTALL_DIR}/ai" qw sync >/dev/null 2>&1 || true
    if [[ -f "${T3CODE_HOME:-${HOME}/.t3}/userdata/settings.json" ]]; then
        # Qwen 1.0 no T3 com todos os modelos via proxy (só faz algo com o 1.0 no PATH)
        "${INSTALL_DIR}/ai" qw t3 2>/dev/null | grep -E "criado|atualizado|desativado" || true
        echo -e "${CYAN}T3 Code: conferindo providers...${RESET}"
        "${INSTALL_DIR}/ai" t3 fix || echo -e "${YELLOW}Pendências acima precisam de você (login etc.).${RESET}"
    fi
fi

echo ""
echo -e "${GREEN}Instalado com sucesso!${RESET}"
echo ""
echo "Uso:"
echo "  ai             Menu interativo (opção 5: Macaron Venti)"
echo "  ai c           Claude Code"
echo "  ai mint        Macaron V1 (Claude Code)"
echo "  ai mint-codex  Codex via Macaron V1"
echo "  ai x           Codex"
echo "  ai fugu        Sakana Fugu Ultra V2.0"
echo "  ai fugu-ultra  Sakana Fugu Ultra V2.0"
echo "  ai fugu-max    Sakana Fugu Max V1.0"
echo "  ai g           Gemini"
echo "  ai k           Kimi Code"
echo "  ai gr          Grok (xAI)"
echo "  ai --help      Ajuda completa"
echo ""
echo -e "${YELLOW}Pré-requisitos (instale os que quiser usar):${RESET}"
echo "  npm install -g @anthropic-ai/claude-code   # Claude"
echo "  npm install -g @openai/codex               # Codex"
echo "  npm install -g @google/gemini-cli           # Gemini"
echo "  npm install -g @mimo-ai/cli                 # MiMoCode (Xiaomi MiMo)"
echo "  npm install -g @minimax-ai/code            # MiniMax Code (mcode)"
echo "  curl -fsSL https://code.kimi.com/kimi-code/install.sh | bash  # Kimi Code"
echo "  curl -fsSL https://x.ai/cli/install.sh | bash                 # Grok (xAI)"
echo "  curl -fsSL https://cli.devin.ai/install.sh | bash             # Devin CLI"
