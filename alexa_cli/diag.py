# Avant: diagnóstico da sessão Alexa SEM expor segredos. Mostra só nomes de
# arquivos, tamanhos, presença (sim/não) de tokens e códigos HTTP.
# Não chama login()/test_loggedin() do alexapy, que apagam os cookies ao falhar.
import asyncio
import json
import sys

from alexapy.const import CALL_VERSION
from cli_anything.alexa.core import session as s


async def main(email, url):
    out = {"email": email, "region": url}
    cfg = s.resolve_config_dir()
    out["config_dir"] = str(cfg)
    out["arquivos"] = sorted(
        (str(f.relative_to(cfg)), f.stat().st_size) for f in cfg.rglob("*") if f.is_file()
    ) if cfg.exists() else []
    login = s.build_login(email, url=url, config_dir=cfg, create_dir=False)
    try:
        out["tem_refresh_token"] = bool(login.refresh_token)
        out["tem_serial_salvo"] = bool(s._avant_oauth_kwargs(cfg, email).get("uuid"))
        cookies = await login.load_cookie()
        out["cookies_carregados"] = len(cookies or {})

        async def users_me(tag, use_cookies):
            for domain in (url, "amazon.com"):
                r = await login._session.get(
                    f"https://alexa.{domain}/api/users/me?platform=ios&version={CALL_VERSION}",
                    cookies=use_cookies, ssl=login._ssl, allow_redirects=False)
                try:
                    body = await r.json(content_type=None)
                except ValueError:
                    body = None
                ok = bool(body and str(body.get("email", "")).lower() == email.lower())
                out[f"{tag}_users_me_{domain}"] = {"http": r.status, "email_confere": ok}

        await users_me("cookies", cookies)
        if login.refresh_token:
            out["refresh_access_token"] = bool(await login.refresh_access_token())
            out["exchange_token_for_cookies"] = bool(await login.exchange_token_for_cookies())
            await users_me("token", None)
    finally:
        await login.close()
    print(json.dumps(out, indent=2, ensure_ascii=False))


asyncio.run(main(sys.argv[1], sys.argv[2]))
