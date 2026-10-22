# Avant: alterações mínimas no cli-anything-alexa v0.13.0 (session.py) para
# rodar dentro de um app do Home Assistant. Cada troca exige o trecho exato;
# se o código original mudar, o build falha em vez de aplicar errado.
#
# 1. proxy_host: o CLI anuncia http://127.0.0.1 quando escuta em 0.0.0.0, e o
#    AlexaProxy reescreve os links para esse endereço (aponta para o PC do
#    usuário). ALEXA_PROXY_PUBLIC_HOST define o IP da LAN.
# 2. Sessão OAuth: o CLI só grava cookies; o alexapy >=1.32 entra pelo refresh
#    token + serial do "aparelho" registrado (o HA guarda isso na config entry).
#    Sem eles a próxima execução falha e o alexapy apaga os cookies. Aqui o
#    token e o serial vão para <config_dir>/avant_oauth.<email>.json (0600,
#    dentro de /data) e são reaproveitados em toda execução.
import pathlib
import cli_anything.alexa.core.session as s

p = pathlib.Path(s.__file__)
src = p.read_text(encoding="utf-8")


def swap(old, new, count=1):
    global src
    assert src.count(old) == count, f"trecho não encontrado {count}x: {old[:60]!r}"
    src = src.replace(old, new)


# 1. IP público do proxy
swap('shown = "127.0.0.1" if host in (BIND_ALL_HOST, "", None) else host',
     'shown = (os.environ.get("ALEXA_PROXY_PUBLIC_HOST") or "127.0.0.1") '
     'if host in (BIND_ALL_HOST, "", None) else host')

# 2a. build_login reaproveita token + serial salvos
swap('''        make_outputpath(config_dir, create=create_dir),
        otp_secret=otp_secret,
    )''', '''        make_outputpath(config_dir, create=create_dir),
        otp_secret=otp_secret,
        **_avant_oauth_kwargs(config_dir, email),
    )''')

# 2b. grava token + serial logo após o login no navegador
swap('''        await login.finalize_login()
''', '''        await login.finalize_login()
        _avant_save_oauth(login, config_dir, email)
''')

# 2c. sem cookie, mas com refresh token: deixa o alexapy entrar pelo token
swap('''        cookies = await login.load_cookie()
        if not cookies:
            raise AlexaSessionError(''', '''        cookies = await login.load_cookie()
        if not cookies and not login.refresh_token:
            raise AlexaSessionError(''')
swap('''        cookies = await login.load_cookie()
        if not cookies:
            return False''', '''        cookies = await login.load_cookie()
        if not cookies and not login.refresh_token:
            return False''')

# 2d. tokens renovados: regrava após cada validação bem-sucedida
swap('''            if await login.test_loggedin(cookies=cookies):
                break''', '''            if await login.test_loggedin(cookies=cookies):
                _avant_save_oauth(login, config_dir, email)
                break''')
swap('''            if await login.test_loggedin(cookies=cookies):
                return True''', '''            if await login.test_loggedin(cookies=cookies):
                _avant_save_oauth(login, config_dir, email)
                return True''')

src += '''

# --- Avant: persistência da sessão OAuth (ver patch_cli.py) -----------------
_AVANT_OAUTH_KEYS = ("access_token", "refresh_token", "mac_dms", "expires_in")


def _avant_oauth_path(config_dir, email):
    return Path(config_dir) / f"avant_oauth.{_sanitize_email_for_filename(email)}.json"


def _avant_oauth_kwargs(config_dir, email):
    import json
    try:
        data = json.loads(_avant_oauth_path(config_dir, email).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}
    oauth = {k: data.get(k) for k in _AVANT_OAUTH_KEYS if data.get(k)}
    kwargs = {"oauth": oauth} if oauth else {}
    if data.get("uuid"):
        kwargs["uuid"] = data["uuid"]
    return kwargs


def _avant_save_oauth(login, config_dir, email):
    import json
    if not getattr(login, "refresh_token", None):
        return
    data = {k: getattr(login, k, None) for k in _AVANT_OAUTH_KEYS}
    data["uuid"] = getattr(login, "uuid", None)
    path = _avant_oauth_path(config_dir, email)
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".tmp")
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        json.dump(data, fh)
    os.replace(tmp, path)
'''
p.write_text(src, encoding="utf-8")
print("patch Avant aplicado em", p)

# 3. Rastreio da sessão (avant6): se AVANT_TRACE_FILE estiver definido, grava
#    em JSON Lines cada etapa do alexapy (resultado + presença sim/não de
#    tokens) e cada chamada HTTP (método, host, caminho, status). Nunca grava
#    valores de cookies/tokens, query strings ou corpos.
src = p.read_text(encoding="utf-8")
src += '''

# --- Avant: rastreio sem segredos (ver patch_cli.py) ------------------------
def _avant_install_trace():
    trace = os.environ.get("AVANT_TRACE_FILE")
    if not trace:
        return
    import functools
    import json
    import time

    import aiohttp
    from alexapy import AlexaLogin
    from yarl import URL

    def log(event):
        event["t"] = round(time.time(), 1)
        with open(trace, "a", encoding="utf-8") as fh:
            print(json.dumps(event, ensure_ascii=False), file=fh)

    def state(login):
        keys = ("access_token", "refresh_token", "authorization_code", "code_verifier", "mac_dms")
        return {k: bool(getattr(login, k, None)) for k in keys}

    def files(login):
        out = []
        for f in getattr(login, "_cookiefile", None) or []:
            if f:
                out.append([os.path.basename(f), os.path.getsize(f) if os.path.exists(f) else None])
        return out

    def wrap(name):
        orig = getattr(AlexaLogin, name, None)
        if orig is None:
            return

        @functools.wraps(orig)
        async def wrapper(self, *args, **kwargs):
            before = state(self)
            try:
                result = await orig(self, *args, **kwargs)
            except BaseException as exc:
                log({"etapa": name, "erro": type(exc).__name__, "antes": before, "depois": state(self)})
                raise
            shown = result if isinstance(result, bool) or result is None else type(result).__name__
            event = {"etapa": name, "resultado": shown, "antes": before, "depois": state(self)}
            if name in ("finalize_login", "save_cookiefile", "reset"):
                event["arquivos"] = files(self)
            log(event)
            return result

        setattr(AlexaLogin, name, wrapper)

    for name in ("login", "test_loggedin", "get_tokens", "register_capabilities",
                 "exchange_token_for_cookies", "get_csrf", "refresh_access_token",
                 "finalize_login", "save_cookiefile", "reset"):
        wrap(name)

    orig_request = aiohttp.ClientSession._request

    async def request(self, method, str_or_url, *args, **kwargs):
        resp = await orig_request(self, method, str_or_url, *args, **kwargs)
        try:
            u = URL(str(str_or_url))
            log({"http": method, "host": u.host, "path": u.path, "status": resp.status})
        except Exception:  # noqa: BLE001 - o rastreio nunca derruba o CLI
            pass
        return resp

    aiohttp.ClientSession._request = request
    log({"inicio": "rastreio ativo"})


_avant_install_trace()
'''
p.write_text(src, encoding="utf-8")
print("rastreio Avant aplicado")
