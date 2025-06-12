FROM ubuntu:focal as app
MAINTAINER devops@edx.org


# Packages installed:
# git; Used to pull in particular requirements from github rather than pypi,
# and to check the sha of the code checkout.

# language-pack-en locales; ubuntu locale support so that system utilities have a consistent
# language and time zone.

# python; ubuntu doesnt ship with python, so this is the python we will use to run the application

# python3-pip; install pip to install application requirements.txt files

# libssl-dev; # mysqlclient wont install without this.

# pkg-config
#     mysqlclient>=2.2.0 requires this (https://github.com/PyMySQL/mysqlclient/issues/620)

# libmysqlclient-dev; to install header files needed to use native C implementation for
# MySQL-python for performance gains.

# wget to download a watchman binary archive

# unzip to unzip a watchman binary archive

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
 language-pack-en \
 locales \
 pkg-config \
 libmysqlclient-dev \
 libssl-dev \
 build-essential \
 git \
 wget \
 unzip \
 curl \
 libffi-dev \
 libsqlite3-dev \
 python3-pip \
 python${PYTHON_VERSION} \
 python${PYTHON_VERSION}-dev

# Use virtualenv pypi package with Python 3.12
RUN curl -sS https://bootstrap.pypa.io/get-pip.py | python${PYTHON_VERSION}
RUN pip install virtualenv

ENV VIRTUAL_ENV=/edx/app/license-manager/venvs/license-manager
RUN virtualenv -p python${PYTHON_VERSION} $VIRTUAL_ENV
ENV PATH="$VIRTUAL_ENV/bin:$PATH"

RUN locale-gen en_US.UTF-8
ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8
ENV DJANGO_SETTINGS_MODULE license_manager.settings.production

EXPOSE 18170
EXPOSE 18171
RUN useradd -m --shell /bin/false app

# Install watchman
RUN wget https://github.com/facebook/watchman/releases/download/v2023.11.20.00/watchman-v2023.11.20.00-linux.zip
RUN unzip watchman-v2023.11.20.00-linux.zip
RUN mkdir -p /usr/local/{bin,lib} /usr/local/var/run/watchman
RUN cp watchman-v2023.11.20.00-linux/bin/* /usr/local/bin
RUN cp watchman-v2023.11.20.00-linux/lib/* /usr/local/lib
RUN chmod 755 /usr/local/bin/watchman
RUN chmod 2777 /usr/local/var/run/watchman

# Now install license-manager
WORKDIR /edx/app/license_manager

RUN mkdir -p requirements

# Install production requirements
RUN curl -L -o requirements/pip.txt https://raw.githubusercontent.com/edx/license-manager/master/requirements/pip.txt
RUN pip install --no-cache-dir -r requirements/pip.txt

RUN curl -L -o requirements/production.txt https://raw.githubusercontent.com/edx/license-manager/master/requirements/production.txt
RUN pip install --no-cache-dir -r requirements/production.txt

RUN curl -L https://github.com/edx/license-manager/archive/refs/heads/master.tar.gz | tar -xz --strip-components=1
RUN curl -L -o license_manager/settings/devstack.py https://raw.githubusercontent.com/edx/devstack/master/py_configuration_files/license_manager.py

RUN mkdir -p /edx/var/log

# Code is owned by root so it cannot be modified by the application user.
# So we copy it before changing users.
USER app

# Gunicorn 19 does not log to stdout or stderr by default. Once we are past gunicorn 19, the logging to STDOUT need not be specified.
CMD gunicorn --workers=2 --name license_manager -c /edx/app/license_manager/license_manager/docker_gunicorn_configuration.py --log-file - --max-requests=1000 license_manager.wsgi:application

FROM app as dev
USER root
RUN pip install -r /edx/app/license_manager/requirements/dev.txt
CMD gunicorn --reload --workers=2 --name license_manager -c /edx/app/license_manager/license_manager/docker_gunicorn_configuration.py --log-file - --max-requests=1000 license_manager.wsgi:application


FROM app as legacy_devapp
# Dev ports
EXPOSE 18170
EXPOSE 18171
USER root
RUN pip install -r /edx/app/license_manager/requirements/dev.txt
CMD gunicorn --reload --workers=2 --name license_manager -c /edx/app/license_manager/license_manager/docker_gunicorn_configuration.py --log-file - --max-requests=1000 license_manager.wsgi:application
