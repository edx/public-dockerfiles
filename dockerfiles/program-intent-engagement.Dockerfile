FROM ubuntu:focal as app
MAINTAINER sre@edx.org


# Packages installed:

# language-pack-en locales; ubuntu locale support so that system utilities have a consistent
# language and time zone.

# python; ubuntu doesnt ship with python, so this is the python we will use to run the application

# python3-pip; install pip to install application requirements.txt files

# libmysqlclient-dev; to install header files needed to use native C implementation for
# MySQL-python for performance gains.

# pkg-config; mysqlclient>=2.2.0 requires pkg-config (https://github.com/PyMySQL/mysqlclient/issues/620)

# libssl-dev; # mysqlclient wont install without this.

# python3-dev; to install header files for python extensions; much wheel-building depends on this

# gcc; for compiling python extensions distributed with python packages like mysql-client

# ENV variables for Python 3.12 support
ARG PYTHON_VERSION=3.12
ENV TZ=UTC
ENV TERM=xterm-256color
ENV DEBIAN_FRONTEND=noninteractive

# software-properties-common is needed to setup Python 3.12 env
RUN apt-get update && \
  apt-get install -y software-properties-common && \
  apt-add-repository -y ppa:deadsnakes/ppa

# If you add a package here please include a comment above describing what it is used for
RUN apt-get update && apt-get -qy install --no-install-recommends \
 language-pack-en \
 locales \
 # libmysqlclient-dev header files needed to use native C implementation for MySQL-python for performance gains.
 libmysqlclient-dev \
 # mysqlclient>=2.2.0 requires pkg-config (https://github.com/PyMySQL/mysqlclient/issues/620)
 pkg-config \
 # mysqlclient wont install without libssl-dev
 libssl-dev \
 build-essential \
 gcc \
 curl \
 python3-pip \
 python${PYTHON_VERSION} \
 python${PYTHON_VERSION}-dev \
 python${PYTHON_VERSION}-distutils


# need to use virtualenv pypi package with Python 3.12
RUN pip install --upgrade pip setuptools
RUN curl -sS https://bootstrap.pypa.io/get-pip.py | python${PYTHON_VERSION}
RUN pip install virtualenv

RUN pip install --upgrade pip setuptools
# delete apt package lists because we do not need them inflating our image
RUN rm -rf /var/lib/apt/lists/*

RUN ln -s /usr/bin/python3 /usr/bin/python

# Setup zoneinfo for Python 3.12
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

RUN locale-gen en_US.UTF-8
ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8
ENV DJANGO_SETTINGS_MODULE program_intent_engagement.settings.production

EXPOSE 18781
RUN useradd -m --shell /bin/false app

WORKDIR /edx/app/program-intent-engagement

# Create required directories for requirements
RUN mkdir -p requirements

ARG INTENT_MANAGEMENT_VENV_DIR="/edx/app/venvs/program-intent-management"
RUN virtualenv -p python${PYTHON_VERSION} --always-copy ${INTENT_MANAGEMENT_VENV_DIR}

# Dependencies are installed as root so they cannot be modified by the application user.
RUN curl -L -o requirements/production.txt https://raw.githubusercontent.com/edx/program-intent-engagement/main/requirements/production.txt
RUN pip install -r requirements/production.txt

RUN mkdir -p /edx/var/log

# Clone the repository
RUN curl -L https://github.com/edx/program-intent-engagement/archive/refs/heads/main.tar.gz | tar -xz --strip-components=1

# Code is owned by root so it cannot be modified by the application user.
USER app

# Gunicorn 19 does not log to stdout or stderr by default. Once we are past gunicorn 19, the logging to STDOUT need not be specified.
CMD gunicorn --workers=2 --name program-intent-engagement -c /edx/app/program-intent-engagement/program_intent_engagement/docker_gunicorn_configuration.py --log-file - --max-requests=1000 program_intent_engagement.wsgi:application
