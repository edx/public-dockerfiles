FROM ubuntu:focal AS app
MAINTAINER sre@edx.org

# ENV variables for Python 3.12 support
ARG PYTHON_VERSION=3.12
ENV TZ=UTC
ENV TERM=xterm-256color
ENV DEBIAN_FRONTEND=noninteractive

# software-properties-common is needed to setup Python 3.12 env
RUN apt-get update && \
  apt-get install -y software-properties-common && \
  apt-add-repository -y ppa:deadsnakes/ppa

# Packages installed:

# pkg-config; mysqlclient>=2.2.0 requires pkg-config (https://github.com/PyMySQL/mysqlclient/issues/620)

RUN apt-get update && apt-get -qy install --no-install-recommends \
 build-essential \
 language-pack-en \
 locales \
 libmysqlclient-dev \
 pkg-config \
 libssl-dev \
 gcc \
 make \
 curl \
 python3-pip \
 python${PYTHON_VERSION} \
 python${PYTHON_VERSION}-dev

RUN pip install --upgrade pip setuptools
# delete apt package lists because we do not need them inflating our image
RUN rm -rf /var/lib/apt/lists/*

RUN ln -s /usr/bin/python3 /usr/bin/python

# Setup zoneinfo for Python 3.12
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# need to use virtualenv pypi package with Python 3.12
RUN pip install --upgrade pip setuptools
RUN curl -sS https://bootstrap.pypa.io/get-pip.py | python${PYTHON_VERSION}
RUN pip install virtualenv

RUN locale-gen en_US.UTF-8
ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8
ENV DJANGO_SETTINGS_MODULE designer.settings.production

EXPOSE 18808
RUN useradd -m --shell /bin/false app

WORKDIR /edx/app/designer
ARG DESIGNER_VENV_DIR="/edx/app/venvs/designer"
ENV PATH="$DESIGNER_VENV_DIR/bin:$PATH"

RUN mkdir -p requirements

# Create virtual environment for the application
RUN virtualenv -p python${PYTHON_VERSION} --always-copy ${DESIGNER_VENV_DIR}

# Download and install application requirements
RUN curl -L -o requirements/production.txt https://raw.githubusercontent.com/edx/portal-designer/master/requirements/production.txt
RUN pip install -r requirements/production.txt

RUN mkdir -p /edx/var/log

# Clone the application code
RUN curl -L https://github.com/edx/portal-designer/archive/refs/heads/master.tar.gz | tar -xz --strip-components=1

# Code is owned by root so it cannot be modified by the application user.
# So we copy it before changing users.
USER app

# Gunicorn 19 does not log to stdout or stderr by default. Once we are past gunicorn 19, the logging to STDOUT need not be specified.
CMD gunicorn --workers=2 --name designer -c /edx/app/designer/designer/docker_gunicorn_configuration.py --log-file - --max-requests=1000 designer.wsgi:application

# Change into dev app
FROM app AS devstack
# Install dependencies as root and revert back to application user
USER root
RUN pip install -r /edx/app/designer/requirements/dev.txt
USER app
