FROM node:16.15.1-bullseye-slim AS assets
LABEL maintainer="Nick Janetakis <nick.janetakis@gmail.com>"

WORKDIR /app/assets

RUN apt-get update \
  && apt-get install -y --no-install-recommends build-essential \
  && rm -rf /var/lib/apt/lists/* /usr/share/doc /usr/share/man \
  && apt-get clean \
  && mkdir -p /node_modules && chown node:node -R /node_modules /app

USER node

COPY --chown=node:node assets/package.json assets/*yarn* ./

RUN yarn install && yarn cache clean

ARG NODE_ENV="production"
ENV NODE_ENV="${NODE_ENV}" \
    PATH="${PATH}:/node_modules/.bin" \
    USER="node"

COPY --chown=node:node . ..

RUN if [ "${NODE_ENV}" != "development" ]; then \
  ../run yarn:build:js && ../run yarn:build:css; else mkdir -p /app/public; fi

CMD ["bash"]

###############################################################################

FROM python:3.10.5-slim-bullseye AS app
LABEL maintainer="Nick Janetakis <nick.janetakis@gmail.com>"

# `DJANGO_ENV` arg is used to make prod / dev builds:
ARG DJANGO_ENV \
  # Needed for fixing permissions of files created by Docker:
  UID=1000 \
  GID=1000 \
  DEBUG="false"

ENV DJANGO_ENV=${DJANGO_ENV} \
  # python:
  DEBUG="${DEBUG}" \
  PYTHONPATH="." \
  PATH="${PATH}:/home/python/.local/bin" \
  PYTHONFAULTHANDLER=1 \
  PYTHONUNBUFFERED=1 \
  PYTHONHASHSEED=random \
  PYTHONDONTWRITEBYTECODE=1 \
  # pip:
  PIP_NO_CACHE_DIR=1 \
  PIP_DISABLE_PIP_VERSION_CHECK=1 \
  PIP_DEFAULT_TIMEOUT=100 \
  # dockerize:
  DOCKERIZE_VERSION=v0.6.1 \
  # tini:
  TINI_VERSION=v0.19.0 \
  # poetry:
  POETRY_VERSION=1.1.14 \
  POETRY_NO_INTERACTION=1 \
  POETRY_VIRTUALENVS_CREATE=false \
  POETRY_CACHE_DIR='/var/cache/pypoetry' \
  POETRY_HOME='/usr/local'

SHELL ["/bin/bash", "-eo", "pipefail", "-c"]

WORKDIR /app

RUN apt-get update \
  && apt-get install -y --no-install-recommends build-essential bash brotli curl libpq-dev git\
  && rm -rf /var/lib/apt/lists/* /usr/share/doc /usr/share/man \
  && apt-get clean \
  && useradd --create-home python \
  && mkdir -p /public_collected public \
  && chown python:python -R /public_collected /app

RUN curl -sSL 'https://install.python-poetry.org' | python - \
  && poetry --version


COPY --chown=python:python ./poetry.lock ./pyproject.toml ./
COPY --chown=python:python bin/ ./bin

COPY --chown=python:python --from=assets /app/public /public
COPY --chown=python:python . .

WORKDIR /app/src

# RUN --mount=type=cache,target="$POETRY_CACHE_DIR" \
RUN  echo "$DJANGO_ENV" \
  && poetry version \
  # Install deps:
  && poetry run pip install -U pip \
  && poetry install \
    $(if [ "$DJANGO_ENV" = 'production' ]; then echo '--no-dev'; fi) \
    --no-interaction --no-ansi

RUN if [ "${DEBUG}" = "false" ]; then \
  SECRET_KEY=dummyvalue python3 manage.py collectstatic --no-input; \
    else mkdir -p /app/public_collected; fi

USER python

ENTRYPOINT ["/app/bin/docker-entrypoint-web"]

EXPOSE 8000

CMD ["gunicorn", "-c", "python:config.gunicorn", "config.wsgi"]
