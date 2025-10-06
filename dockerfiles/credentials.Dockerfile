# syntax=docker/dockerfile:1
# check=skip=SecretsUsedInArgOrEnv
# SecretsUsedInArgOrEnv check gets false positives on the name CREDENTIALS
FROM ubuntu:jammy AS base

ARG CREDENTIALS_SERVICE_REPO=openedx/credentials
ARG CREDENTIALS_SERVICE_VERSION=master
ARG PYTHON_VERSION=3.12
ENV TZ=UTC
ENV TERM=xterm-256color
ENV DEBIAN_FRONTEND=noninteractive

# software-properties-common is needed to setup our Python 3.12 env
RUN apt-get update && \
    apt-get install -y software-properties-common && \
    apt-add-repository -y ppa:deadsnakes/ppa

# System requirements
# - build-essential; meta-package that install a collection of essential tools for compiling software from source (e.g. gcc, g++, make, etc.)
# - curl; used to pull requirements files
# - gettext; used to support i18n functionality for the app
# - git; Used to pull in particular requirements from github rather than pypi and to check the SHA of the code checked out
# - language-pack-en & locales; Ubuntu locale support so that system utilities have a consistent language and time zone.
# - libmysqlclient-dev; to install header files needed to use native C implementation for MySQL-python for performance gains.
# - libssl-dev; # mysqlclient wont install without this.
# - pkg-config; mysqlclient>=2.2.0 requires pkg-config (https://github.com/PyMySQL/mysqlclient/issues/620)
# - python${PYTHON_VERSION}; Ubuntu doesn't ship with Python, this is the Python version used to run the application
# - python${PYTHON_VERSION}-dev; to install header files for python extensions, wheel-building depends on this
# - wget; for downloading files (watchman binary, common_constraints file)
# - unzip; to unzip a watchman binary archive
#
# If you add a package here please include a comment above describing what it is used for
RUN apt-get update && apt-get -qy install --no-install-recommends \
        build-essential \
        curl \
        gettext \
        git \
        language-pack-en \
        libmysqlclient-dev \
        libssl-dev \
        locales \
        pkg-config \
        python${PYTHON_VERSION} \
        python${PYTHON_VERSION}-dev \
        wget \
        unzip

# need to use virtualenv pypi package with Python 3.12
RUN curl -sS https://bootstrap.pypa.io/get-pip.py | python${PYTHON_VERSION}
RUN pip install virtualenv
# create our Python virtual env
ENV VIRTUAL_ENV=/edx/venvs/credentials
RUN virtualenv -p python$PYTHON_VERSION $VIRTUAL_ENV
ENV PATH="$VIRTUAL_ENV/bin:$PATH"

# delete apt package lists because we do not need them inflating our image
RUN rm -rf /var/lib/apt/lists/*

# Python is Python3.
RUN ln -s /usr/bin/python3 /usr/bin/python

# Setup zoneinfo for Python 3.12
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# Use UTF-8.
RUN locale-gen en_US.UTF-8
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

# Create Node env
RUN pip install nodeenv
ENV NODE_ENV=/edx/app/credentials/nodeenvs/credentials
RUN nodeenv $NODE_ENV --node=20.19.0 --prebuilt
ENV PATH="$NODE_ENV/bin:$PATH"
RUN npm install -g npm@11.x.x

ENV DJANGO_SETTINGS_MODULE=credentials.settings.production
ENV OPENEDX_ATLAS_PULL=true
ENV CREDENTIALS_CFG="minimal.yml"

EXPOSE 18150
RUN useradd -m --shell /bin/false app

# Install watchman
RUN wget https://github.com/facebook/watchman/releases/download/v2023.11.20.00/watchman-v2023.11.20.00-linux.zip
RUN unzip watchman-v2023.11.20.00-linux.zip
RUN mkdir -p /usr/local/{bin,lib} /usr/local/var/run/watchman
RUN cp watchman-v2023.11.20.00-linux/bin/* /usr/local/bin
RUN cp watchman-v2023.11.20.00-linux/lib/* /usr/local/lib
RUN chmod 755 /usr/local/bin/watchman
RUN chmod 2777 /usr/local/var/run/watchman

# Now install credentials
WORKDIR /edx/app/credentials/credentials

# fetching the requirement files that are needed
RUN mkdir -p requirements
RUN curl -L -o requirements/pip_tools.txt https://raw.githubusercontent.com/openedx/credentials/${CREDENTIALS_SERVICE_VERSION}/requirements/pip_tools.txt
RUN curl -L -o requirements/production.txt https://raw.githubusercontent.com/openedx/credentials/${CREDENTIALS_SERVICE_VERSION}/requirements/production.txt

# Dependencies are installed as root so they cannot be modified by the application user.
RUN pip install -r requirements/pip_tools.txt
RUN pip install -r requirements/production.txt

RUN mkdir -p /edx/var/log

# Cloning git repo. This line is after the python requirements so that changes to the code will not bust the image cache
ADD https://github.com/${CREDENTIALS_SERVICE_REPO}.git#${CREDENTIALS_SERVICE_VERSION} /edx/app/credentials/credentials

# Install frontend dependencies in node_modules directory
RUN npm install --no-save
ENV NODE_BIN=/edx/app/credentials/credentials/node_modules
ENV PATH="$NODE_BIN/.bin:$PATH"
# Run webpack
RUN webpack --config webpack.config.js

# Change static folder owner to application user.
RUN chown -R app:app /edx/app/credentials/credentials/credentials/static

# Code is owned by root so it cannot be modified by the application user. So we copy it before changing users.
USER app

# Gunicorn 19 does not log to stdout or stderr by default. Once we are past gunicorn 19, the logging to STDOUT need not be specified.
CMD gunicorn --workers=2 --name credentials -c /edx/app/credentials/credentials/credentials/docker_gunicorn_configuration.py --log-file - --max-requests=1000 credentials.wsgi:application

# We don't switch back to the app user for devstack because we need devstack users to be able to update requirements and generally run things as root.
FROM base AS dev
USER root

RUN curl -L -o credentials/settings/devstack.py https://raw.githubusercontent.com/edx/devstack/${CREDENTIALS_SERVICE_VERSION}/py_configuration_files/credentials.py

ENV DJANGO_SETTINGS_MODULE=credentials.settings.devstack
RUN pip install -r /edx/app/credentials/credentials/requirements/dev.txt
RUN make pull_translations

# Devstack related step for backwards compatibility, used in devstack's docker-compose.yml
RUN touch ../credentials_env

CMD while true; do python ./manage.py runserver 0.0.0.0:18150; sleep 2; done
