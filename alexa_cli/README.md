# Avant Alexa CLI (app local para Home Assistant)

Empacota o `cli-anything-alexa` v0.13.0 (commit 5abfab9…, MIT) num app isolado.
Não instala nada no Python do Home Assistant Core.

## Instalação manual
1. Copie esta pasta para `/addons/alexa_cli` no HAOS. Use o compartilhamento `addons` do Samba ou o app Terminal & SSH.
2. Vá em Configurações → Apps → Loja → ⋮ → Verificar atualizações. O app aparece em "Apps locais".
3. Instale o app. A instalação compila a imagem e baixa o projeto do GitHub.

## Uso
Cada execução roda **um** comando de leitura da lista permitida e termina.
1. Escolha o comando em Configuração → `command`. Primeira execução obrigatória: `help`, que grava o `--help` real da versão instalada.
2. Clique em Iniciar.
3. Os resultados ficam em `/addon_configs/local_alexa_cli/output/`, sem cookies.
4. A sessão Amazon fica em `/data`, dentro do volume do app. Não fica na imagem nem em `.storage`.

## Login (somente LAN, temporário)
1. Em Rede, mapeie a porta 3001.
2. Preencha `email` e `proxy_host` (IP do HA na LAN).
   - Se já existir sessão salva, o login é recusado. Marque `refazer_login: true` só para substituir a sessão e desmarque depois.
   - Inicie o login **uma vez só**: um segundo `auth login` faz o alexapy apagar a sessão salva.
3. Rode `command: auth login` e abra `http://<IP-do-HA>:3001` na LAN.
3. Conclua o login no navegador, incluindo captcha ou 2FA. A senha nunca passa por linha de comando.
4. Depois do login, **remova o mapeamento da porta**.

Riscos: enquanto a porta está aberta, qualquer pessoa na LAN alcança a página de login da Amazon via proxy por até 600 s.

## Alterações no código original (`patch_cli.py`)
Aplicadas no build. Se o código original mudar, o build falha.
1. O proxy de login usa `proxy_host` em vez de `127.0.0.1`.
2. O refresh token OAuth e o serial do "aparelho" registrado ficam salvos em `/data/.config/cli-anything-alexa/avant_oauth.<email>.json`, com permissão 0600, e são reaproveitados em cada execução, como o HA faz. Sem isso, a sessão some na execução seguinte.
3. **Rastreio (avant6).** Exceto em `help`, cada execução grava `output/<data>-<comando>-rastreio.jsonl`. O arquivo registra cada etapa da alexapy (resultado e presença sim/não de cada token) e cada chamada HTTP (método, host, caminho, status). Não grava valores de cookie ou token, query strings nem corpos.

## Alterações na Alexa (avant9)
- `devices delete` exclui **somente** os applianceIds de `/addon_configs/local_alexa_cli/excluir.txt`.
- `groups plano` executa as linhas de `grupos.txt`, na ordem, uma ação por linha:
  - `add|GRUPO|endpointId` coloca o aparelho no cômodo;
  - `remove|GRUPO|endpointId` tira o aparelho do cômodo;
  - `create|GRUPO|endpointId` cria o cômodo (avant10). O endpointId é opcional e vira o primeiro membro;
  - `delete|GRUPO|` apaga o cômodo (avant10). Os aparelhos continuam na Alexa.
  - Para criar um cômodo e encher, use um `create` seguido de linhas `add` no mesmo arquivo.
- Sem `confirmar_alteracoes: true` os dois comandos fazem apenas simulação (dry-run). Depois de executar, desmarque a opção.
- `discover` e `groups set` não estão liberados. A Tuya pode recadastrar itens excluídos na próxima descoberta.

## Atualização remota (avant10)
- Se existir `/addon_configs/local_alexa_cli/run.sh`, o app usa esse script no lugar do embutido na imagem.
- Essa pasta é editável pelo File editor, inclusive fora da rede do cliente pelo acesso remoto do HA. Assim, ajustes de lógica não exigem copiar arquivos para `/addons` nem reconstruir o app.
- Mudanças no `config.yaml`, como novos comandos na lista ou novas opções, ainda exigem atualizar o app em `/addons`.
- Para voltar ao script embutido, apague o `run.sh` dessa pasta.

## Diagnóstico
`command: diagnostico` grava um JSON só com:
- nomes e tamanhos dos arquivos;
- se existe ou não um token salvo;
- os códigos HTTP do `users/me`.

Não grava nenhum valor de cookie ou token e não chama rotinas que apagam a sessão.

## Limites
- A API da Amazon não é oficial e o domínio `amazon.com.br` ainda não foi testado.
- Comandos que alteram algo (`--yes`, `groups set`, `devices prune`) **não** estão liberados nesta versão.
