# Usage:
#
# - Listens on port 8080 internally
# - Set environment variable `DJANGO_SETTINGS_MODULE`, e.g. to
#   `codejail_service.settings.production` or `codejail_service.settings.devstack`
# - Override arg `VERSION` to a commit hash or a branch
#
# In the nomenclature of codejail's confinement documentation:
#
# - SANDENV is at `/sandbox/venv`
# - Sandbox user is `sandbox`
# - SANDBOX_CALLER is `app`

FROM ubuntu:noble AS app


##### Base app installation #####

ARG GITHUB_REPO=openedx/codejail-service

# This should be overridden with a commit hash to ensure we always get
# a coherent result, even if things are changing on a branch as the
# image is being built.
#
# Must use the full 40-character hash when specifying a commit hash.
ARG VERSION=main

# Python version
ARG PY_VER_APP=3.12
ARG PY_VER_SANDBOX=3.8

ARG SANDENV=/sandbox/venv

ENV DEBIAN_FRONTEND=noninteractive
ARG APT_INSTALL="apt-get install --quiet --yes --no-install-recommends"

# Packages installed:
#
# - language-pack-en, locales: Ubuntu locale support so that system utilities
#   have a consistent language and time zone.
# - sudo: Web user (`app`) needs to be able to sudo as the `sandbox` user.
# - python*: Specific versions of Python -- the service runs with a recent version, but
#   the sandboxed code will usually need a different (older) version. This is also why
#   we need to pull in the deadsnakes PPA.
# - python*-dev: Header files for python extensions, required by many source wheels
# - python*-venv: Allow creation of virtualenvs
#
# We also have to do a bit of bootstrapping here installing the
# `software-properties-common` package gives us `add-apt-repository`, which
# allows us to add the deadsnakes PPA more easily (that is, without messing
# about with repository keys).
RUN apt-get update && \
  ${APT_INSTALL} software-properties-common && \
  add-apt-repository ppa:deadsnakes/ppa && \
  ${APT_INSTALL} \
    language-pack-en locales sudo \
    python${PY_VER_APP} python${PY_VER_APP}-dev python${PY_VER_APP}-venv \
    python${PY_VER_SANDBOX} python${PY_VER_SANDBOX}-venv \
    # If you add a package, please add a comment above explaining why it is needed!
    && \
  rm -rf /var/lib/apt/lists/*

RUN locale-gen en_US.UTF-8
ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8

WORKDIR /app

# We'll build the virtualenv and pre-compile Python as root, but switch to user
# `app` for actually running the application.
RUN useradd --create-home --shell /bin/false app

# Unpack the repo directly from GitHub, since this image is not built
# from inside the application repo.
#
# Start with getting just the requirements files so that code changes
# do not bust the image cache and require rebuilding the virtualenv.
ADD https://github.com/${GITHUB_REPO}.git#${VERSION}:requirements requirements

RUN python${PY_VER_APP} -m venv /venv && \
  /venv/bin/pip install -r /app/requirements/pip.txt && \
  /venv/bin/pip install -r /app/requirements/pip-tools.txt


##### Sandbox environment #####

RUN useradd --no-create-home --shell /bin/false --user-group sandbox

# We need to use --copies so that there is a distinct Python
# executable to confine.
RUN mkdir -p ${SANDENV}
RUN python${PY_VER_SANDBOX} -m venv --clear --copies ${SANDENV}

RUN { \
  echo "app ALL=(sandbox) SETENV:NOPASSWD:${SANDENV}/bin/python"; \
  echo "app ALL=(sandbox) SETENV:NOPASSWD:/usr/bin/find"; \
  echo "app ALL=(ALL) NOPASSWD:/usr/bin/pkill"; \
} > /etc/sudoers.d/01-sandbox


##### Default run config #####

EXPOSE 8080
CMD /venv/bin/gunicorn -c /app/codejail_service/docker_gunicorn_configuration.py \
    --bind '0.0.0.0:8080' --workers=10 --max-requests=1000 --name codejail \
    codejail_service.wsgi:application


##### Development target #####

FROM app AS dev

# Developers will want some additional packages for interactive debugging.
RUN apt-get update && \
  ${APT_INSTALL} make less nano emacs-nox && \
  rm -rf /var/lib/apt/lists/*

RUN /venv/bin/pip-sync requirements/dev.txt
RUN python${PY_VER_APP} -m compileall /venv

# Add code changes after deps installation so it won't bust the image cache
ADD https://github.com/${GITHUB_REPO}.git#${VERSION} .
RUN python${PY_VER_APP} -m compileall /app

# Set up virtualenv for developer
ENV PATH="/venv/bin:$PATH"


##### Production target #####

FROM app AS prod

RUN /venv/bin/pip-sync requirements/base.txt
RUN python${PY_VER_APP} -m compileall /venv

# Add code changes after deps installation so it won't bust the image cache
ADD https://github.com/${GITHUB_REPO}.git#${VERSION} .
RUN python${PY_VER_APP} -m compileall /app

# Drop to unprivileged user for running service
USER app
