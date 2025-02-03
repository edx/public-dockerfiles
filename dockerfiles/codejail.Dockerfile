# Usage:
#
# - Listens on port 8080 internally
# - Set environment variable `DJANGO_SETTINGS_MODULE`, e.g. to
#   `codejail_service.settings.production` or `codejail_service.settings.devstack`
# - Override arg `VERSION` to a commit hash or a branch

FROM ubuntu:noble AS app

ARG GITHUB_REPO=openedx/codejail-service

# This should be overridden with a commit hash to ensure we always get
# a coherent result, even if things are changing on a branch as the
# image is being built.
#
# Must use the full 40-character hash when specifying a commit hash.
ARG VERSION=main

# Python version
ARG PYVER=3.12

# Packages installed:
#
# - curl: To fetch the repository as a tarball
# - language-pack-en, locales: Ubuntu locale support so that system utilities
#   have a consistent language and time zone.
# - python*: A specific version of Python
# - python*-dev: Header files for python extensions, required by many source wheels
# - python*-venv: Allow creation of virtualenvs
RUN apt-get update && \
  DEBIAN_FRONTEND=noninteractive apt-get install \
    --quiet --yes --no-install-recommends \
    language-pack-en locales \
    python${PYVER} python${PYVER}-dev python${PYVER}-venv && \
    # If you add a package, please add a comment above explaining why it is needed!
  rm -rf /var/lib/apt/lists/*

RUN locale-gen en_US.UTF-8
ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8

WORKDIR /app

# We'll build the virtualenv and pre-compile Python as root, but switch to user
# `app` for actually running the application.
RUN useradd -m --shell /bin/false app

# Cloning git repo
RUN curl -L https://github.com/${GITHUB_REPO}/archive/refs/heads/${VERSION}.tar.gz | tar -xz --strip-components=1

RUN python${PYVER} -m venv /venv && \
  /venv/bin/pip install -r /app/requirements/pip.txt && \
  /venv/bin/pip install -r /app/requirements/pip-tools.txt

EXPOSE 8080
CMD /venv/bin/gunicorn -c /app/codejail_service/docker_gunicorn_configuration.py \
    --bind '0.0.0.0:8080' --workers=10 --max-requests=1000 --name codejail \
    codejail_service.wsgi:application


FROM app AS dev

# Developers will want some additional packages for interactive debugging.
RUN apt-get update && \
  DEBIAN_FRONTEND=noninteractive apt-get install \
    --quiet --yes --no-install-recommends \
    make less nano emacs-nox && \
  rm -rf /var/lib/apt/lists/*

RUN /venv/bin/pip-sync requirements/dev.txt
RUN python${PYVER} -m compileall /venv

RUN python${PYVER} -m compileall /app

# Set up virtualenv for developer
ENV PATH="/venv/bin:$PATH"


FROM app AS prod

RUN /venv/bin/pip-sync requirements/base.txt
RUN python${PYVER} -m compileall /venv

RUN python${PYVER} -m compileall /app

# Drop to unprivileged user for running service
USER app
