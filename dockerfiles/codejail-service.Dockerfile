# Usage:
#
# - Listens on port 8080 internally
# - Set environment variable `DJANGO_SETTINGS_MODULE`, e.g. to
#   `codejail_service.settings.production` or `codejail_service.settings.devstack`
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
ARG APP_REPO=openedx/codejail-service

# This must be a branch or other ref in APP_REPO
ARG APP_VERSION=main

# Python version for webapp
ARG APP_PY_VER=3.12

# Where to get the Python dependencies lockfile for installing
# packages into the sandbox environment. Defaults to the codejail
# dependencies in edx-platform.
ARG SANDBOX_DEPS_REPO=openedx/edx-platform
ARG SANDBOX_DEPS_VERSION=master
# Path to the lockfile in the deps repo.
#
# The path base.txt will get the latest dependencies, but this needs
# to be coordinated with SANDBOX_PY_VER as each release has a
# different Python support window. We'll continue to use the quince
# release until we can move beyond Python 3.8.
ARG SANDBOX_DEPS_PATH=requirements/edx-sandbox/releases/quince.txt

# Python version for sandboxed executions
ARG SANDBOX_PY_VER=3.8


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
# The user account that runs the regular web app, described in codejail docs as
# `<SANDBOX_CALLER>`. Needs to match the sudoers file.
ARG APP_USER=app

# Temporary location where we save the lockfile for Python dependencies before
# installing them in the sandbox virtualenv.
ARG SAND_DEPS=/sandbox/requirements.txt

# The codejail-service API tests check for the visibility of this environment
# variable from the sandbox. (It should not be visibile.) This helps test for
# environment leakage into the sandbox.
ENV CJS_TEST_ENV_LEAKAGE=yes

# Packages installed:
#
# - curl: To fetch the repository as a tarball
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
    curl language-pack-en locales sudo \
    python${APP_PY_VER} python${APP_PY_VER}-dev python${APP_PY_VER}-venv \
    python${SANDBOX_PY_VER} python${SANDBOX_PY_VER}-venv \
    # If you add a package, please add a comment above explaining why it is needed!
  && \
  rm -rf /var/lib/apt/lists/*

RUN locale-gen en_US.UTF-8
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

WORKDIR /app

# We'll build the virtualenv and pre-compile Python as root, but switch to app user
# for actually running the application.
RUN useradd --create-home --shell /bin/false ${APP_USER}

# Cloning git repo
RUN curl -L https://github.com/${APP_REPO}/archive/refs/heads/${APP_VERSION}.tar.gz | tar -xz --strip-components=1

RUN python${APP_PY_VER} -m venv /venv && \
  /venv/bin/pip install -r /app/requirements/pip.txt && \
  /venv/bin/pip install -r /app/requirements/pip-tools.txt


##### Sandbox environment #####

# Codejail executions will be run under this user's account.
RUN useradd --no-create-home --shell /bin/false --user-group ${SAND_USER}

# We need to use --copies so that there is a distinct Python
# executable to confine.
RUN mkdir -p ${SAND_VENV}
RUN python${SANDBOX_PY_VER} -m venv --clear --copies ${SAND_VENV}

# Fetch and install the Python libraries used by the sandbox.
RUN curl -L "https://github.com/${SANDBOX_DEPS_REPO}/raw/refs/heads/${SANDBOX_DEPS_VERSION}/${SANDBOX_DEPS_PATH}" > ${SAND_DEPS}
RUN ${SAND_VENV}/bin/pip install -r ${SAND_DEPS}

# Sudoers config as specified by codejail's docs.
# - `find` is used in sandbox cleanup
# - `pkill` is used to terminate overlong execution
RUN { \
  echo "${APP_USER} ALL=(${SAND_USER}) SETENV:NOPASSWD:${SAND_VENV}/bin/python"; \
  echo "${APP_USER} ALL=(${SAND_USER}) SETENV:NOPASSWD:/usr/bin/find"; \
  echo "${APP_USER} ALL=(ALL) NOPASSWD:/usr/bin/pkill"; \
} > /etc/sudoers.d/01-sandbox


##### Default run config #####

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

# Set up virtualenv for developer
ENV PATH="/venv/bin:$PATH"


##### Production target #####

FROM app AS prod

RUN /venv/bin/pip-sync requirements/base.txt
RUN python${APP_PY_VER} -m compileall /venv /app

# Drop to unprivileged user for running service
USER ${APP_USER}
