#!/usr/bin/env python3
"""Qwen Code 1.0 no T3 com todos os modelos do settings.json.

No modo ACP o Qwen Code 1.0.0-preview(.1) anuncia só o `model.name` do
settings.json e recusa `session/set_model` para qualquer outro: o adaptador de
modelos do ACP devolve fixo `[getModel()]`. O `-m` e o `--settings` também
são ignorados no ACP. Este proxy fica entre o T3 e o `qwen --acp`:

- anuncia ao T3 os modelos dos `providers` do settings.json (Qwen, DeepSeek...);
- roda um `qwen --acp` por modelo, cada um com QWEN_CONFIG_DIR próprio: uma
  cópia do settings.json com aquele modelo como padrão e a lista do provider
  reduzida a ele. O resto da pasta é link para a ~/.qwen, então sessões,
  memória, skills e MCP são os mesmos;
- na troca de modelo, fecha a sessão no processo antigo e a retoma
  (`session/resume`) no processo do modelo novo, com o histórico. A lista
  reduzida importa: ao retomar, o Qwen volta para o modelo salvo na sessão se
  ele ainda estiver na lista.

Modelos embutidos do provider (ex.: qwen3.8-max do type "alibaba") ficam fora
da lista: o Qwen sempre os restaura ao retomar, então a troca não pegaria. O
proxy repassa ao T3 o modelo que o Qwen informa, nunca o que pediu.

Uso: qwen-acp-proxy.py <caminho do qwen> [args do qwen, ex. --acp]
Só stdlib.
"""

import itertools
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import threading

SERVER_VERSION = "1.0.1"

# Métodos que abrem sessão: a resposta traz models/configOptions.
OPEN_METHODS = ("session/new", "session/load", "session/resume", "session/fork")
# Pastas que precisam existir na ~/.qwen antes do link (senão o Qwen as cria
# dentro da pasta do modelo e as sessões se separam).
SHARED_DIRS = ("projects", "memory", "skills", "agents", "commands", "extensions",
               "plans", "agent-memory", "todos", "tmp")
PRIVATE_FILES = ("settings.json", "settings.local.json")


def log(msg):
    try:
        sys.stderr.write(f"[qwen-acp-proxy] {msg}\n")
        sys.stderr.flush()
    except (OSError, ValueError):
        pass


def rpc_error(req_id, code, message):
    return {"jsonrpc": "2.0", "id": req_id, "error": {"code": code, "message": message}}


def base_dir():
    d = os.environ.get("QWEN_CONFIG_DIR") or os.path.join(os.path.expanduser("~"), ".qwen")
    return os.path.abspath(os.path.expanduser(d))


def state_dir():
    d = os.environ.get("QWEN_ACP_PROXY_DIR") or os.path.join(
        os.path.expanduser("~"), ".local", "share", "ai-launcher", "qwen-acp")
    return os.path.abspath(os.path.expanduser(d))


def load_settings(base):
    with open(os.path.join(base, "settings.json"), encoding="utf-8") as f:
        data = json.load(f)
    if not isinstance(data, dict):
        raise ValueError("settings.json não é um objeto")
    return data


def configured_models(settings):
    """Modelos dos providers, no formato "provider/modelo", com o padrão primeiro."""
    ids = []
    providers = settings.get("providers") if isinstance(settings.get("providers"), dict) else {}
    for pid, prov in providers.items():
        if not isinstance(prov, dict) or prov.get("enabled") is False:
            continue
        for m in prov.get("models") or []:
            mid = m.get("model") if isinstance(m, dict) else m
            if isinstance(m, dict) and m.get("enabled") is False:
                continue
            if isinstance(mid, str) and mid.strip():
                key = f"{pid}/{mid.strip()}"
                if key not in ids:
                    ids.append(key)
    model = settings.get("model") if isinstance(settings.get("model"), dict) else {}
    default = model.get("name") if isinstance(model.get("name"), str) else ""
    if default in ids:
        ids.remove(default)
    if default:
        ids.insert(0, default)
    return ids, default


def model_settings(settings, model):
    """settings.json da pasta de um modelo: ele como padrão e sozinho na lista."""
    data = json.loads(json.dumps(settings))
    pid, _, mid = model.partition("/")
    cur = data.get("model") if isinstance(data.get("model"), dict) else {}
    cur["name"] = model
    data["model"] = cur
    providers = data.get("providers") if isinstance(data.get("providers"), dict) else {}
    prov = dict(providers.get(pid) or {})
    keep = [m for m in prov.get("models") or [] if isinstance(m, dict) and m.get("model") == mid]
    prov["models"] = keep or [{"model": mid}]
    data["providers"] = {pid: prov}
    return data


# O T3 sobe várias instâncias do provider ao mesmo tempo (status, sessões), e
# todas preparam a mesma pasta: temporário único e "já existe" não é erro.
def write_private(path, data):
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), prefix=".settings-")
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as f:
            json.dump(data, f, indent=2, ensure_ascii=False)
            f.write("\n")
        os.chmod(tmp, 0o600)
        os.replace(tmp, path)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def link(src, dst):
    if os.path.lexists(dst):
        return
    try:
        try:
            os.symlink(src, dst, target_is_directory=os.path.isdir(src))
            return
        except FileExistsError:
            raise
        except (OSError, NotImplementedError):
            pass
        # Windows sem permissão de symlink: junção para pasta, hardlink para arquivo.
        if os.name == "nt" and os.path.isdir(src):
            import _winapi
            _winapi.CreateJunction(src, dst)
        elif os.path.isfile(src):
            try:
                os.link(src, dst)
            except FileExistsError:
                raise
            except OSError:
                shutil.copy2(src, dst)
    except FileExistsError:
        return  # outra instância criou primeiro


def prepare_model_dir(base, state, settings, model):
    for d in SHARED_DIRS:
        os.makedirs(os.path.join(base, d), exist_ok=True)
    pasta = os.path.join(state, re.sub(r"[^A-Za-z0-9._-]+", "_", model))
    os.makedirs(pasta, mode=0o700, exist_ok=True)
    try:
        os.chmod(pasta, 0o700)
    except OSError:
        pass
    write_private(os.path.join(pasta, "settings.json"), model_settings(settings, model))
    for entry in os.listdir(base):
        if entry not in PRIVATE_FILES:
            link(os.path.join(base, entry), os.path.join(pasta, entry))
    return pasta


class Child:
    """Um `qwen --acp` com o modelo fixo na pasta de config dele."""

    def __init__(self, proxy, model, config_dir):
        self.proxy = proxy
        self.model = model
        env = dict(os.environ)
        env["QWEN_CONFIG_DIR"] = config_dir
        self.proc = subprocess.Popen([proxy.qwen] + proxy.qwen_args, stdin=subprocess.PIPE,
                                     stdout=subprocess.PIPE, env=env)
        self.wlock = threading.Lock()
        self.waiters = {}
        self.dead = False
        threading.Thread(target=self._reader, daemon=True).start()

    def write(self, msg):
        data = (json.dumps(msg, ensure_ascii=False) + "\n").encode("utf-8")
        with self.wlock:
            self.proc.stdin.write(data)
            self.proc.stdin.flush()

    def call(self, method, params, timeout=180):
        req_id = f"qwen-acp-proxy-{next(self.proxy.ids)}"
        ev = threading.Event()
        slot = [ev, None]
        self.waiters[req_id] = slot
        try:
            self.write({"jsonrpc": "2.0", "id": req_id, "method": method, "params": params})
        except OSError as e:
            self.waiters.pop(req_id, None)
            return {"error": {"code": -32603, "message": f"qwen ({self.model}) fora do ar: {e}"}}
        if not ev.wait(timeout):
            self.waiters.pop(req_id, None)
            return {"error": {"code": -32603, "message": f"qwen ({self.model}) não respondeu {method}"}}
        return slot[1]

    def _reader(self):
        for line in iter(self.proc.stdout.readline, b""):
            try:
                msg = json.loads(line.decode("utf-8"))
            except ValueError:
                continue
            if not isinstance(msg, dict):
                continue
            slot = self.waiters.pop(msg.get("id"), None) if "method" not in msg else None
            if slot is not None:
                slot[1] = msg
                slot[0].set()
            else:
                self.proxy.from_child(self, msg)
        self.dead = True
        for slot in list(self.waiters.values()):
            slot[1] = {"error": {"code": -32603, "message": f"qwen ({self.model}) encerrou"}}
            slot[0].set()
        self.proxy.child_exited(self)

    def stop(self):
        self.dead = True
        try:
            self.proc.stdin.close()
        except OSError:
            pass
        try:
            self.proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            self.proc.kill()


class Session:
    def __init__(self, child, csid, params):
        self.child = child
        self.csid = csid
        self.model = child.model
        self.params = {k: params[k] for k in ("cwd", "mcpServers", "additionalDirectories") if k in params}
        self.mode = None


class Proxy:
    def __init__(self, qwen, qwen_args, settings, models, default):
        self.qwen = qwen
        self.qwen_args = qwen_args
        self.settings = settings
        self.models = models
        self.default = default
        self.base = base_dir()
        self.state = state_dir()
        self.ids = itertools.count(1)
        self.lock = threading.RLock()
        self.out_lock = threading.Lock()
        self.children = {}
        self.sessions = {}      # sessionId do T3 → Session
        self.by_child = {}      # (id(child), sessionId no qwen) → sessionId do T3
        self.t3_calls = {}      # id da requisição do T3 → (método, params)
        self.agent_calls = {}   # id que o T3 vê → (child, id original)
        self.init_params = None

    # --- saída para o T3 ---------------------------------------------------
    def send(self, msg):
        data = json.dumps(msg, ensure_ascii=False) + "\n"
        with self.out_lock:
            sys.stdout.write(data)
            sys.stdout.flush()

    def label(self, model):
        return model.split("/", 1)[-1]

    def widen(self, obj):
        """Troca a lista de um modelo só pela lista completa, mantendo o atual."""
        if not isinstance(obj, dict):
            return None
        current = None
        models = obj.get("models")
        if isinstance(models, dict):
            current = models.get("currentModelId") or current
            lista = list(self.models)
            if current and current not in lista:
                lista.insert(0, current)
            models["availableModels"] = [{"modelId": m, "name": self.label(m)} for m in lista]
        for opt in obj.get("configOptions") or []:
            if isinstance(opt, dict) and opt.get("id") == "model":
                cur = opt.get("currentValue") or current
                current = cur
                lista = list(self.models)
                if cur and cur not in lista:
                    lista.insert(0, cur)
                opt["options"] = [{"value": m, "name": self.label(m)} for m in lista]
        return current

    # --- processos ---------------------------------------------------------
    def child_for(self, model):
        with self.lock:
            child = self.children.get(model)
            if child is not None and not child.dead:
                return child
            pasta = prepare_model_dir(self.base, self.state, self.settings, model)
            child = Child(self, model, pasta)
            self.children[model] = child
        if self.init_params is not None and model != self.default:
            r = child.call("initialize", self.init_params, timeout=120)
            if "error" in r:
                child.stop()
                raise RuntimeError(r["error"].get("message") or "initialize falhou")
        return child

    def child_exited(self, child):
        with self.lock:
            if self.children.get(child.model) is child:
                del self.children[child.model]
        if child.model == self.default and not getattr(self, "closing", False):
            code = child.proc.poll()
            log(f"qwen do modelo padrão encerrou (código {code})")
            os._exit(code if isinstance(code, int) and code > 0 else 1)

    def maybe_stop(self, child):
        if child.model == self.default:
            return
        with self.lock:
            if any(s.child is child for s in self.sessions.values()):
                return
            if self.children.get(child.model) is child:
                del self.children[child.model]
        child.stop()

    # --- sessões -----------------------------------------------------------
    def register(self, t3sid, child, csid, params):
        with self.lock:
            s = self.sessions.get(t3sid)
            if s is not None:
                self.by_child.pop((id(s.child), s.csid), None)
            s = Session(child, csid, params)
            self.sessions[t3sid] = s
            self.by_child[(id(child), csid)] = t3sid
            return s

    def t3_sid(self, child, csid):
        return self.by_child.get((id(child), csid), csid)

    def route(self, params):
        """Processo e sessionId do qwen para uma requisição do T3."""
        sid = params.get("sessionId") if isinstance(params, dict) else None
        s = self.sessions.get(sid) if sid else None
        if s is not None:
            return s.child, s.csid
        return self.child_for(self.default), sid

    # --- T3 → qwen ---------------------------------------------------------
    def from_t3(self, msg):
        method = msg.get("method")
        if method is None:  # resposta a uma requisição que o qwen fez ao T3
            alvo = self.agent_calls.pop(msg.get("id"), None)
            if alvo is not None:
                child, orig = alvo
                try:
                    child.write({**msg, "id": orig})
                except OSError:
                    pass
            return
        params = msg.get("params") if isinstance(msg.get("params"), dict) else {}
        req_id = msg.get("id")
        if method == "initialize":
            self.init_params = params
        target = None
        if method == "session/set_model":
            target = params.get("modelId")
        elif method == "session/set_config_option" and params.get("configId") == "model":
            target = params.get("value")
        s = self.sessions.get(params.get("sessionId"))
        if req_id is not None and target is not None and not (s is not None and s.model == target):
            # Modelo diferente do processo atual: o qwen recusaria; o proxy troca.
            threading.Thread(target=self.switch, args=(req_id, method, params.get("sessionId"), target),
                             daemon=True).start()
            return
        if method == "session/set_mode" or (method == "session/set_config_option" and params.get("configId") == "mode"):
            s = self.sessions.get(params.get("sessionId"))
            if s is not None:
                s.mode = params.get("modeId") or params.get("value")
        try:
            child, csid = self.route(params)
        except Exception as e:  # noqa: BLE001 - erro ao subir o qwen vira erro JSON-RPC
            if req_id is not None:
                self.send(rpc_error(req_id, -32603, f"não consegui iniciar o qwen: {e}"))
            return
        out = dict(msg)
        if csid is not None and "sessionId" in params:
            out["params"] = {**params, "sessionId": csid}
        if req_id is not None:
            self.t3_calls[req_id] = (method, params, child)
        try:
            child.write(out)
        except OSError as e:
            self.t3_calls.pop(req_id, None)
            if req_id is not None:
                self.send(rpc_error(req_id, -32603, f"qwen ({child.model}) fora do ar: {e}"))

    # --- qwen → T3 ---------------------------------------------------------
    def from_child(self, child, msg):
        method = msg.get("method")
        params = msg.get("params") if isinstance(msg.get("params"), dict) else None
        if params is not None and isinstance(params.get("sessionId"), str):
            msg = {**msg, "params": {**params, "sessionId": self.t3_sid(child, params["sessionId"])}}
            params = msg["params"]
        if method is not None and "id" in msg:  # requisição do qwen ao T3 (permissão, fs...)
            novo = next(self.ids)
            self.agent_calls[novo] = (child, msg["id"])
            self.send({**msg, "id": novo})
            return
        if method is not None:  # notificação
            if method == "session/update" and params is not None:
                self.widen(params.get("update"))
            self.send(msg)
            return
        call = self.t3_calls.pop(msg.get("id"), None)
        if call is not None and isinstance(msg.get("result"), dict):
            m, p, _ = call
            res = msg["result"]
            if m in OPEN_METHODS:
                csid = res.get("sessionId") or p.get("sessionId")
                if csid:
                    s = self.register(csid if m in ("session/new", "session/fork") else p.get("sessionId", csid),
                                      child, csid, p if m != "session/fork" else self._fork_params(p))
                    s.model = self.widen(res) or child.model
            elif m == "session/set_config_option":
                self.widen(res)
            elif m in ("session/close", "session/delete"):
                with self.lock:
                    s = self.sessions.pop(p.get("sessionId"), None)
                    if s is not None:
                        self.by_child.pop((id(s.child), s.csid), None)
                if s is not None:
                    self.maybe_stop(s.child)
        self.send(msg)

    def _fork_params(self, p):
        s = self.sessions.get(p.get("sessionId"))
        return {**(s.params if s else {}), **p}

    # --- troca de modelo ---------------------------------------------------
    def switch(self, req_id, method, sid, target):
        try:
            self._switch(req_id, method, sid, target)
        except Exception as e:  # noqa: BLE001 - qualquer falha vira erro para o T3
            self.send(rpc_error(req_id, -32603, f"troca de modelo falhou: {e}"))

    def _switch(self, req_id, method, sid, target):
        s = self.sessions.get(sid)
        if s is None:
            self.send(rpc_error(req_id, -32602, f"sessão desconhecida: {sid}"))
            return
        if target not in self.models:
            self.send(rpc_error(req_id, -32602, f"Invalid or unavailable model: {target}"))
            return
        old, old_csid = s.child, s.csid
        new = self.child_for(target)
        r = new.call("session/resume", {**s.params, "sessionId": old_csid})
        csid = old_csid
        if "error" in r:
            # Sessão sem nenhum prompt ainda não foi gravada: abre outra no modelo novo.
            r = new.call("session/new", dict(s.params))
            csid = (r.get("result") or {}).get("sessionId")
        if "error" in r or not csid:
            erro = (r.get("error") or {}).get("message") or "sem sessionId"
            self.send(rpc_error(req_id, -32603, f"não consegui abrir a sessão em {target}: {erro}"))
            self.maybe_stop(new)
            return
        # Um escritor por histórico: o processo antigo solta a sessão.
        old.call("session/close", {"sessionId": old_csid}, timeout=30)
        res = r["result"]
        with self.lock:
            self.by_child.pop((id(old), old_csid), None)
            s.child, s.csid = new, csid
            self.by_child[(id(new), csid)] = sid
        if s.mode:
            m = new.call("session/set_mode", {"sessionId": csid, "modeId": s.mode}, timeout=30)
            for opt in res.get("configOptions") or []:
                if "error" not in m and isinstance(opt, dict) and opt.get("id") == "mode":
                    opt["currentValue"] = s.mode
        real = self.widen(res) or target
        s.model = real
        self.maybe_stop(old)
        self.send({"jsonrpc": "2.0", "method": "session/update", "params": {
            "sessionId": sid, "update": {"sessionUpdate": "config_option_update",
                                         "configOptions": res.get("configOptions") or []}}})
        if real != target:
            self.send(rpc_error(req_id, -32603, f"o Qwen manteve o modelo salvo nesta conversa ({real}); "
                                                f"abra uma conversa nova para usar {target}"))
            return
        self.send({"jsonrpc": "2.0", "id": req_id, "result": {} if method == "session/set_model"
                   else {"configOptions": res.get("configOptions") or []}})

    # --- laço principal ----------------------------------------------------
    def run(self):
        self.child_for(self.default)
        for line in sys.stdin:
            line = line.strip()
            if not line:
                continue
            try:
                msg = json.loads(line)
            except ValueError:
                continue
            if isinstance(msg, dict):
                self.from_t3(msg)
        self.closing = True
        for child in list(self.children.values()):
            child.stop()


def main(argv):
    if len(argv) < 2:
        sys.stderr.write("uso: qwen-acp-proxy.py <qwen> [args do qwen]\n")
        return 2
    qwen, qwen_args = argv[1], argv[2:]
    for stream in (sys.stdin, sys.stdout):
        try:
            stream.reconfigure(encoding="utf-8", newline="\n")
        except (AttributeError, ValueError):
            pass
    try:
        settings = load_settings(base_dir())
        models, default = configured_models(settings)
    except (OSError, ValueError) as e:
        log(f"settings.json ilegível ({e}); rodando o qwen direto")
        models, default = [], ""
    if not default or len(models) < 2:
        # Nada a multiplexar: o qwen puro, sem camada no meio.
        if os.name == "nt":
            return subprocess.call([qwen] + qwen_args)
        os.execv(qwen, [qwen] + qwen_args)
    Proxy(qwen, qwen_args, settings, models, default).run()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
