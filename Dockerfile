# Self-contained production image for this LMS fork, built from local source
# instead of frappe_docker's Containerfile + a remote git clone (see cloudbuild.yaml
# for the previous approach). Mirrors .github/workflows/build.yml's app set
# (frappe + payments@version-15 + lms) but pulls "lms" from this working tree.
#
# Runs a single gunicorn process bound to $PORT (Cloud Run compatible). It does
# NOT include nginx, socketio, background workers or the scheduler — those need
# separate services if you need real-time updates or scheduled jobs.
#
# Build:
#   docker build -t lms .
# Deploy (Cloud Run "deploy from source" also just runs this Dockerfile):
#   gcloud run deploy lms --source . --region <region> \
#     --set-env-vars SITE_NAME=...,DB_HOST=...,DB_PASSWORD=...,DB_ROOT_PASSWORD=...,ADMIN_PASSWORD=...,REDIS_CACHE=...,REDIS_QUEUE=...
#
# Required at runtime (see docker/cloudrun-entrypoint.sh): a reachable MariaDB
# (e.g. Cloud SQL via VPC connector / Auth Proxy sidecar) and Redis (e.g.
# Memorystore). The site is (re)created from env vars on every cold start, so
# no persistent volume is required for `sites/`.

ARG PYTHON_VERSION=3.14
ARG DEBIAN_BASE=bookworm
ARG NODE_VERSION=24
ARG FRAPPE_BRANCH=version-16
ARG FRAPPE_PATH=https://github.com/frappe/frappe
ARG PAYMENTS_REPO=https://github.com/frappe/payments
ARG PAYMENTS_BRANCH=version-15

FROM python:${PYTHON_VERSION}-slim-${DEBIAN_BASE} AS base

ARG NODE_VERSION
ENV NVM_DIR=/home/frappe/.nvm
ENV NVM_SYMLINK_CURRENT=true
ENV PATH=${NVM_DIR}/current/bin:${PATH}

RUN useradd -ms /bin/bash frappe \
    && apt-get update \
    && apt-get install --no-install-recommends -y \
        curl git less jq wait-for-it \
        mariadb-client \
        # WeasyPrint runtime libs (PDF generation, e.g. LMS certificates)
        libpango-1.0-0 libharfbuzz0b libpangoft2-1.0-0 libpangocairo-1.0-0 \
        # Build deps for python packages with native extensions
        build-essential gcc pkg-config libffi-dev liblcms2-dev libldap2-dev \
        libmariadb-dev libsasl2-dev libtiff5-dev libwebp-dev libbz2-dev tk8.6-dev \
    && mkdir -p /home/frappe/.nvm \
    && curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.6/install.sh | bash \
    && . "$NVM_DIR/nvm.sh" \
    && nvm install ${NODE_VERSION} \
    && nvm alias default ${NODE_VERSION} \
    && npm install -g yarn \
    && rm -rf /var/lib/apt/lists/* "$NVM_DIR/.cache" \
    && pip3 install --no-cache-dir frappe-bench \
    && chown -R frappe:frappe /home/frappe/.nvm

FROM base AS builder

ARG FRAPPE_BRANCH
ARG FRAPPE_PATH
ARG PAYMENTS_REPO
ARG PAYMENTS_BRANCH

USER frappe
WORKDIR /home/frappe

# `bench get-app` needs its source to be a git repo. Snapshot the build
# context (this checkout, uncommitted changes included) into a throwaway
# local repo so it can be cloned in without network access.
COPY --chown=frappe:frappe . /home/frappe/lms-src
RUN cd /home/frappe/lms-src \
    && rm -rf .git \
    && git init -q \
    && git -c user.email=build@local -c user.name=build add -A \
    && git -c user.email=build@local -c user.name=build commit -q -m build

RUN bench init \
        --frappe-branch=${FRAPPE_BRANCH} \
        --frappe-path=${FRAPPE_PATH} \
        --no-procfile \
        --no-backups \
        --skip-redis-config-generation \
        --verbose \
        /home/frappe/frappe-bench \
    && cd /home/frappe/frappe-bench \
    && bench get-app payments --branch=${PAYMENTS_BRANCH} ${PAYMENTS_REPO} \
    && bench get-app lms /home/frappe/lms-src \
    && echo "{}" > sites/common_site_config.json \
    && rm -rf /home/frappe/lms-src \
    && find apps -mindepth 1 -path "*/.git" | xargs rm -fr

FROM base AS backend

USER frappe
COPY --from=builder --chown=frappe:frappe /home/frappe/frappe-bench /home/frappe/frappe-bench
WORKDIR /home/frappe/frappe-bench

# Assets are baked into the image but sites/ is rebuilt at container start
# (see entrypoint), so keep them out of sites/ and symlink them back in.
RUN cp -r sites/assets assets && rm -rf sites/assets

USER root
COPY --chown=frappe:frappe docker/cloudrun-entrypoint.sh /usr/local/bin/cloudrun-entrypoint.sh
RUN chmod 755 /usr/local/bin/cloudrun-entrypoint.sh

USER frappe
ENV PORT=8080
EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/cloudrun-entrypoint.sh"]
