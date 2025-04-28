# Usage:
#
# - Listens on port 8080 internally
# - Set environment variable `DJANGO_SETTINGS_MODULE`, e.g. to
#   `codejail_service.settings.production` or `codejail_service.settings.devstack`
# - Must be run with UID and GID $APP_UID_GID, if setting this explicitly in the
#   container execution.
#
# Terminology notes:
#
# - This Dockerfile is for the codejail-service, a wrapper around the codejail
#   *library*. When used in isolation, "codejail" usually refers to the library.
# - "Sandbox" refers to the secured execution environment for user-submitted
#   code, not to the sandbox deployment environments used for debugging. This
#   matches the codejail library's own terminology.

FROM ubuntu:noble AS app


##### Defaults and config #####

# GitHub org/repo containing the webapp
ARG CODEJAIL_SERVICE_REPO=openedx/codejail-service

# Revision of CODEJAIL_SERVICE_REPO, ideally a commit hash
ARG CODEJAIL_SERVICE_VERSION=main

# Python version for webapp
ARG APP_PY_VER=3.12

# See codejail-service deployment and configuration docs for why we need to select
# a UID/GID that is unlikely to collide with anything on the host. (Short answer:
# RLIMIT_NPROC UID-global usage pool, and Docker not isolating UIDs.)
#
# Selected via: python3 -c 'import random; print(random.randrange(3000, 2 ** 31))'
ARG APP_UID=206593644
# Use the same group ID as the user ID for convenience.
ARG APP_GID=$APP_UID

# Where to get the Python dependencies lockfile for installing
# packages into the sandbox environment. Defaults to the codejail
# dependencies in edx-platform.
ARG SANDBOX_DEPS_REPO=openedx/edx-platform
ARG SANDBOX_DEPS_VERSION=master
# Path to the lockfile in the deps repo, as dir + filename.
#
# The path base.txt will get the latest dependencies, but this needs
# to be coordinated with SANDBOX_PY_VER as each release has a
# different Python support window.
ARG SANDBOX_DEPS_SRC_DIR=requirements/edx-sandbox/releases
ARG SANDBOX_DEPS_SRC_FILE=sumac.txt

# Python version for sandboxed executions. This must be coordinated with
# `SANDBOX_DEPS_SRC_*` to ensure compatibility.
ARG SANDBOX_PY_VER=3.12


##### Base app installation #####

# Internal variables

ENV DEBIAN_FRONTEND=noninteractive
ARG APT_INSTALL="apt-get install --quiet --yes --no-install-recommends"

# The codejail library specifies a certain structure to how the sandboxing is
# performed. (See the documentation in the codejail library README:
# https://github.com/openedx/codejail).
#
# Some of this structure can be changed, and some cannot. Any changes that are
# possible will also need to be coordinated with changes to the apparmor profile
# as well as to the `CODE_JAIL` Django settings. Accordingly, it's best to just
# *avoid* making changes to this part.

# The location of the virtualenv that code executions in the sandbox will use.
# This is a critical path, as SAND_VENV/bin/python is what is targeted by the
# AppArmor confinement. It must also match the Django setting
# `CODE_JAIL.python_bin`. The codejail docs refer to this as `<SANDENV>`.
ARG SAND_VENV=/sandbox/venv
# The user account that will run code executions, described just as "the sandbox
# user" in codejail docs. This needs to match the Django setting
# `CODE_JAIL.user` and the sudoers file.
ARG SAND_USER=sandbox
# Same situation as for APP_UID
ARG SAND_UID=349590265
ARG SAND_GID=$SAND_UID
# The user account that runs the regular web app, described in codejail docs as
# `<SANDBOX_CALLER>`. Needs to match the sudoers file.
ARG APP_USER=app

# The codejail-service API tests check for the visibility of this environment
# variable from the sandbox. (It should not be visible.) This helps test for
# environment leakage into the sandbox.
ENV CJS_TEST_ENV_LEAKAGE=yes

# Packages installed:
#
# - language-pack-en, locales: Ubuntu locale support so that system utilities
#   have a consistent language and time zone.
# - sudo: Web user (`APP_USER`) needs to be able to sudo as `SAND_USER`
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
    python${APP_PY_VER} python${APP_PY_VER}-dev python${APP_PY_VER}-venv \
    python${SANDBOX_PY_VER} python${SANDBOX_PY_VER}-venv \
    # If you add a package, please add a comment above explaining why it is needed!
  && \
  rm -rf /var/lib/apt/lists/*

RUN locale-gen en_US.UTF-8
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

# We'll build the virtualenv and pre-compile Python as root, but switch to app user
# for actually running the application.
RUN groupadd --gid $APP_GID $APP_USER
RUN useradd --no-create-home --shell /bin/false --uid $APP_UID --gid $APP_GID $APP_USER

# Cloning git repo
ADD https://github.com/${CODEJAIL_SERVICE_REPO}.git#${CODEJAIL_SERVICE_VERSION} /app

WORKDIR /app

RUN python${APP_PY_VER} -m venv /venv && \
  /venv/bin/pip install -r /app/requirements/pip.txt && \
  /venv/bin/pip install -r /app/requirements/pip-tools.txt


##### Sandbox environment #####

# Codejail executions will be run under this user's account.
RUN groupadd --gid $SAND_GID $SAND_USER
RUN useradd --no-create-home --shell /bin/false --uid $SAND_UID --gid $SAND_GID $SAND_USER

# We need to use --copies so that there is a distinct Python
# executable to confine.
RUN mkdir -p ${SAND_VENV}
RUN python${SANDBOX_PY_VER} -m venv --clear --copies ${SAND_VENV}

# Fetch and install the Python libraries used by the sandbox.
ADD https://github.com/${SANDBOX_DEPS_REPO}.git#${SANDBOX_DEPS_VERSION}:${SANDBOX_DEPS_SRC_DIR} /tmp/sand-deps
RUN ${SAND_VENV}/bin/pip install -r /tmp/sand-deps/${SANDBOX_DEPS_SRC_FILE} && rm -rf /tmp/sand-deps/

# Sudoers config as specified by codejail's docs.
# - `find` is used in sandbox cleanup
# - `pkill` is used to terminate overlong execution
RUN { \
  echo "${APP_USER} ALL=(${SAND_USER}) SETENV:NOPASSWD:${SAND_VENV}/bin/python"; \
  echo "${APP_USER} ALL=(${SAND_USER}) SETENV:NOPASSWD:/usr/bin/find"; \
  echo "${APP_USER} ALL=(ALL) NOPASSWD:/usr/bin/pkill"; \
} > /etc/sudoers.d/01-sandbox


##### Default run config #####

# Set up virtualenv for any additional commands. This isn't just for developers
# -- it allows an entry command into the Dockerfile to be run without the caller
# knowing where the virtualenv is located.
ENV PATH="/venv/bin:$PATH"

EXPOSE 8080
CMD /venv/bin/gunicorn -c /app/codejail_service/docker_gunicorn_configuration.py \
    --bind '0.0.0.0:8080' --workers=10 --max-requests=1000 \
    codejail_service.wsgi:application


##### Development target #####

FROM app AS dev

# Developers will want some additional packages for interactive debugging.
RUN apt-get update && \
  ${APT_INSTALL} make less nano emacs-nox && \
  rm -rf /var/lib/apt/lists/*

RUN /venv/bin/pip-sync requirements/dev.txt
RUN python${APP_PY_VER} -m compileall /venv /app


##### Production target #####

FROM app AS prod

RUN /venv/bin/pip-sync requirements/base.txt
RUN python${APP_PY_VER} -m compileall /venv /app

# Drop to unprivileged user for running service
USER ${APP_USER}
