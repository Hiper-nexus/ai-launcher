#!/usr/bin/env python3
"""Servidor MCP do Jev (TypeSafe) — roteamento por linguagem natural.

Dá a qualquer CLI que fale MCP (Claude Code, Cursor, Gemini, opencode, Codex)
a capacidade de perguntar "qual CLI de IA serve para esta tarefa?" sem passar
pelo launcher `ai`.

Escopo deliberadamente pequeno: UMA tool. Cada tool de MCP é carregada no
contexto a cada turno, então a diferença entre 1 e 8 tools é a diferença entre
~300 tokens e ~4 mil tokens por sessão, em CADA CLI que você configurar.

    ┌──────────────────────────────────────────────────────────┐
    │ CUSTO: este servidor adiciona ~300 tokens de contexto por │
    │ sessão em cada CLI onde for configurado. Configure só     │
    │ onde você realmente usa CLI fora do `ai`.                 │
    └──────────────────────────────────────────────────────────┘

O Jev não é um LLM: é um serviço que devolve julgamento TIPADO (a opção
escolhida, a distribuição de probabilidade e um confidence). Nada é executado
aqui — a tool só devolve a decisão para quem chamou.

Protocolo: JSON-RPC 2.0 sobre stdio, deliberadamente sem dependências (só a
stdlib). O repo exige python3 para o próprio launcher, então não há instalação
nova.

Uso (o cliente MCP é quem sobe o processo):
    python3 /caminho/para/mcp/jev-server.py

Variáveis de ambiente:
    TYPESAFE_API_KEY        key do TypeSafe (obrigatória para rotear)
    AI_JEV_HOST             default https://api.typesafe.ai
    AI_JEV_MODEL            default jev-latest
    AI_LAUNCHER_PATH        caminho do script `ai` (default ~/.local/bin/ai),
                            de onde o criteria de destinos é lido
"""

import json
import os
import re
import sys
import time
import urllib.error
import urllib.request

PROTOCOL_VERSION = "2024-11-05"
SERVER_NAME = "jev"
SERVER_VERSION = "1.0.0"

HOST = os.environ.get("AI_JEV_HOST", "https://api.typesafe.ai").rstrip("/")
MODEL = os.environ.get("AI_JEV_MODEL", "jev-latest")
LAUNCHER = os.environ.get(
    "AI_LAUNCHER_PATH", os.path.expanduser("~/.local/bin/ai")
)

RETENTAVEIS = {429, 503, 529}
TENTATIVAS = 3
ESPERA = 0.8


# ── Criteria: fonte única ────────────────────────────────
# O `ai` é distribuído como ARQUIVO ÚNICO (curl de uma URL só), então não dá
# para ter um criteria.json compartilhado sem quebrar a distribuição. Lemos o
# JSON de dentro do launcher instalado: uma fonte só, zero duplicação. Se o
# formato mudar, isto falha ALTO em vez de rotear errado em silêncio.
def carregar_criteria():
    try:
        with open(LAUNCHER, "r", encoding="utf-8", errors="replace") as fh:
            src = fh.read()
    except OSError as e:
        raise RuntimeError(
            f"não consegui ler o launcher em {LAUNCHER}: {e}. "
            f"Defina AI_LAUNCHER_PATH apontando para o script `ai`."
        ) from e

    marca = "JEV_ROUTE_CRITERIA='"
    i = src.find(marca)
    if i < 0:
        raise RuntimeError(
            f"{LAUNCHER} não tem JEV_ROUTE_CRITERIA — é uma versão anterior a "
            f"1.51.0, ou o nome da variável mudou."
        )
    j = src.find("'", i + len(marca))
    if j < 0:
        raise RuntimeError("JEV_ROUTE_CRITERIA sem aspas de fechamento")
    return json.loads(src[i + len(marca):j])


def api_key():
    """Key do TypeSafe, em ordem de precedência.

    1. TYPESAFE_API_KEY no ambiente (útil para testar)
    2. slot `typesafe` do providers.conf do launcher (chmod 600)

    O passo 2 existe para NÃO gravar a key em cada config de CLI. Configurar o
    Jev em cinco CLIs com a key inline criaria cinco cópias em texto plano do
    mesmo segredo — o problema que o próprio launcher já resolve guardando as
    keys num arquivo 600. Configure as CLIs sem key nenhuma no config; ela sai
    daqui. Grave a sua uma vez com:  ai jev key
    """
    do_env = os.environ.get("TYPESAFE_API_KEY", "").strip()
    if do_env:
        return do_env

    conf = os.environ.get(
        "AI_PROVIDERS_FILE",
        os.path.expanduser("~/.local/share/ai-launcher/providers.conf"),
    )
    try:
        with open(conf, "r", encoding="utf-8", errors="replace") as fh:
            for linha in fh:
                if linha.startswith("typesafe="):
                    return linha.split("=", 1)[1].strip()
    except OSError:
        pass
    return ""


# ── Roteamento ───────────────────────────────────────────
def rotear(pedido, criteria):
    url = HOST + "/v1/systemone"
    body = json.dumps({
        "model": MODEL,
        "state": {"pedido_do_usuario": pedido},
        "questions": {
            "destino": {
                "type": "choice",
                "instructions": (
                    "O pedido do usuário deve ser executado por uma CLI de "
                    "agente de programação. Escolha a CLI mais adequada para "
                    "ESTE pedido. Pese: custo, tamanho de contexto necessário, "
                    "profundidade de raciocínio exigida, e se o trabalho é "
                    "autônomo de ponta a ponta ou uma conversa iterativa. Se o "
                    "pedido já cita uma ferramenta pelo nome, escolha a opção "
                    "correspondente a ela."
                ),
                "criteria": criteria,
            }
        },
    }).encode()

    req = urllib.request.Request(url, data=body, headers={
        "Authorization": "Bearer " + api_key(),
        "Content-Type": "application/json",
    })

    ultimo = None
    for tentativa in range(TENTATIVAS):
        try:
            with urllib.request.urlopen(req, timeout=30) as r:
                d = json.load(r)
            a = (d.get("answers") or {}).get("destino") or {}
            return {
                "opcao": a.get("choice", ""),
                "confianca": a.get("confidence"),
                "distribuicao": a.get("probabilities", {}),
                "modelo": d.get("model", ""),
                "uso": d.get("usage", {}),
            }
        except urllib.error.HTTPError as e:
            detalhe = e.read().decode("utf-8", "replace")[:200].replace("\n", " ")
            ultimo = f"HTTP {e.code}: {detalhe}"
            if e.code not in RETENTAVEIS or tentativa == TENTATIVAS - 1:
                break
            time.sleep(ESPERA * (2 ** tentativa))
        except Exception as e:  # rede, timeout, DNS
            ultimo = str(e)
            if tentativa == TENTATIVAS - 1:
                break
            time.sleep(ESPERA * (2 ** tentativa))
    raise RuntimeError(f"Jev indisponível: {ultimo}")


# ── Definição da tool ────────────────────────────────────
TOOL = {
    "name": "jev_route",
    "description": (
        "Escolhe qual CLI de IA (Claude Code, Codex, Gemini, DeepSeek, GLM, "
        "Fugu, Cursor, Devin…) é a mais adequada para uma tarefa descrita em "
        "linguagem natural, e devolve a decisão com a confiança e a "
        "distribuição de probabilidade entre as opções. Use quando o usuário "
        "descrever o que quer fazer sem dizer qual ferramenta usar, ou quando "
        "ele perguntar qual CLI/modelo escolher. NÃO executa nada: apenas "
        "decide e reporta. Se a confiança vier baixa ou a opção for 'nenhum', "
        "trate como indecisão e pergunte ao usuário em vez de assumir."
    ),
    "inputSchema": {
        "type": "object",
        "properties": {
            "pedido": {
                "type": "string",
                "description": (
                    "A tarefa em linguagem natural, de preferência com o "
                    "contexto que importa para a escolha (tamanho, urgência, "
                    "se pode gastar, se é trabalho longo e autônomo)."
                ),
            }
        },
        "required": ["pedido"],
    },
}


# ── JSON-RPC sobre stdio ─────────────────────────────────
def responder(msg_id, result=None, error=None):
    out = {"jsonrpc": "2.0", "id": msg_id}
    if error is not None:
        out["error"] = error
    else:
        out["result"] = result
    sys.stdout.write(json.dumps(out) + "\n")
    sys.stdout.flush()


def texto_resultado(texto):
    return {"content": [{"type": "text", "text": texto}]}


def tratar(msg):
    metodo = msg.get("method")
    msg_id = msg.get("id")

    # Notificações não têm id e não levam resposta.
    if metodo == "notifications/initialized":
        return
    if metodo == "initialize":
        responder(msg_id, {
            "protocolVersion": PROTOCOL_VERSION,
            "capabilities": {"tools": {}},
            "serverInfo": {"name": SERVER_NAME, "version": SERVER_VERSION},
        })
        return
    if metodo == "tools/list":
        responder(msg_id, {"tools": [TOOL]})
        return
    if metodo == "ping":
        responder(msg_id, {})
        return
    if metodo == "tools/call":
        params = msg.get("params") or {}
        args = params.get("arguments") or {}
        pedido = (args.get("pedido") or "").strip()

        if not api_key():
            responder(msg_id, error={
                "code": -32000,
                "message": (
                    "Nenhuma key do TypeSafe encontrada. Rode `ai jev key` uma "
                    "vez para gravar em providers.conf (chmod 600), ou defina "
                    "TYPESAFE_API_KEY no env DESTE servidor MCP. A key NÃO vai "
                    "no config da CLI — o servidor lê do providers.conf."
                ),
            })
            return
        if not pedido:
            responder(msg_id, error={
                "code": -32602,
                "message": "argumento 'pedido' vazio",
            })
            return

        try:
            criteria = carregar_criteria()
            r = rotear(pedido, criteria)
        except Exception as e:
            # Falha de infraestrutura vira resultado de erro da tool (não
            # -32603), para o modelo poder reagir em vez de o cliente quebrar.
            responder(msg_id, result={
                "content": [{"type": "text", "text": f"Erro no roteamento: {e}"}],
                "isError": True,
            })
            return

        linhas = [
            f"opção escolhida: {r['opcao'] or '(vazia)'}",
        ]
        if r["confianca"] is not None:
            try:
                linhas.append(f"confiança: {float(r['confianca']) * 100:.0f}%")
            except (TypeError, ValueError):
                linhas.append(f"confiança: {r['confianca']}")
        probs = sorted(
            ((v, k) for k, v in (r["distribuicao"] or {}).items()
             if isinstance(v, (int, float))),
            reverse=True,
        )
        if probs:
            top = "  ".join(f"{k} {v * 100:.1f}%" for v, k in probs[:5])
            linhas.append(f"distribuição: {top}")
        if r["modelo"]:
            linhas.append(f"modelo: {r['modelo']}")
        if r["opcao"] == "nenhum":
            linhas.append(
                "→ 'nenhum' significa que o pedido não descreve uma tarefa "
                "executável por CLI. Não escolha uma ferramenta por conta "
                "própria: pergunte ao usuário."
            )

        responder(msg_id, result=texto_resultado("\n".join(linhas)))
        return

    if msg_id is not None:
        responder(msg_id, error={
            "code": -32601,
            "message": f"método não suportado: {metodo}",
        })


def main():
    # O protocolo é JSON UTF-8, mas no Windows o Python abre stdin/stdout no
    # encoding da locale (cp1252). Um pedido com acento — "refatorar a
    # autenticação" — chegava como UnicodeDecodeError e derrubava o servidor
    # na primeira frase em português. reconfigure existe desde o 3.7; em
    # stream que não aceite (stdin redirecionado de forma exótica) seguimos
    # com o que havia em vez de não subir.
    for stream in (sys.stdin, sys.stdout):
        try:
            stream.reconfigure(encoding="utf-8")
        except (AttributeError, ValueError):
            pass

    for linha in sys.stdin:
        linha = linha.strip()
        if not linha:
            continue
        try:
            msg = json.loads(linha)
        except json.JSONDecodeError:
            continue  # lixo no stream não pode derrubar o servidor
        try:
            tratar(msg)
        except Exception as e:
            msg_id = msg.get("id") if isinstance(msg, dict) else None
            if msg_id is not None:
                responder(msg_id, error={"code": -32603, "message": str(e)})


if __name__ == "__main__":
    main()
