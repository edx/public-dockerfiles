FROM ubuntu:jammy AS app

# ARG and ENV variables for Python 3.12 support
ARG PYTHON_VERSION=3.12
ENV TZ=UTC
ENV TERM=xterm-256color
ENV DEBIAN_FRONTEND=noninteractive

# System requirements. software-properties-common is only needed to add the
# deadsnakes PPA for Python 3.12, so it is removed again in the same layer.
RUN apt-get update && \
    apt-get install -qy software-properties-common && \
    apt-add-repository -y ppa:deadsnakes/ppa && \
    apt-get update && \
    apt-get upgrade -qy && \
    apt-get install -qy \
    build-essential \
    language-pack-en locales git curl \
    libmysqlclient-dev libssl-dev \
    pkg-config wget unzip \
    python${PYTHON_VERSION} \
    python${PYTHON_VERSION}-dev \
    python${PYTHON_VERSION}-venv && \
    apt-get purge -qy software-properties-common && \
    apt-get autoremove -qy && \
    rm -rf /var/lib/apt/lists/*

RUN update-alternatives --install /usr/bin/python3 python3 /usr/bin/python${PYTHON_VERSION} 1

# Bootstrap a Python 3.12 pip. We can't use Ubuntu's apt python3-pip because it is
# built for the system Python and breaks when run under Python 3.12.
RUN curl -fsSL -o /tmp/get-pip.py https://bootstrap.pypa.io/get-pip.py && \
    python${PYTHON_VERSION} /tmp/get-pip.py && \
    rm /tmp/get-pip.py
RUN python${PYTHON_VERSION} -m pip install virtualenv

# Use UTF-8.
RUN locale-gen en_US.UTF-8
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

ARG COMMON_APP_DIR="/edx/app"
ARG XQUEUE_APP_DIR="${COMMON_APP_DIR}/xqueue"
ENV XQUEUE_APP_DIR="${COMMON_APP_DIR}/xqueue"
ENV XQUEUE_VENV_DIR="${COMMON_APP_DIR}/xqueue/venvs/xqueue"
ENV XQUEUE_CODE_DIR="${XQUEUE_APP_DIR}/xqueue"

ENV PATH="$XQUEUE_VENV_DIR/bin:$PATH"

# Working directory will be root of repo.
WORKDIR ${XQUEUE_CODE_DIR}

RUN mkdir -p requirements

RUN virtualenv -p python${PYTHON_VERSION} --always-copy ${XQUEUE_VENV_DIR}

# Create placeholder file for devstack provisioning, if needed
RUN touch ${XQUEUE_APP_DIR}/xqueue_env

# This line is after the requirements so that changes to the code will not

# Expose ports.
EXPOSE 8040

FROM app AS dev

RUN curl -L -o ${XQUEUE_CODE_DIR}/requirements/dev.txt https://raw.githubusercontent.com/edx/xqueue/master/requirements/dev.txt
# xqueue service config commands below
RUN pip install -r ${XQUEUE_CODE_DIR}/requirements/dev.txt

# cloning git repo
RUN curl -L https://github.com/edx/xqueue/archive/refs/heads/master.tar.gz | tar -xz --strip-components=1

RUN curl -L -o ${XQUEUE_CODE_DIR}/xqueue/devstack.py https://raw.githubusercontent.com/edx/devstack/master/py_configuration_files/xqueue.py

ENV DJANGO_SETTINGS_MODULE xqueue.devstack

CMD while true; do python ./manage.py runserver 0.0.0.0:8040; sleep 2; done

FROM app AS production

RUN curl -L -o ${XQUEUE_APP_DIR}/requirements.txt https://raw.githubusercontent.com/edx/xqueue/master/requirements.txt
# xqueue service config commands below
RUN pip install -r ${XQUEUE_APP_DIR}/requirements.txt

# cloning git repo
RUN curl -L https://github.com/edx/xqueue/archive/refs/heads/master.tar.gz | tar -xz --strip-components=1

ENV DJANGO_SETTINGS_MODULE=xqueue.production

CMD gunicorn \
    --pythonpath=/edx/app/xqueue/xqueue \
    --timeout=300 \
    -b 0.0.0.0:8040 \
    -w 2 \
    - xqueue.wsgi:application
