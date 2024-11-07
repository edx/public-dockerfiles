FROM ubuntu:focal AS app

# Packages installed:
# git; Used to pull in particular requirements from github rather than pypi,
# and to check the sha of the code checkout.

# language-pack-en locales; ubuntu locale support so that system utilities have a consistent
# language and time zone.

# python3.12-dev; to install python 3.12
# python3-venv; installs venv module required to create virtual environments

# libssl-dev; # mysqlclient wont install without this.

# libmysqlclient-dev; to install header files needed to use native C implementation for
# MySQL-python for performance gains.

# If you add a package here please include a comment above describing what it is used for

# ENV variables for Python 3.12 support
ARG PYTHON_VERSION=3.12
ENV TZ=UTC
ENV TERM=xterm-256color
ENV DEBIAN_FRONTEND=noninteractive

# software-properties-common is needed to setup Python 3.12 env
RUN apt-get update && \
  apt-get install -y software-properties-common && \
  apt-add-repository -y ppa:deadsnakes/ppa

RUN apt-get update && apt-get -qy install --no-install-recommends \
    build-essential \
    language-pack-en \
    locales \
    pkg-config \
    libssl-dev \
    libffi-dev \
    libsqlite3-dev \
    libmysqlclient-dev \
    git \
    curl \
    python3-pip \
    python${PYTHON_VERSION} \
    python${PYTHON_VERSION}-dev \
    python${PYTHON_VERSION}-distutils && \
    rm -rf /var/lib/apt/lists/*

RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone
RUN ln -s /usr/bin/python3 /usr/bin/python

RUN locale-gen en_US.UTF-8
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

# need to use virtualenv pypi package with Python 3.12
RUN curl -sS https://bootstrap.pypa.io/get-pip.py | python${PYTHON_VERSION}
RUN pip install virtualenv

# ENV variables lifetime is bound to the container whereas ARGS variables lifetime is bound to the image building process only
# Also ARGS provide us an option of compatibility of Path structure for Tutor and other OpenedX installations
ARG COMMON_CFG_DIR="/edx/etc"
ARG COMMON_APP_DIR="/edx/app"
ARG NOTES_APP_DIR="${COMMON_APP_DIR}/notes"
ARG NOTES_VENV_DIR="${COMMON_APP_DIR}/venvs/notes"

ENV NOTES_APP_DIR=${NOTES_APP_DIR}
ENV PATH="$NOTES_VENV_DIR/bin:$PATH"

WORKDIR ${NOTES_APP_DIR}

RUN useradd -m --shell /bin/false app

RUN mkdir -p requirements

RUN virtualenv -p python${PYTHON_VERSION} --always-copy ${NOTES_VENV_DIR}

RUN pip install --upgrade pip setuptools

RUN curl -L -o requirements/base.txt https://raw.githubusercontent.com/openedx/edx-notes-api/master/requirements/base.txt
RUN curl -L -o requirements/pip.txt https://raw.githubusercontent.com/openedx/edx-notes-api/master/requirements/pip.txt

RUN pip install --no-cache-dir -r requirements/base.txt
RUN pip install --no-cache-dir -r requirements/pip.txt

RUN curl -L https://github.com/openedx/edx-notes-api/archive/refs/heads/master.tar.gz | tar -xz --strip-components=1

RUN mkdir -p /edx/var/log

EXPOSE 8120

FROM app AS dev

ENV DJANGO_SETTINGS_MODULE="notesserver.settings.devstack"

# Backwards compatibility with devstack
RUN touch "${COMMON_APP_DIR}/edx_notes_api_env"

CMD while true; do python ./manage.py runserver 0.0.0.0:8120; sleep 2; done

FROM app AS production

ENV EDXNOTES_CONFIG_ROOT="/edx/etc"
ENV DJANGO_SETTINGS_MODULE="notesserver.settings.yaml_config"

USER app

# Gunicorn 19 does not log to stdout or stderr by default. Once we are past gunicorn 19, the logging to STDOUT need not be specified.
CMD gunicorn --workers=2 --name notes -c /edx/app/notes/notesserver/docker_gunicorn_configuration.py --log-file - --max-requests=1000 notesserver.wsgi:application
