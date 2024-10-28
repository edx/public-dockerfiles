FROM ubuntu:focal AS app
MAINTAINER sre@edx.org


# Packages installed:

# gcc; for compiling python extensions distributed with python packages like mysql-client
# git; for pulling requirements from GitHub.
# language-pack-en locales; ubuntu locale support so that system utilities have a consistent language and time zone.
# libmysqlclient-dev; to install header files needed to use native C implementation for MySQL-python for performance gains.
# libssl-dev; # mysqlclient wont install without this.
# pkg-config is now required for libmysqlclient-dev and its python dependencies
# python3-dev; to install header files for python extensions; much wheel-building depends on this
# python3-pip; install pip to install application requirements.txt files
# python; ubuntu doesnt ship with python, so this is the python we will use to run the application

# If you add a package here please include a comment above describing what it is used for
RUN apt-get update && apt-get -qy install --no-install-recommends \
 gcc \
 curl \
 git \
 language-pack-en \
 libmysqlclient-dev \
 libssl-dev \
 locales \
 pkg-config \
 python3-dev \
 python3-pip \
 python3.8


RUN pip install --upgrade pip setuptools

# Delete apt package lists because we do not need them inflating our image
RUN rm -rf /var/lib/apt/lists/*

RUN ln -s /usr/bin/python3 /usr/bin/python

RUN locale-gen en_US.UTF-8
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

ENV DJANGO_SETTINGS_MODULE=commerce_coordinator.settings.production

EXPOSE 8140

RUN useradd -m --shell /bin/false app

WORKDIR /edx/app/commerce-coordinator

RUN mkdir -p requirements

RUN curl -L -o requirements/production.txt https://raw.githubusercontent.com/edx/commerce-coordinator/main/requirements/production.txt
RUN pip install -r requirements/production.txt

RUN mkdir -p /edx/var/log

RUN curl -L https://github.com/edx/commerce-coordinator/archive/refs/heads/main.tar.gz | tar -xz --strip-components=1

# Code is owned by root so it cannot be modified by the application user.
# So we copy it before changing users.
USER app

# Gunicorn 19 does not log to stdout or stderr by default. Once we are past gunicorn 19, the logging to STDOUT need not be specified.
CMD gunicorn --workers=2 --name commerce-coordinator -c /edx/app/commerce-coordinator/commerce_coordinator/docker_gunicorn_configuration.py --log-file - --max-requests=1000 commerce-coordinator.wsgi:application