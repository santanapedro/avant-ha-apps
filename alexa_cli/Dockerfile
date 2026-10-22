ARG BUILD_FROM
FROM ${BUILD_FROM}

# Versão fixada do cli-anything-alexa (tag v0.13.0)
ARG CLI_COMMIT=5abfab949b6e05350c2318aca9561ac8613d7b5e

# Dependências de compilação só durante o build; ambiente Python isolado do app
RUN apk add --no-cache --virtual .build-deps git build-base libffi-dev openssl-dev \
 && python3 -m venv /opt/venv \
 && /opt/venv/bin/pip install --no-cache-dir --upgrade pip \
 && /opt/venv/bin/pip install --no-cache-dir "git+https://github.com/jonwilliams84/cli-anything-alexa.git@${CLI_COMMIT}" \
 && apk del .build-deps

COPY patch_cli.py /tmp/patch_cli.py
COPY diag.py /opt/avant/diag.py
RUN /opt/venv/bin/python /tmp/patch_cli.py && rm /tmp/patch_cli.py

ENV PATH="/opt/venv/bin:${PATH}" \
    HOME=/data \
    PYTHONUNBUFFERED=1

COPY run.sh /run.sh
RUN chmod a+x /run.sh

CMD [ "/run.sh" ]
