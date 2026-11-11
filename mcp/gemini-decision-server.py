#!/usr/bin/env python3
"""Servidor MCP do Gemini Decision (Google, modelo gemini-decision-1).

O Gemini Decision não gera texto: responde perguntas FECHADAS com
probabilidade calibrada em ~200 ms (sim/não, uma opção de uma lista, uma nota
numa rubrica), sobre texto, imagem, PDF, áudio e vídeo. Saída custa zero;
entrada custa US$ 0,10 por 1M tokens.

Três tools, pensadas para desenvolvimento web (T3 ou qualquer CLI com MCP):

  ui_check  screenshots × critérios de aceite → o que passou, falhou, ficou em
            dúvida; com mock aprovado, mede a fidelidade ao design
  rank      objetivo × candidatos (componentes de catálogo, arquivos,
            abordagens) → ordenados pelo quanto servem
  decide    perguntas livres noul/choice/score sobre texto e arquivos

    ┌──────────────────────────────────────────────────────────┐
    │ CUSTO DE CONTEXTO: as três tools somam ~1,2 mil tokens   │
    │ por sessão em cada CLI onde o servidor for registrado.   │
    └──────────────────────────────────────────────────────────┘

Sem dependências (só a stdlib). A key NÃO vai no config das CLIs: o servidor
lê do providers.conf do launcher (slot gemini-decision, chmod 600), gravada
uma vez com `ai gd key`.

Também roda como comando (é o que o `ai gd` usa):
    gemini-decision-server.py ping
    gemini-decision-server.py ui [--ref IMG] [--context TXT] [-c CRITÉRIO]... IMG...
    gemini-decision-server.py ask "PERGUNTA" [ARQUIVO...]
    gemini-decision-server.py call <tool> '<argumentos em JSON>'

Variáveis de ambiente:
    GEMINI_DECISION_API_KEY   key (senão providers.conf; senão GEMINI_API_KEY)
    GEMINI_DECISION_BASE_URL  default https://generativelanguage.googleapis.com
    GEMINI_DECISION_MODEL     default gemini-decision-1
    AI_PROVIDERS_FILE         default ~/.local/share/ai-launcher/providers.conf
    GEMINI_DECISION_LOG       registro de uso SEM conteúdo (data, tool,
                              tokens, ms); "off" desliga
"""

import base64
import concurrent.futures
import tempfile
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request

PROTOCOL_VERSION = "2024-11-05"
SERVER_NAME = "gemini_decision"
SERVER_VERSION = "1.2.0"

BASE = os.environ.get(
    "GEMINI_DECISION_BASE_URL", "https://generativelanguage.googleapis.com"
).rstrip("/")
MODEL = os.environ.get("GEMINI_DECISION_MODEL", "gemini-decision-1")
SLOT = "gemini-decision"
DATA_DIR = os.path.expanduser("~/.local/share/ai-launcher")

RETENTAVEIS = {429, 500, 502, 503, 504}
TENTATIVAS = 3
ESPERA = 1.0
TIMEOUT = 45      # por tentativa
PRAZO_TOTAL = 55  # o Codex desiste da tool em ~60 s; não adianta tentar além

# Limites da API: 100 MB inline por pedido (50 MB para PDF). Fica uma folga
# para o base64 (que cresce 4/3) e o resto do JSON.
MAX_INLINE = 70 * 1024 * 1024
MAX_PDF = 37 * 1024 * 1024

# Faixas de decisão do ui_check. A API devolve P(sim) entre 0,01 e 0,99.
OK_MIN = 0.80
FALHA_MAX = 0.35

MIMES = {
    ".png": "image/png", ".jpg": "image/jpeg", ".jpeg": "image/jpeg",
    ".webp": "image/webp", ".gif": "image/gif", ".heic": "image/heic",
    ".heif": "image/heif", ".bmp": "image/bmp", ".tif": "image/tiff",
    ".tiff": "image/tiff",
    ".pdf": "application/pdf",
    # .webm é vídeo aqui: é o que o Playwright grava.
    ".mp4": "video/mp4", ".mpeg": "video/mpeg", ".mpg": "video/mpeg",
    ".mov": "video/mov", ".avi": "video/avi", ".webm": "video/webm",
    ".wmv": "video/wmv", ".flv": "video/x-flv", ".3gp": "video/3gpp",
    ".wav": "audio/wav", ".mp3": "audio/mp3", ".aiff": "audio/aiff",
    ".aac": "audio/aac", ".ogg": "audio/ogg", ".flac": "audio/flac",
    ".m4a": "audio/m4a", ".opus": "audio/opus",
}
RESOLUCOES = ("low", "medium", "high", "ultra_high")
CHAVE_PERGUNTA = re.compile(r"^[A-Za-z0-9_-]{1,64}$")

# Formatos de credencial conhecidos. Tudo que sai daqui vai para a API do
# Google; na camada gratuita os dados podem ser usados para melhorar produtos.
# Não é DLP completo: pega o vazamento acidental mais comum (agente colando
# um .env, um log com token ou uma URL com senha). A fronteira (?<![\w-]) evita
# recusar identificadores como "task-runner-..." ou "desk-booking-...".
_B = r"(?<![A-Za-z0-9_-])"
SEGREDOS = [
    ("key do Google", re.compile(_B + r"(?:AIza[0-9A-Za-z_\-]{35}|AQ\.[A-Za-z0-9_-]{40,})")),
    ("key da OpenAI/Anthropic", re.compile(_B + r"sk-(?:ant-|proj-)?(?=[A-Za-z0-9_-]*\d)[A-Za-z0-9_-]{24,}")),
    ("key do Stripe", re.compile(_B + r"[sr]k_(?:live|test)_[A-Za-z0-9]{16,}")),
    ("token do GitHub", re.compile(_B + r"(?:gh[pousr]_[A-Za-z0-9]{36}|github_pat_[A-Za-z0-9_]{40,})")),
    ("token do Slack", re.compile(_B + r"xox[abprs]-[A-Za-z0-9-]{10,}")),
    ("token do Supabase", re.compile(_B + r"sbp_[a-f0-9]{40}")),
    ("key da AWS", re.compile(_B + r"AKIA[0-9A-Z]{16}")),
    ("chave privada", re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----")),
    ("JWT", re.compile(r"eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}")),
    ("senha em URL", re.compile(r"[a-z][a-z0-9+.-]*://[^/\s:@]+:[^/\s@]+@")),
    ("token Bearer", re.compile(r"(?i)\bbearer\s+[A-Za-z0-9._~+/=-]{20,}")),
    ("credencial atribuída", re.compile(
        r"(?i)\b[A-Z0-9_]*(?:api[_-]?key|secret|passw(?:or)?d|token)\b\s*[=:]\s*[\"']?[A-Za-z0-9/+_=-]{20,}")),
]

# Checagens que valem para qualquer tela. Redigidas no positivo (a doc da API
# recomenda: "sim" = está certo), então P(sim) baixo = problema.
CHECAGENS_PADRAO = [
    "Todo o texto visível está inteiro e legível, sem cortes, sem "
    "sobreposição e sem sair do seu contêiner.",
    "Todas as imagens e ícones carregaram: não há ícone de imagem quebrada, "
    "caixa vazia no lugar de imagem nem texto alternativo aparecendo.",
    "A tela está livre de erro técnico visível: stack trace, overlay de erro "
    "do framework (Next.js, Vite), 'undefined', 'NaN' ou '[object Object]'.",
    "O layout cabe na largura da tela: sem rolagem horizontal, sem elementos "
    "cortados na borda e sem elementos sobrepostos por engano.",
    "A tela mostra conteúdo carregado: não está em branco, presa em "
    "esqueleto de carregamento nem só com um spinner.",
]
NIVEIS_FIDELIDADE = [
    "Muito diferente da referência: estrutura ou hierarquia diferentes.",
    "Mesma estrutura geral, mas várias diferenças visíveis de espaçamento, "
    "cor, tipografia ou componentes.",
    "Próxima da referência, com poucas diferenças pequenas.",
    "Praticamente idêntica à referência.",
]
NIVEIS_RANK = [
    "Não serve para o objetivo.",
    "Serve só em parte; exigiria adaptação grande.",
    "Serve com adaptação pequena.",
    "Serve quase como está.",
]


class ErroTool(Exception):
    """Erro que vira resultado `isError` para o modelo reagir."""


# ── Key ──────────────────────────────────────────────────
def api_key():
    """1. GEMINI_DECISION_API_KEY  2. slot gemini-decision do providers.conf
    3. GEMINI_API_KEY / GOOGLE_API_KEY.

    O passo 2 existe para NÃO gravar a key no config de cada CLI (seriam oito
    cópias em texto plano do mesmo segredo)."""
    k = os.environ.get("GEMINI_DECISION_API_KEY", "").strip()
    if k:
        return k
    conf = os.environ.get(
        "AI_PROVIDERS_FILE", os.path.join(DATA_DIR, "providers.conf")
    )
    try:
        with open(conf, "r", encoding="utf-8", errors="replace") as fh:
            for linha in fh:
                if linha.startswith(SLOT + "="):
                    k = linha.split("=", 1)[1].strip()
                    if k:
                        return k
    except OSError:
        pass
    for nome in ("GEMINI_API_KEY", "GOOGLE_API_KEY"):
        k = os.environ.get(nome, "").strip()
        if k:
            return k
    return ""


SEM_KEY = (
    "Sem key do Gemini Decision. Crie uma em https://aistudio.google.com/api-keys "
    "e grave UMA vez com `ai gd key` (fica em providers.conf, chmod 600). A key "
    "não vai no config da CLI: este servidor lê de lá."
)


# ── Entrada ──────────────────────────────────────────────
def checar_segredo(*textos):
    for t in textos:
        if not isinstance(t, str):
            continue
        for nome, padrao in SEGREDOS:
            if padrao.search(t):
                # Diz o TIPO, nunca o valor: a mensagem volta para o modelo.
                raise ErroTool(
                    f"o conteúdo parece ter uma credencial ({nome}). Nada foi "
                    "enviado. Remova o segredo e tente de novo."
                )


def pastas_permitidas():
    """De onde arquivos locais podem sair. GEMINI_DECISION_ALLOWED_DIRS
    (separado por os.pathsep) SUBSTITUI a lista padrão: a pasta do projeto
    (cwd do servidor, que a CLI sobe no projeto), as pastas temporárias e
    Desktop/Downloads, onde screenshots costumam cair. O home inteiro nunca."""
    extra = os.environ.get("GEMINI_DECISION_ALLOWED_DIRS")
    if extra is not None:
        dirs = [d for d in extra.split(os.pathsep) if d.strip()]
    else:
        home = os.path.expanduser("~")
        dirs = [tempfile.gettempdir(), "/tmp", "/private/tmp", "/var/folders",
                "/private/var/folders", os.path.join(home, "Desktop"),
                os.path.join(home, "Downloads")]
        cwd = os.getcwd()
        if os.path.realpath(cwd) not in (os.path.realpath(home), os.path.realpath(os.sep)):
            dirs.append(cwd)
    return [os.path.realpath(os.path.expanduser(d)) for d in dirs]


def dentro_permitido(caminho):
    for d in pastas_permitidas():
        try:
            if os.path.commonpath([caminho, d]) == d:
                return True
        except ValueError:  # unidades diferentes no Windows
            continue
    return False


def assinatura_ok(h, mime):
    """Confere os primeiros bytes contra o formato declarado pela extensão."""
    caixa = h[4:8]  # ISO BMFF (mp4, mov, 3gp, m4a, heic)
    if mime == "image/png":
        return h.startswith(b"\x89PNG")
    if mime == "image/jpeg":
        return h.startswith(b"\xff\xd8\xff")
    if mime == "image/gif":
        return h.startswith(b"GIF8")
    if mime == "image/webp":
        return h[:4] == b"RIFF" and h[8:12] == b"WEBP"
    if mime == "image/bmp":
        return h.startswith(b"BM")
    if mime == "image/tiff":
        return h[:4] in (b"II*\x00", b"MM\x00*")
    if mime in ("image/heic", "image/heif", "video/mp4", "video/mov",
                "video/3gpp", "audio/m4a"):
        return caixa in (b"ftyp", b"moov", b"wide", b"mdat", b"free", b"skip")
    if mime == "application/pdf":
        return h.startswith(b"%PDF")
    if mime == "video/webm":
        return h.startswith(b"\x1a\x45\xdf\xa3")
    if mime == "video/avi":
        return h[:4] == b"RIFF" and h[8:11] == b"AVI"
    if mime == "audio/wav":
        return h[:4] == b"RIFF" and h[8:12] == b"WAVE"
    if mime == "video/mpeg":
        return h[:3] == b"\x00\x00\x01"
    if mime == "video/wmv":
        return h.startswith(b"\x30\x26\xb2\x75")
    if mime == "video/x-flv":
        return h.startswith(b"FLV")
    if mime == "audio/mp3":
        return h.startswith(b"ID3") or (len(h) > 1 and h[0] == 0xFF and h[1] & 0xE0 == 0xE0)
    if mime == "audio/aiff":
        return h[:4] == b"FORM" and h[8:11] == b"AIF"
    if mime == "audio/aac":
        return h.startswith(b"ADIF") or (len(h) > 1 and h[0] == 0xFF and h[1] & 0xF6 == 0xF0)
    if mime in ("audio/ogg", "audio/opus"):
        return h.startswith(b"OggS")
    if mime == "audio/flac":
        return h.startswith(b"fLaC")
    return False


def bloco_arquivo(ref, resolucao, orcamento):
    """Caminho local ou URL https → bloco de conteúdo da API."""
    ref = (ref or "").strip()
    if not ref:
        raise ErroTool("caminho de arquivo vazio")
    alvo = ref.split("?", 1)[0] if ref.startswith("https://") else ref
    ext = os.path.splitext(alvo)[1].lower()
    mime = MIMES.get(ext)
    if not mime:
        # Recusa por extensão: impede que um agente mande .env, chaves SSH ou
        # código-fonte como "arquivo". Texto vai no campo `input`.
        raise ErroTool(
            f"tipo não suportado: {os.path.basename(alvo) or alvo}. Arquivos "
            "aceitos: imagem, PDF, áudio ou vídeo. Texto vai no campo `input`."
        )
    tipo = ("image" if mime.startswith("image/") else
            "video" if mime.startswith("video/") else
            "audio" if mime.startswith("audio/") else "document")
    bloco = {"type": tipo, "mime_type": mime}
    if ref.startswith("https://"):
        checar_segredo(ref)  # token em query string também é vazamento
        bloco["uri"] = ref
    elif ref.startswith("http://"):
        raise ErroTool("a API só aceita URL https")
    else:
        caminho = os.path.realpath(os.path.expanduser(ref))
        if not os.path.isfile(caminho):
            raise ErroTool(f"arquivo não encontrado: {ref}")
        if not dentro_permitido(caminho):
            # realpath antes: symlink no projeto apontando para fora não passa.
            raise ErroTool(
                f"{ref} está fora das pastas permitidas (projeto, temporárias, "
                "Desktop, Downloads). Copie o arquivo para o projeto ou defina "
                "GEMINI_DECISION_ALLOWED_DIRS no env do servidor."
            )
        tamanho = os.path.getsize(caminho)
        if tipo == "document" and tamanho > MAX_PDF:
            raise ErroTool(f"PDF grande demais (máx. {MAX_PDF // 2**20} MB)")
        orcamento[0] += tamanho
        if orcamento[0] > MAX_INLINE:
            raise ErroTool(
                f"arquivos somam mais de {MAX_INLINE // 2**20} MB; mande menos "
                "por chamada ou reduza (vídeo curto, screenshot em PNG/JPG)"
            )
        try:
            with open(caminho, "rb") as fh:
                dados = fh.read()
        except OSError as e:
            raise ErroTool(f"não consegui ler {ref}: {e.strerror}")
        if not assinatura_ok(dados[:64], mime):
            # Um .env renomeado para .png não passa: o conteúdo tem que ser
            # mesmo da mídia declarada.
            raise ErroTool(f"{os.path.basename(ref)} não é um {mime} de verdade")
        bloco["data"] = base64.b64encode(dados).decode("ascii")
    if resolucao and tipo in ("image", "video"):
        bloco["resolution"] = resolucao
    return bloco


def resolucao_valida(r, padrao=None):
    r = (r or padrao or "")
    if r and r not in RESOLUCOES:
        raise ErroTool(f"resolution deve ser um de {', '.join(RESOLUCOES)}")
    return r or None


def montar_perguntas(perguntas):
    """Aceita o formato tipado da tool (lista de objetos, portável entre
    clientes MCP) ou o formato nativo da API (mapa chave → pergunta)."""
    if isinstance(perguntas, dict):
        itens = [dict(v, id=k) for k, v in perguntas.items() if isinstance(v, dict)]
    elif isinstance(perguntas, list):
        itens = perguntas
    else:
        raise ErroTool("questions deve ser uma lista de perguntas")
    if not 1 <= len(itens) <= 1000:
        raise ErroTool("envie de 1 a 1000 perguntas")

    saida = {}
    for n, q in enumerate(itens, 1):
        if not isinstance(q, dict):
            raise ErroTool(f"pergunta {n} não é um objeto")
        chave = str(q.get("id") or f"q{n}")
        checar_segredo(chave)
        if not CHAVE_PERGUNTA.match(chave):
            raise ErroTool(f"id inválido '{chave[:40]}': use [A-Za-z0-9_-], até 64")
        if chave in saida:
            raise ErroTool(f"id repetido: {chave}")
        tipo = q.get("type")
        instr = q.get("instructions")
        if not isinstance(instr, str):
            raise ErroTool(f"pergunta {chave}: instructions deve ser texto")
        instr = instr.strip()
        if not instr:
            raise ErroTool(f"pergunta {chave}: instructions vazio")
        item = {"type": tipo, "instructions": instr}

        if tipo == "noul":
            crit = q.get("criteria") if isinstance(q.get("criteria"), dict) else {}
            sim = q.get("true_description") or crit.get("true_description")
            nao = q.get("false_description") or crit.get("false_description")
            if sim or nao:
                item["criteria"] = {k: v for k, v in
                                    (("true_description", sim), ("false_description", nao)) if v}
        elif tipo == "choice":
            crit = q.get("criteria")
            if not isinstance(crit, dict):
                crit = {}
                for op in q.get("options") or []:
                    op = str(op)
                    k, _, desc = op.partition(":")
                    crit[k.strip()] = desc.strip()
            if not 2 <= len(crit) <= 255 or not all(str(k).strip() for k in crit):
                raise ErroTool(f"pergunta {chave}: choice precisa de 2 a 255 opções")
            item["criteria"] = {str(k).strip(): str(v) for k, v in crit.items()}
        elif tipo == "score":
            niveis = q.get("criteria") if isinstance(q.get("criteria"), list) else q.get("levels")
            niveis = [str(x).strip() for x in (niveis or [])]
            if not 2 <= len(niveis) <= 255 or not all(niveis):
                raise ErroTool(f"pergunta {chave}: score precisa de 2 a 255 níveis não vazios")
            item["criteria"] = niveis
        else:
            raise ErroTool(f"pergunta {chave}: type deve ser noul, choice ou score")

        checar_segredo(instr, json.dumps(item.get("criteria", ""), ensure_ascii=False))
        saida[chave] = item
    return saida


# ── API ──────────────────────────────────────────────────
def registrar_uso(tool, resposta, ms, perguntas):
    destino = os.environ.get("GEMINI_DECISION_LOG", "")
    if destino.lower() == "off":
        return
    destino = destino or os.path.join(DATA_DIR, "gemini-decision-usage.jsonl")
    uso = (resposta or {}).get("usage") or {}
    linha = json.dumps({
        "ts": time.strftime("%Y-%m-%dT%H:%M:%S"),
        "tool": tool,
        "tokens": uso.get("total_input_tokens") or uso.get("total_tokens") or 0,
        "ms": ms,
        "perguntas": perguntas,
    })
    try:
        os.makedirs(os.path.dirname(destino), exist_ok=True)
        fd = os.open(destino, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
        with os.fdopen(fd, "a", encoding="utf-8") as fh:
            fh.write(linha + "\n")
    except OSError:
        pass


def chamar(entrada, perguntas, tool):
    key = api_key()
    if not key:
        raise ErroTool(SEM_KEY)
    corpo = json.dumps(
        {"model": MODEL, "input": entrada, "questions": perguntas},
        ensure_ascii=False,
    ).encode("utf-8")
    pedido = urllib.request.Request(
        BASE + "/v1beta/decisions", data=corpo, method="POST",
        headers={"x-goog-api-key": key, "Content-Type": "application/json"},
    )
    ultimo = None
    prazo = time.monotonic() + PRAZO_TOTAL
    for tentativa in range(TENTATIVAS):
        inicio = time.monotonic()
        try:
            restante = max(5.0, prazo - inicio)
            with urllib.request.urlopen(pedido, timeout=min(TIMEOUT, restante)) as r:
                d = json.load(r)
            ms = int((time.monotonic() - inicio) * 1000)
            bloqueio = (d.get("prompt_feedback") or {}).get("block_reason")
            if bloqueio or not d.get("answers"):
                motivo = (d.get("prompt_feedback") or {}).get("block_reason_message") or bloqueio
                raise ErroTool(f"a API não respondeu às perguntas ({motivo or 'sem answers'})")
            registrar_uso(tool, d, ms, len(perguntas))
            d["_ms"] = ms
            return d
        except urllib.error.HTTPError as e:
            bruto = e.read().decode("utf-8", "replace")
            try:
                erro = json.loads(bruto).get("error") or {}
                msg = erro.get("message") or bruto
            except (ValueError, AttributeError):
                msg = bruto
            ultimo = f"HTTP {e.code}: {msg[:300]}".replace("\n", " ")
            if e.code not in RETENTAVEIS or tentativa == TENTATIVAS - 1:
                break
        except ErroTool:
            raise
        except Exception as e:  # rede, timeout, DNS
            ultimo = str(e)[:300]
            if tentativa == TENTATIVAS - 1:
                break
        espera = ESPERA * (2 ** tentativa)
        if time.monotonic() + espera + 5 > prazo:
            break  # sem tempo para outra tentativa útil antes do cliente desistir
        time.sleep(espera)
    raise ErroTool(f"Gemini Decision indisponível: {ultimo}")


def arredondar(x):
    if isinstance(x, float):
        return round(x, 3)
    if isinstance(x, dict):
        return {k: arredondar(v) for k, v in x.items()}
    if isinstance(x, list):
        return [arredondar(v) for v in x]
    return x


def p_sim(resposta):
    try:
        return float(resposta.get("noul"))
    except (TypeError, ValueError):
        return None


# ── Tools ────────────────────────────────────────────────
def tool_decide(args):
    texto = args.get("input") or ""
    if not isinstance(texto, str):
        texto = json.dumps(texto, ensure_ascii=False)
    checar_segredo(texto)
    resolucao = resolucao_valida(args.get("resolution"))
    perguntas = montar_perguntas(args.get("questions"))
    orcamento = [0]
    entrada = []
    if texto.strip():
        entrada.append({"type": "text", "text": texto})
    for ref in args.get("files") or []:
        entrada.append(bloco_arquivo(ref, resolucao, orcamento))
    if not entrada:
        raise ErroTool("input vazio: mande texto em `input` ou arquivos em `files`")
    d = chamar(entrada, perguntas, "decide")
    return {
        "answers": arredondar(d["answers"]),
        "tokens": (d.get("usage") or {}).get("total_input_tokens"),
        "ms": d["_ms"],
    }


def _checar_uma(captura, checks, referencia, contexto, resolucao):
    orcamento = [0]
    entrada = []
    if referencia:
        entrada.append({"type": "text", "text": "REFERÊNCIA (design aprovado):\n"})
        entrada.append(bloco_arquivo(referencia, resolucao, orcamento))
        entrada.append({"type": "text", "text": "\nIMPLEMENTAÇÃO ATUAL (a avaliar):\n"})
    entrada.append(bloco_arquivo(captura, resolucao, orcamento))
    if contexto:
        entrada.append({"type": "text", "text": "\nContexto: " + contexto})

    alvo = "a IMPLEMENTAÇÃO ATUAL" if referencia else "a captura de tela"
    perguntas = {}
    for i, c in enumerate(checks):
        perguntas[f"c{i:03d}"] = {
            "type": "noul",
            "instructions": f"Sobre {alvo} desta interface, a afirmação é verdadeira? {c}",
        }
    if referencia:
        perguntas["fidelidade"] = {
            "type": "score",
            "instructions": "Quão fiel a IMPLEMENTAÇÃO ATUAL está à REFERÊNCIA?",
            "criteria": NIVEIS_FIDELIDADE,
        }
    d = chamar(entrada, perguntas, "ui_check")
    a = d["answers"]

    falhas, incertos, ok = [], [], 0
    for i, c in enumerate(checks):
        p = p_sim(a.get(f"c{i:03d}") or {})
        if p is None:
            incertos.append({"criterio": c, "p_ok": None})
        elif p >= OK_MIN:
            ok += 1
        elif p <= FALHA_MAX:
            falhas.append({"criterio": c, "p_ok": round(p, 2)})
        else:
            incertos.append({"criterio": c, "p_ok": round(p, 2)})
    falhas.sort(key=lambda x: x["p_ok"])
    r = {
        "captura": os.path.basename(captura.split("?", 1)[0]),
        "falhas": falhas,
        "incertos": incertos,
        "ok": ok,
        "tokens": (d.get("usage") or {}).get("total_input_tokens"),
        "ms": d["_ms"],
    }
    fid = a.get("fidelidade")
    if fid:
        probs = fid.get("probabilities") or {}
        nivel = max(probs, key=probs.get) if probs else None
        r["fidelidade"] = {
            "nota": round(float(fid.get("score", 0)), 2),
            "de": len(NIVEIS_FIDELIDADE) - 1,
            "nivel": (fid.get("legend") or {}).get(nivel) if nivel else None,
        }
    return r


def tool_ui_check(args):
    capturas = args.get("screenshots") or []
    if isinstance(capturas, str):
        capturas = [capturas]
    if not 1 <= len(capturas) <= 12:
        raise ErroTool("envie de 1 a 12 screenshots por chamada")
    checks = [str(c).strip() for c in (args.get("checks") or []) if str(c).strip()]
    if args.get("defaults", True) is not False:
        checks = checks + CHECAGENS_PADRAO
    if not checks:
        raise ErroTool("sem critérios: passe `checks` ou deixe defaults ligado")
    contexto = (args.get("context") or "").strip()
    checar_segredo(contexto, *checks)
    resolucao = resolucao_valida(args.get("resolution"), "high")
    referencia = (args.get("reference") or "").strip() or None

    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        futuros = [pool.submit(_checar_uma, c, checks, referencia, contexto, resolucao)
                   for c in capturas]
        resultados = []
        for c, f in zip(capturas, futuros):
            try:
                resultados.append(f.result())
            except ErroTool as e:
                resultados.append({"captura": os.path.basename(c), "erro": str(e)})
            except Exception as e:  # noqa: BLE001 — erro de uma captura fica nela
                resultados.append({"captura": os.path.basename(c),
                                   "erro": f"{type(e).__name__}: {e}"[:200]})

    if all("erro" in r for r in resultados):
        raise ErroTool(resultados[0]["erro"])
    nf = sum(len(r.get("falhas", [])) for r in resultados)
    ni = sum(len(r.get("incertos", [])) for r in resultados)
    resumo = (f"{nf} falha(s), {ni} incerto(s) em {len(capturas)} captura(s) × "
              f"{len(checks)} critério(s). Falha = P(ok) ≤ {FALHA_MAX}; incerto = "
              f"entre {FALHA_MAX} e {OK_MIN}. Confirme falhas e incertos você mesmo.")
    return {"resumo": resumo, "capturas": resultados}


def tool_rank(args):
    objetivo = (args.get("goal") or "").strip()
    if not objetivo:
        raise ErroTool("goal vazio")
    candidatos = []
    for c in args.get("candidates") or []:
        if isinstance(c, dict):
            ident = str(c.get("id") or "").strip()
            desc = str(c.get("description") or "").strip()
            texto = f"{ident}: {desc}" if desc else ident
        else:
            texto = str(c).strip()
            ident = texto.partition(":")[0].strip()[:80] or texto[:80]
        if texto:
            candidatos.append((ident, texto))
    if not 1 <= len(candidatos) <= 500:
        raise ErroTool("envie de 1 a 500 candidatos")
    checar_segredo(objetivo, *(t for _, t in candidatos))
    try:
        top = max(1, min(int(args.get("top") or 10), len(candidatos)))
    except (TypeError, ValueError):
        top = min(10, len(candidatos))

    orcamento = [0]
    entrada = [{"type": "text", "text": "OBJETIVO:\n" + objetivo}]
    for ref in args.get("files") or []:
        entrada.append(bloco_arquivo(ref, resolucao_valida(args.get("resolution"), "medium"), orcamento))
    perguntas = {
        f"k{i:03d}": {
            "type": "score",
            "instructions": "Quão bem este candidato atende ao OBJETIVO? Candidato: " + texto,
            "criteria": NIVEIS_RANK,
        }
        for i, (_, texto) in enumerate(candidatos)
    }
    d = chamar(entrada, perguntas, "rank")
    a = d["answers"]
    lista = []
    for i, (ident, texto) in enumerate(candidatos):
        r = a.get(f"k{i:03d}") or {}
        try:
            nota = float(r.get("score"))
        except (TypeError, ValueError):
            continue
        lista.append({
            "id": ident,
            "nota": round(nota, 2),
            "confianca": round(float(r.get("confidence") or 0), 2),
        })
    lista.sort(key=lambda x: -x["nota"])
    return {
        "escala": "0 = não serve … 3 = serve quase como está",
        "ranking": lista[:top],
        "descartados": sum(1 for x in lista if x["nota"] < 1),
        "tokens": (d.get("usage") or {}).get("total_input_tokens"),
        "ms": d["_ms"],
    }


TOOLS = [
    {
        "name": "ui_check",
        "description": (
            "Confere screenshots da interface contra critérios de aceite em ~1 s, "
            "com probabilidade por critério (Gemini Decision). Use depois de mudar "
            "UI: capture as larguras que importam (ex.: 320, 768, 1024, 1440) e "
            "passe os critérios do pedido e do DESIGN.md como afirmações que DEVEM "
            "ser verdadeiras. Já inclui checagens de texto cortado, imagem quebrada, "
            "erro visível, overflow e tela vazia. Com `reference` (mock aprovado) "
            "também mede a fidelidade. É sinal rápido, não prova: confirme falhas e "
            "incertos. Só telas com dados de teste; nunca segredos."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "screenshots": {"type": "array", "items": {"type": "string"},
                                "description": "Caminhos locais (PNG/JPG/WebP) ou URLs https; 1 a 12."},
                "checks": {"type": "array", "items": {"type": "string"},
                           "description": "Afirmações que devem ser verdadeiras na tela, uma por item."},
                "reference": {"type": "string",
                              "description": "Imagem do design aprovado, para medir fidelidade."},
                "context": {"type": "string",
                            "description": "Página, estado e largura da captura."},
                "defaults": {"type": "boolean",
                             "description": "Incluir as checagens padrão (default true)."},
            },
            "required": ["screenshots"],
        },
    },
    {
        "name": "rank",
        "description": (
            "Ordena candidatos pelo quanto atendem a um objetivo (Gemini Decision; "
            "centenas em ~1 s). Use para escolher componente ou template de catálogo "
            "(BoardUI, shadcnuikit, componentes do projeto) antes de criar do zero, "
            "quais arquivos ler numa tarefa, ou entre abordagens. Passe descrições "
            "curtas e reais. É sugestão: leia o código dos primeiros antes de decidir."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "goal": {"type": "string", "description": "O requisito ou a tarefa."},
                "candidates": {"type": "array", "items": {"type": "string"},
                               "description": "Até 500, no formato 'id: descrição curta'."},
                "files": {"type": "array", "items": {"type": "string"},
                          "description": "Opcional: imagem do design desejado, PDF da spec."},
                "top": {"type": "integer", "description": "Quantos devolver (default 10)."},
            },
            "required": ["goal", "candidates"],
        },
    },
    {
        "name": "decide",
        "description": (
            "Perguntas fechadas com probabilidade calibrada sobre texto e arquivos "
            "(imagem, PDF, áudio, vídeo): sim/não (noul), uma opção de uma lista "
            "(choice) ou nota numa rubrica (score). Até 1000 perguntas por chamada, "
            "independentes entre si; escreva a pergunta inteira em instructions. Use "
            "para triar logs e erros, classificar diffs, checar PDF de spec ou vídeo "
            "de um fluxo. Confiança < 0,7 = dúvida. Sem segredos no input."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "input": {"type": "string",
                          "description": "Contexto em texto: log, trecho de código, spec, JSON."},
                "files": {"type": "array", "items": {"type": "string"},
                          "description": "Caminhos locais ou URLs https de imagem, PDF, áudio ou vídeo."},
                "resolution": {"type": "string", "enum": list(RESOLUCOES),
                               "description": "Detalhe de imagem/vídeo (custo em tokens)."},
                "questions": {
                    "type": "array",
                    "description": "1 a 1000 perguntas.",
                    "items": {
                        "type": "object",
                        "properties": {
                            "id": {"type": "string", "description": "Chave da resposta."},
                            "type": {"type": "string", "enum": ["noul", "choice", "score"]},
                            "instructions": {"type": "string", "description": "A pergunta completa."},
                            "options": {"type": "array", "items": {"type": "string"},
                                        "description": "choice: 'chave: quando se aplica'."},
                            "levels": {"type": "array", "items": {"type": "string"},
                                       "description": "score: níveis do pior (0) ao melhor."},
                            "true_description": {"type": "string", "description": "noul: o que conta como sim."},
                            "false_description": {"type": "string", "description": "noul: o que conta como não."},
                        },
                        "required": ["type", "instructions"],
                    },
                },
            },
            "required": ["questions"],
        },
    },
]
EXECUTORES = {"decide": tool_decide, "ui_check": tool_ui_check, "rank": tool_rank}


def executar(nome, args):
    if nome not in EXECUTORES:
        raise ErroTool(f"tool desconhecida: {nome}")
    if not isinstance(args, dict):
        raise ErroTool("argumentos devem ser um objeto")
    return EXECUTORES[nome](args)


def como_texto(resultado):
    return json.dumps(resultado, ensure_ascii=False, indent=1)


# ── JSON-RPC sobre stdio ─────────────────────────────────
def responder(msg_id, result=None, error=None):
    out = {"jsonrpc": "2.0", "id": msg_id}
    if error is not None:
        out["error"] = error
    else:
        out["result"] = result
    sys.stdout.write(json.dumps(out, ensure_ascii=False) + "\n")
    sys.stdout.flush()


def tratar(msg):
    metodo = msg.get("method")
    msg_id = msg.get("id")
    if metodo and metodo.startswith("notifications/"):
        return
    if metodo == "initialize":
        responder(msg_id, {
            "protocolVersion": PROTOCOL_VERSION,
            "capabilities": {"tools": {}},
            "serverInfo": {"name": SERVER_NAME, "version": SERVER_VERSION},
        })
    elif metodo == "tools/list":
        responder(msg_id, {"tools": TOOLS})
    elif metodo == "ping":
        responder(msg_id, {})
    elif metodo == "tools/call":
        params = msg.get("params") or {}
        try:
            r = executar(params.get("name"), params.get("arguments") or {})
            responder(msg_id, {"content": [{"type": "text", "text": como_texto(r)}]})
        except Exception as e:  # noqa: BLE001
            # Vira resultado de erro da tool (não erro JSON-RPC) para o modelo
            # poder reagir em vez de o cliente quebrar.
            msg = str(e) if isinstance(e, ErroTool) else f"{type(e).__name__}: {e}"
            responder(msg_id, {"content": [{"type": "text", "text": f"Erro: {msg[:300]}"}],
                               "isError": True})
    elif msg_id is not None:
        responder(msg_id, error={"code": -32601, "message": f"método não suportado: {metodo}"})


def servir():
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
                responder(msg_id, error={"code": -32603, "message": str(e)[:300]})


# ── Linha de comando (ai gd) ─────────────────────────────
def imprimir_ui(r):
    print(r["resumo"])
    for c in r["capturas"]:
        print(f"\n▸ {c['captura']}")
        if "erro" in c:
            print(f"  erro: {c['erro']}")
            continue
        if c.get("fidelidade"):
            f = c["fidelidade"]
            print(f"  fidelidade à referência: {f['nota']}/{f['de']} — {f['nivel']}")
        for x in c["falhas"]:
            print(f"  ✗ {x['p_ok']:.2f}  {x['criterio']}")
        for x in c["incertos"]:
            p = "  ?  " if x["p_ok"] is None else f"{x['p_ok']:.2f}"
            print(f"  ? {p}  {x['criterio']}")
        print(f"  ✓ {c['ok']} ok   ({c['tokens']} tokens, {c['ms']} ms)")


def cli(argv):
    if not argv or argv[0] in ("-h", "--help"):
        print(__doc__)
        return 0
    cmd, resto = argv[0], argv[1:]
    try:
        if cmd == "ping":
            r = tool_decide({
                "input": "O céu estava azul e sem nuvens durante a tarde.",
                "questions": [{"id": "ceu", "type": "noul",
                               "instructions": "O texto descreve o céu?"}],
            })
            p = p_sim(r["answers"].get("ceu") or {})
            if p is None:
                print("Erro: a API respondeu sem probabilidade", file=sys.stderr)
                return 1
            print(f"ok: {r['ms']} ms, {r['tokens']} tokens, P(sim)={p:.2f} (esperado alto)")
            return 0
        if cmd == "call":
            if len(resto) != 2:
                print("uso: call <tool> '<json>'", file=sys.stderr)
                return 2
            print(como_texto(executar(resto[0], json.loads(resto[1]))))
            return 0
        if cmd == "ui":
            args = {"screenshots": [], "checks": []}
            i = 0
            while i < len(resto):
                a = resto[i]
                if a in ("-c", "--check") and i + 1 < len(resto):
                    args["checks"].append(resto[i + 1]); i += 2
                elif a == "--ref" and i + 1 < len(resto):
                    args["reference"] = resto[i + 1]; i += 2
                elif a == "--context" and i + 1 < len(resto):
                    args["context"] = resto[i + 1]; i += 2
                elif a == "--no-defaults":
                    args["defaults"] = False; i += 1
                else:
                    args["screenshots"].append(a); i += 1
            r = tool_ui_check(args)
            imprimir_ui(r)
            return 1 if any(c.get("falhas") or "erro" in c for c in r["capturas"]) else 0
        if cmd == "ask":
            if not resto:
                print('uso: ask "pergunta de sim/não" [arquivos...]', file=sys.stderr)
                return 2
            pergunta, arquivos = resto[0], resto[1:]
            if not arquivos:
                raise ErroTool("passe ao menos um arquivo (ou use `call decide` com input)")
            r = tool_decide({"files": arquivos, "questions": [
                {"id": "r", "type": "noul", "instructions": pergunta}]})
            p = p_sim(r["answers"].get("r") or {})
            if p is None:
                print("Erro: a API respondeu sem probabilidade", file=sys.stderr)
                return 1
            print(f"P(sim) = {p:.2f}  ({r['tokens']} tokens, {r['ms']} ms)")
            return 0
    except ErroTool as e:
        print(f"Erro: {e}", file=sys.stderr)
        return 1
    except json.JSONDecodeError as e:
        print(f"Erro: JSON inválido: {e}", file=sys.stderr)
        return 2
    print(f"comando desconhecido: {cmd}", file=sys.stderr)
    return 2


def stdio_utf8():
    for nome, erros in (("stdin", "replace"), ("stdout", "strict"), ("stderr", "replace")):
        fluxo = getattr(sys, nome)
        try:
            fluxo.reconfigure(encoding="utf-8", errors=erros)
        except (AttributeError, ValueError):
            pass


if __name__ == "__main__":
    stdio_utf8()
    if len(sys.argv) > 1:
        sys.exit(cli(sys.argv[1:]))
    servir()
