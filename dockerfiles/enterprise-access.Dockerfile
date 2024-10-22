FROM ubuntu:focal AS app
MAINTAINER sre@edx.org


# Packages installed:
# git; Used to pull in particular requirements from github rather than pypi,
# and to check the sha of the code checkout.

# build-essentials; so we can use make with the docker container

# language-pack-en locales; ubuntu locale support so that system utilities have a consistent
# language and time zone.

# python; ubuntu doesnt ship with python, so this is the python we will use to run the application

# python3-pip; install pip to install application requirements.txt files

# pkg-config
#     mysqlclient>=2.2.0 requires this (https://github.com/PyMySQL/mysqlclient/issues/620)

# libmysqlclient-dev; to install header files needed to use native C implementation for
# MySQL-python for performance gains.

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
 build-essential \
 language-pack-en \
 locales \
 pkg-config \
 libmysqlclient-dev \
 libssl-dev \
 git \
 wget \
 curl \
 libffi-dev \
 libsqlite3-dev \
 python3-pip \
 python${PYTHON_VERSION} \
 python${PYTHON_VERSION}-dev \
 python${PYTHON_VERSION}-distutils

RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

RUN pip install --upgrade pip setuptools

# Remove package lists to reduce image size
RUN rm -rf /var/lib/apt/lists/*

# Set up Python environment and install virtualenv
RUN curl -sS https://bootstrap.pypa.io/get-pip.py | python${PYTHON_VERSION}
RUN pip install virtualenv

# Create a virtualenv for sanity
ENV VIRTUAL_ENV=/edx/venvs/enterprise-access
RUN virtualenv -p python${PYTHON_VERSION} $VIRTUAL_ENV
ENV PATH="$VIRTUAL_ENV/bin:$PATH"

WORKDIR /tmp
RUN wget https://packages.confluent.io/clients/deb/pool/main/libr/librdkafka/librdkafka_2.0.2.orig.tar.gz
RUN tar -xf librdkafka_2.0.2.orig.tar.gz
WORKDIR /tmp/librdkafka-2.0.2
RUN ./configure && make && make install && ldconfig

RUN ln -s /usr/bin/python3 /usr/bin/python

RUN locale-gen en_US.UTF-8
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8
ENV DJANGO_SETTINGS_MODULE=enterprise_access.settings.production

EXPOSE 18270
EXPOSE 18271
RUN useradd -m --shell /bin/false app

WORKDIR /edx/app/enterprise-access

RUN mkdir -p /requirements

RUN curl -L -o /requirements/pip.txt https://raw.githubusercontent.com/openedx/enterprise-access/main/requirements/pip.txt
RUN curl -L -o /requirements/production.txt https://raw.githubusercontent.com/openedx/enterprise-access/main/requirements/production.txt
# Dependencies are installed as root so they cannot be modified by the application user.
RUN pip install -r /requirements/pip.txt
RUN pip install -r /requirements/production.txt

RUN mkdir -p /edx/var/log

# Clone the source code
RUN curl -L https://github.com/openedx/enterprise-access/archive/refs/heads/main.tar.gz | tar -xz --strip-components=1

# Change user to app
USER app

# Gunicorn 19 does not log to stdout or stderr by default. Once we are past gunicorn 19, the logging to STDOUT need not be specified.
CMD gunicorn --workers=2 --name enterprise-access -c /edx/app/enterprise-access/enterprise_access/docker_gunicorn_configuration.py --log-file - --max-requests=1000 enterprise_access.wsgi:application

FROM app AS newrelic
RUN pip install newrelic
CMD newrelic-admin run-program gunicorn --workers=2 --name enterprise-access -c /edx/app/enterprise-access/enterprise_access/docker_gunicorn_configuration.py --log-file - --max-requests=1000 enterprise_access.wsgi:application

FROM app AS devstack
USER root
RUN pip install -r /requirements/dev.txt
USER app
CMD gunicorn --workers=2 --name enterprise-access -c /edx/app/enterprise-access/enterprise_access/docker_gunicorn_configuration.py --log-file - --max-requests=1000 enterprise_access.wsgi:application
