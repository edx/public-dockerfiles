FROM ubuntu:focal AS app

# ENV variables for Python 3.11 support
ARG PYTHON_VERSION=3.11
ENV TZ=UTC
ENV TERM=xterm-256color
ENV DEBIAN_FRONTEND=noninteractive

# software-properties-common is needed to setup Python 3.11 env
RUN apt-get update && \
  apt-get install -y software-properties-common && \
  apt-add-repository -y ppa:deadsnakes/ppa

# System requirements

RUN apt-get upgrade -qy && \
    apt-get install -qy \
    build-essential \
    language-pack-en locales git curl \
    python${PYTHON_VERSION} \
    python${PYTHON_VERSION}-dev \
    python${PYTHON_VERSION}-distutils \
    libmysqlclient-dev libssl-dev \
    pkg-config wget unzip && \
    rm -rf /var/lib/apt/lists/*

RUN update-alternatives --install /usr/bin/python3 python3 /usr/bin/python${PYTHON_VERSION} 1

# need to use virtualenv pypi package with Python 3.11
RUN curl -sS https://bootstrap.pypa.io/get-pip.py | python${PYTHON_VERSION}
RUN pip install virtualenv

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

# Create xqueue user for running the app
RUN useradd -m --shell /bin/false xqueue

# Copy the entrypoint script that configures git safe.directory at runtime
COPY dockerfiles/git-safe-entrypoint.sh /usr/local/bin/git-safe-entrypoint.sh
RUN chmod +x /usr/local/bin/git-safe-entrypoint.sh

# Expose ports.
EXPOSE 8040

FROM app AS dev

RUN curl -L -o ${XQUEUE_CODE_DIR}/requirements/dev.txt https://raw.githubusercontent.com/openedx/xqueue/master/requirements/dev.txt
# xqueue service config commands below
RUN pip install -r ${XQUEUE_CODE_DIR}/requirements/dev.txt

# cloning git repo
RUN curl -L https://github.com/openedx/xqueue/archive/refs/heads/master.tar.gz | tar -xz --strip-components=1

# Ensure the repository is owned by the xqueue user
RUN chown -R xqueue:xqueue ${XQUEUE_CODE_DIR}

RUN curl -L -o ${XQUEUE_CODE_DIR}/xqueue/devstack.py https://raw.githubusercontent.com/edx/devstack/master/py_configuration_files/xqueue.py

ENV DJANGO_SETTINGS_MODULE xqueue.devstack

USER xqueue
# Configure git safe.directory as the xqueue user
RUN git config --global --add safe.directory ${XQUEUE_CODE_DIR}

# Use entrypoint to handle runtime UID changes in Kubernetes
ENTRYPOINT ["/usr/local/bin/git-safe-entrypoint.sh"]
CMD while true; do python ./manage.py runserver 0.0.0.0:8040; sleep 2; done

FROM app AS production

RUN curl -L -o ${XQUEUE_APP_DIR}/requirements.txt https://raw.githubusercontent.com/openedx/xqueue/master/requirements.txt
# xqueue service config commands below
RUN pip install -r ${XQUEUE_APP_DIR}/requirements.txt

# cloning git repo
RUN curl -L https://github.com/openedx/xqueue/archive/refs/heads/master.tar.gz | tar -xz --strip-components=1

# Ensure the repository is owned by the xqueue user
RUN chown -R xqueue:xqueue ${XQUEUE_CODE_DIR}

ENV DJANGO_SETTINGS_MODULE=xqueue.production

USER xqueue
# Configure git safe.directory as the xqueue user
RUN git config --global --add safe.directory ${XQUEUE_CODE_DIR}

# Use entrypoint to handle runtime UID changes in Kubernetes
ENTRYPOINT ["/usr/local/bin/git-safe-entrypoint.sh"]
CMD gunicorn \
    --pythonpath=/edx/app/xqueue/xqueue \
    --timeout=300 \
    -b 0.0.0.0:8040 \
    -w 2 \
    - xqueue.wsgi:application
