FROM ubuntu:focal AS base

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
# - language-pack-en & locales; Ubuntu locale support so that system utilities have a consistent language and time zone.
# - libmysqlclient-dev; to install header files needed to use native C implementation for MySQL-python for performance gains.
# - libssl-dev; # mysqlclient wont install without this.
# - pkg-config; mysqlclient>=2.2.0 requires pkg-config (https://github.com/PyMySQL/mysqlclient/issues/620)
# - python${PYTHON_VERSION}; Ubuntu doesn't ship with Python, this is the Python version used to run the application
# - python${PYTHON_VERSION}-dev; to install header files for python extensions, wheel-building depends on this
#
# If you add a package here please include a comment above describing what it is used for
RUN apt-get update && apt-get -qy install --no-install-recommends \
        build-essential \
        curl \
        language-pack-en \
        libmysqlclient-dev \
        libssl-dev \
        locales \
        pkg-config \
        python${PYTHON_VERSION} \
        python${PYTHON_VERSION}-dev


# need to use virtualenv pypi package with Python 3.12
RUN curl -sS https://bootstrap.pypa.io/get-pip.py | python${PYTHON_VERSION}
RUN pip install virtualenv
# create our Python virtual env
ENV VIRTUAL_ENV=/edx/venvs/pie
RUN virtualenv -p python$PYTHON_VERSION $VIRTUAL_ENV
ENV PATH="$VIRTUAL_ENV/bin:$PATH"

RUN pip install --upgrade pip setuptools

# delete apt package lists because we do not need them inflating our image
RUN rm -rf /var/lib/apt/lists/*


# Python is Python3.
RUN ln -s /usr/bin/python3 /usr/bin/python

# Setup zoneinfo for Python 3.12
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

RUN locale-gen en_US.UTF-8
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8
ENV DJANGO_SETTINGS_MODULE=program_intent_engagement.settings.production

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

# Clone the repository
RUN curl -L https://github.com/edx/program-intent-engagement/archive/refs/heads/main.tar.gz | tar -xz --strip-components=1

RUN mkdir -p /edx/var/log

# Code is owned by root so it cannot be modified by the application user.
USER app

# Gunicorn 19 does not log to stdout or stderr by default. Once we are past gunicorn 19, the logging to STDOUT need not be specified.
CMD gunicorn --workers=2 --name program-intent-engagement -c /edx/app/program-intent-engagement/program_intent_engagement/docker_gunicorn_configuration.py --log-file - --max-requests=1000 program_intent_engagement.wsgi:application
