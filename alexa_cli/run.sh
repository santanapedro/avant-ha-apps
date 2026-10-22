#!/usr/bin/with-contenv bashio
# Avant Alexa CLI - executa UM comando permitido e termina (startup: once).
# Nunca imprime o conteúdo dos resultados no log: a saída vai para /config/output.
set -u

# Atualização remota (avant10): se existir /config/run.sh (= /addon_configs/local_alexa_cli/run.sh,
# editável pelo File editor), ele substitui este script, sem precisar copiar nada para /addons.
# Mudanças no config.yaml (lista de comandos/opções) ainda exigem atualizar o app em /addons.
if [ -f /config/run.sh ] && [ -z "${AVANT_RUN_OVERRIDE:-}" ]; then
  export AVANT_RUN_OVERRIDE=1
  bashio::log.info "Usando /config/run.sh (versão editável remotamente)."
  exec /usr/bin/with-contenv bashio /config/run.sh
fi

COMMAND="$(bashio::config 'command')"
REGION="$(bashio::config 'region')"
# E-mail da conta Amazon (sem senha); o CLI pediria no terminal, que o app não tem
EMAIL_ARGS=()
if bashio::config.has_value 'email'; then
  EMAIL_ARGS=(--email "$(bashio::config 'email')")
fi
OUT_DIR="/config/output"
mkdir -p "${OUT_DIR}" /data
chmod 700 /data
# O alexapy grava o cookie em <config>/.storage/ (layout do HA) e, se a pasta
# não existir, falha em silêncio: o login "funciona" mas nada é salvo.
mkdir -p /data/.config/cli-anything-alexa/.storage
chmod 700 /data/.config/cli-anything-alexa /data/.config/cli-anything-alexa/.storage
STAMP="$(date +%Y%m%d-%H%M%S)"
SAFE_NAME="$(echo "${COMMAND}" | tr ' ' '_')"
OUT_FILE="${OUT_DIR}/${STAMP}-${SAFE_NAME}.json"
HELP_FILE="${OUT_DIR}/${STAMP}-help.txt"
# Rastreio sem segredos das etapas do alexapy (ver patch_cli.py, item 3)
if [ "${COMMAND}" != "help" ]; then
  export AVANT_TRACE_FILE="${OUT_DIR}/${STAMP}-${SAFE_NAME}-rastreio.jsonl"
fi

bashio::log.info "Comando solicitado: ${COMMAND} | região: ${REGION}"

case "${COMMAND}" in
  help)
    # Registra o --help real desta versão (sem dados pessoais)
    {
      echo "== versão"; cli-anything-alexa --version 2>&1 || true
      echo; echo "== cli-anything-alexa --help"; cli-anything-alexa --help 2>&1
      for g in auth devices groups scenes routines echos; do
        echo; echo "== ${g} --help"; cli-anything-alexa "${g}" --help 2>&1
      done
      for c in "auth login" "auth status" "auth whoami" "devices list" "devices duplicates" "devices capabilities" "groups list" "groups create" "groups add" "groups delete" "scenes list" "routines list" "echos list"; do
        echo; echo "== ${c} --help"
        # shellcheck disable=SC2086
        cli-anything-alexa ${c} --help 2>&1
      done
    } > "${HELP_FILE}"
    bashio::log.info "Ajuda gravada em ${HELP_FILE}"
    exit 0
    ;;
  "devices delete"|"groups plano")
    # Alterações na Alexa: só itens de uma lista fechada; simulação salvo confirmar_alteracoes
    YES=()
    if bashio::config.true 'confirmar_alteracoes'; then
      YES=(--yes)
      bashio::log.warning "EXECUÇÃO REAL (confirmar_alteracoes: true). Desmarque depois."
    else
      bashio::log.info "Simulação (dry-run): nada será alterado na Alexa."
    fi
    if [ "${COMMAND}" = "devices delete" ]; then
      LIST="/config/excluir.txt"
      mapfile -t IDS < <(sed 's/\r//; s/#.*//; s/[[:space:]]*$//; /^$/d' "${LIST}" 2>/dev/null)
      if [ ${#IDS[@]} -eq 0 ]; then bashio::log.error "Lista vazia ou ausente: ${LIST}"; exit 2; fi
      bashio::log.info "${#IDS[@]} applianceIds em ${LIST}"
      if cli-anything-alexa --json "${EMAIL_ARGS[@]}" --url "${REGION}" devices delete "${IDS[@]}" "${YES[@]}" > "${OUT_FILE}" 2> "${OUT_FILE}.err"; then
        bashio::log.info "OK: resultado em ${OUT_FILE}"
        rm -f "${OUT_FILE}.err"
        exit 0
      else
        RC=$?
        bashio::log.error "Falhou (código ${RC}). Detalhes em ${OUT_FILE}.err"
        exit "${RC}"
      fi
    fi
    # groups plano: uma ação por linha, executadas na ordem do arquivo
    #   add|GRUPO|endpointId      coloca o aparelho no cômodo
    #   remove|GRUPO|endpointId   tira o aparelho do cômodo
    #   create|GRUPO|endpointId   cria o cômodo (endpointId opcional: primeiro membro)
    #   delete|GRUPO|             apaga o cômodo (os aparelhos continuam na Alexa)
    LIST="/config/grupos.txt"
    mapfile -t LINES < <(sed 's/\r//; s/#.*//; s/[[:space:]]*$//; /^$/d' "${LIST}" 2>/dev/null)
    if [ ${#LINES[@]} -eq 0 ]; then bashio::log.error "Lista vazia ou ausente: ${LIST}"; exit 2; fi
    FAIL=0
    : > "${OUT_FILE}"
    for line in "${LINES[@]}"; do
      IFS='|' read -r ACTION GROUP ENDPOINT <<< "${line}"
      if [ -z "${GROUP}" ]; then bashio::log.error "Linha sem nome de cômodo: ${line}"; FAIL=1; continue; fi
      ARGS=()
      case "${ACTION}" in
        add|remove)
          if [ -z "${ENDPOINT}" ]; then bashio::log.error "Linha sem endpointId: ${line}"; FAIL=1; continue; fi
          ARGS=(--endpoint "${ENDPOINT}") ;;
        create)
          if [ -n "${ENDPOINT}" ]; then ARGS=(--endpoint "${ENDPOINT}"); fi ;;
        delete) ;;
        *) bashio::log.error "Ação inválida: ${line}"; FAIL=1; continue ;;
      esac
      echo "## ${ACTION} | ${GROUP} | ${ENDPOINT}" >> "${OUT_FILE}"
      if ! cli-anything-alexa --json "${EMAIL_ARGS[@]}" --url "${REGION}" groups "${ACTION}" "${GROUP}" "${ARGS[@]}" "${YES[@]}" >> "${OUT_FILE}" 2>> "${OUT_FILE}.err"; then
        bashio::log.error "Falhou: ${ACTION} ${GROUP}"
        FAIL=1
      fi
    done
    bashio::log.info "${#LINES[@]} linhas processadas; resultado em ${OUT_FILE}"
    [ -s "${OUT_FILE}.err" ] || rm -f "${OUT_FILE}.err"
    exit "${FAIL}"
    ;;
  diagnostico)
    if [ ${#EMAIL_ARGS[@]} -eq 0 ]; then bashio::log.error "Preencha o campo email."; exit 2; fi
    if /opt/venv/bin/python /opt/avant/diag.py "$(bashio::config 'email')" "${REGION}" > "${OUT_FILE}" 2> "${OUT_FILE}.err"; then
      bashio::log.info "Diagnóstico gravado em ${OUT_FILE}"
      rm -f "${OUT_FILE}.err"
      exit 0
    else
      RC=$?
      bashio::log.error "Diagnóstico falhou (código ${RC}). Detalhes em ${OUT_FILE}.err"
      exit "${RC}"
    fi
    ;;
  "auth login")
    bashio::log.warning "Login: abra http://<IP-do-HA>:<porta mapeada> na LAN e conclua login/captcha/2FA no navegador."
    bashio::log.warning "O proxy fecha sozinho em 600 s. Depois REMOVA o mapeamento da porta 3001."
    if [ ${#EMAIL_ARGS[@]} -eq 0 ]; then bashio::log.error "Preencha o campo email antes do login."; exit 2; fi
    if ! bashio::config.has_value 'proxy_host'; then bashio::log.error "Preencha o campo proxy_host com o IP do HA na LAN."; exit 2; fi
    # Um segundo login apaga a sessão salva (o alexapy limpa os cookies ao esperar o novo login)
    SESSION_DIR="/data/.config/cli-anything-alexa"
    if [ -n "$(find "${SESSION_DIR}" -type f \( -name 'alexa_media.*' -o -name 'avant_oauth.*' \) 2>/dev/null)" ] \
       && ! bashio::config.true 'refazer_login'; then
      bashio::log.error "Já existe sessão salva. Para substituí-la, marque refazer_login: true (e desmarque depois)."
      exit 2
    fi
    export ALEXA_PROXY_PUBLIC_HOST="$(bashio::config 'proxy_host')"
    bashio::log.info "Abra http://${ALEXA_PROXY_PUBLIC_HOST}:3001 na LAN."
    exec cli-anything-alexa auth login "${EMAIL_ARGS[@]}" --url "${REGION}" --host 0.0.0.0 --port 3001 --timeout 600
    ;;
  "auth status"|"auth whoami"|"auth ping"|"auth logout"|"devices list"|"devices duplicates"|"devices capabilities"|"groups list"|"scenes list"|"routines list"|"echos list")
    # shellcheck disable=SC2086
    if cli-anything-alexa --json "${EMAIL_ARGS[@]}" --url "${REGION}" ${COMMAND} > "${OUT_FILE}" 2> "${OUT_FILE}.err"; then
      bashio::log.info "OK: $(wc -c < "${OUT_FILE}") bytes gravados em ${OUT_FILE}"
      rm -f "${OUT_FILE}.err"
      exit 0
    else
      RC=$?
      bashio::log.error "Falhou (código ${RC}). Detalhes técnicos em ${OUT_FILE}.err"
      exit "${RC}"
    fi
    ;;
  *)
    bashio::log.error "Comando não permitido: ${COMMAND}"
    exit 2
    ;;
esac
