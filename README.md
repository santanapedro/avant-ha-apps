# Avant Tecnologia – Apps para Home Assistant

Repositório público de apps (add-ons) da Avant para Home Assistant OS.

## Como instalar no Home Assistant
1. **Configurações → Apps → Loja de apps → ⋮ → Repositórios**.
2. Adicione `https://github.com/santanapedro/avant-ha-apps` e feche.
3. O app **Avant Alexa CLI** aparece na loja. Instale e siga o `alexa_cli/README.md`.

Para atualizar: **⋮ → Verificar atualizações** e depois **Atualizar** no app.

| App | Pasta | Descrição |
|---|---|---|
| Avant Alexa CLI | `alexa_cli/` | Inventário e administração da Alexa (cômodos, exclusões) via cli-anything-alexa |

Nada de cliente fica aqui: sessões Amazon ficam em `/data` do app, e listas/saídas em `/addon_configs/<slug>_alexa_cli`.
