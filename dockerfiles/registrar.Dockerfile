FROM ubuntu:focal AS app

# ENV variables for Python 3.12 support
ARG PYTHON_VERSION=3.12
ENV TZ=UTC
ENV TERM=xterm-256color
ENV DEBIAN_FRONTEND=noninteractive

# software-properties-common is needed to setup Python 3.12 env
RUN apt-get update && \
  apt-get install -y software-properties-common && \
  apt-add-repository -y ppa:deadsnakes/ppa

# System requirements.
RUN apt-get update
RUN apt-get install -qy \
	git-core \
	language-pack-en \
	build-essential \
	# libmysqlclient-dev header files needed to use native C implementation for MySQL-python for performance gains.
	libmysqlclient-dev \
	# mysqlclient wont install without libssl-dev
	libssl-dev \
	# mysqlclient>=2.2.0 requires pkg-config (https://github.com/PyMySQL/mysqlclient/issues/620)
	pkg-config \
	curl \
	python3-pip \
	python${PYTHON_VERSION} \
	python${PYTHON_VERSION}-dev \
	python${PYTHON_VERSION}-distutils

# need to use virtualenv pypi package with Python 3.12
RUN curl -sS https://bootstrap.pypa.io/get-pip.py | python${PYTHON_VERSION}
RUN pip install virtualenv

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

ARG COMMON_CFG_DIR="/edx/etc"
ARG COMMON_APP_DIR="/edx/app"
ARG REGISTRAR_APP_DIR="${COMMON_APP_DIR}/registrar"
ARG REGISTRAR_VENV_DIR="${COMMON_APP_DIR}/venvs/registrar"
ARG REGISTRAR_CODE_DIR="${REGISTRAR_APP_DIR}"

ENV PATH="$REGISTRAR_VENV_DIR/bin:$PATH"
ENV REGISTRAR_APP_DIR=${REGISTRAR_APP_DIR}
ENV REGISTRAR_CODE_DIR=${REGISTRAR_CODE_DIR}

# Working directory will be root of repo.
WORKDIR ${REGISTRAR_CODE_DIR}

RUN mkdir -p requirements

RUN virtualenv -p python${PYTHON_VERSION} --always-copy ${REGISTRAR_VENV_DIR}

RUN pip install --upgrade pip setuptools

ENV REGISTRAR_CFG="${COMMON_CFG_DIR}/registrar.yml"

# Expose ports.
EXPOSE 18734
EXPOSE 18735

FROM app AS dev

# fetching the requirement file that is needed
RUN curl -L -o requirements/devstack.txt https://raw.githubusercontent.com/edx/registrar/master/requirements/devstack.txt

RUN pip install --no-cache-dir -r ${REGISTRAR_CODE_DIR}/requirements/devstack.txt

# cloning the repository after requirements installation
RUN curl -L https://github.com/edx/registrar/archive/refs/heads/master.tar.gz | tar -xz --strip-components=1

RUN curl -L -o ${REGISTRAR_CODE_DIR}/registrar/settings/devstack.py https://raw.githubusercontent.com/edx/devstack/main/py_configuration_files/registrar.py

ENV DJANGO_SETTINGS_MODULE registrar.settings.devstack

CMD while true; do python ./manage.py runserver 0.0.0.0:18734; sleep 2; done

FROM app AS prod

# fetching the requirement file that is needed
RUN curl -L -o requirements/production.txt https://raw.githubusercontent.com/edx/registrar/master/requirements/production.txt

RUN pip install --no-cache-dir -r ${REGISTRAR_CODE_DIR}/requirements/production.txt

# cloning the repository after requirements installation
RUN curl -L https://github.com/edx/registrar/archive/refs/heads/master.tar.gz | tar -xz --strip-components=1

ENV DJANGO_SETTINGS_MODULE=registrar.settings.production

CMD ["gunicorn", "--workers=2", "--name", "registrar", "-c", "/edx/app/registrar/registrar/docker_gunicorn_configuration.py", "--max-requests=1000", "registrar.wsgi:application"]
