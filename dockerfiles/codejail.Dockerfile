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

# Unpack the repo directly from GitHub, since this image is not built
# from inside the application repo.
#
# Start with getting just the requirements files so that code changes
# do not bust the image cache and require rebuilding the virtualenv.
ADD https://github.com/${GITHUB_REPO}.git#${VERSION}:requirements requirements

RUN python${PYVER} -m venv /venv && \
  /venv/bin/pip install -r /app/requirements/pip.txt && \
  /venv/bin/pip install -r /app/requirements/pip-tools.txt

EXPOSE 8080


FROM app AS dev

RUN /venv/bin/pip-sync requirements/dev.txt
RUN python${PYVER} -m compileall /venv

# Add code changes after deps installation so it won't bust the image cache
ADD https://github.com/${GITHUB_REPO}.git#${VERSION} .
RUN python${PYVER} -m compileall /app

USER app
CMD echo $PATH; while true; do /venv/bin/python ./manage.py runserver 0.0.0.0:8080; sleep 2; done


FROM app AS prod

RUN /venv/bin/pip-sync requirements/base.txt
RUN python${PYVER} -m compileall /venv

# Add code changes after deps installation so it won't bust the image cache
ADD https://github.com/${GITHUB_REPO}.git#${VERSION} .
RUN python${PYVER} -m compileall /app

USER app
CMD /venv/bin/gunicorn -c /app/codejail_service/docker_gunicorn_configuration.py \
    --bind '0.0.0.0:8080' --workers=2 --max-requests=1000 --name codejail \
    codejail_service.wsgi:application
