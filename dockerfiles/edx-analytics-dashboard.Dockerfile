FROM ubuntu:focal AS app

ENV DEBIAN_FRONTEND=noninteractive

ARG PYTHON_VERSION=3.12

# Packages installed:

# pkg-config; mysqlclient>=2.2.0 requires pkg-config (https://github.com/PyMySQL/mysqlclient/issues/620)

RUN apt-get update && \
  apt-get install -y software-properties-common && \
  apt-add-repository -y ppa:deadsnakes/ppa && \
  apt-get install --no-install-recommends -qy \
  language-pack-en \
  build-essential \
  python${PYTHON_VERSION}-dev \
  libmysqlclient-dev \
  pkg-config \
  libssl-dev \
  # needed by phantomjs
  libfontconfig \
  # needed by i18n tests in CI
  gettext \
  # needed by a11y tests script
  curl \
  # needed to install github based dependency
  git && \
  rm -rf /var/lib/apt/lists/*

RUN locale-gen en_US.UTF-8
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

# ENV variables lifetime is bound to the container whereas ARGS variables lifetime is bound to the image building process only
# Also ARGS provide us an option of compatibility of Path structure for Tutor and other OpenedX installations
ARG COMMON_CFG_DIR="/edx/etc"
ARG COMMON_APP_DIR="/edx/app"
ARG INSIGHTS_APP_DIR="${COMMON_APP_DIR}/insights"
ARG INSIGHTS_VENV_DIR="${COMMON_APP_DIR}/insights/venvs/insights"
ARG INSIGHTS_CODE_DIR="${INSIGHTS_APP_DIR}/edx_analytics_dashboard"
ARG INSIGHTS_NODEENV_DIR="${COMMON_APP_DIR}/insights/nodeenvs/insights"

ENV PATH="${INSIGHTS_VENV_DIR}/bin:${INSIGHTS_NODEENV_DIR}/bin:$PATH"
ENV INSIGHTS_APP_DIR=${INSIGHTS_APP_DIR}
ENV THEME_SCSS="sass/themes/open-edx.scss"
ENV PYTHON_VERSION="${PYTHON_VERSION}"

RUN curl -sS https://bootstrap.pypa.io/get-pip.py | python${PYTHON_VERSION}
RUN pip install virtualenv

# No need to activate insights virtualenv as it is already activated by putting in the path
RUN virtualenv -p python${PYTHON_VERSION} --always-copy ${INSIGHTS_VENV_DIR}

ENV PATH="${INSIGHTS_CODE_DIR}/node_modules/.bin:$PATH"

WORKDIR ${INSIGHTS_CODE_DIR}/

# Create required directories for requirements
RUN mkdir -p requirements

# insights service config commands below
RUN curl -L -o requirements/production.txt https://raw.githubusercontent.com/edx/edx-analytics-dashboard/master/requirements/production.txt
RUN pip install  --no-cache-dir -r requirements/production.txt

RUN curl -L https://github.com/edx/edx-analytics-dashboard/archive/refs/heads/master.tar.gz | tar -xz --strip-components=1

# Ensure the repository is owned by the app user (when running with app user)
RUN chown -R app:app ${INSIGHTS_CODE_DIR}

# Copy the entrypoint script that configures git safe.directory at runtime
COPY dockerfiles/git-safe-entrypoint.sh /usr/local/bin/git-safe-entrypoint.sh
RUN chmod +x /usr/local/bin/git-safe-entrypoint.sh

RUN curl -L -o ${INSIGHTS_CODE_DIR}/analytics_dashboard/settings/devstack.py https://raw.githubusercontent.com/edx/devstack/master/py_configuration_files/analytics_dashboard.py

RUN nodeenv ${INSIGHTS_NODEENV_DIR} --node=18.20.2 --prebuilt \
  && npm install -g npm@10.5.x

RUN npm set progress=false && npm ci

EXPOSE 8110
EXPOSE 18110

FROM app AS dev

RUN pip install --no-cache-dir -r requirements/local.txt

ENV DJANGO_SETTINGS_MODULE="analytics_dashboard.settings.devstack"

# Backwards compatibility with devstack
RUN touch "${INSIGHTS_APP_DIR}/insights_env"

# Configure git safe.directory (needed for git operations at runtime)
RUN git config --global --add safe.directory ${INSIGHTS_CODE_DIR}

# Use entrypoint to handle runtime UID changes in Kubernetes
ENTRYPOINT ["/usr/local/bin/git-safe-entrypoint.sh"]
CMD while true; do python ./manage.py runserver 0.0.0.0:8110; sleep 2; done

FROM app AS prod

ENV DJANGO_SETTINGS_MODULE="analytics_dashboard.settings.production"

# Configure git safe.directory (needed for git operations at runtime)
RUN git config --global --add safe.directory ${INSIGHTS_CODE_DIR}

# Use entrypoint to handle runtime UID changes in Kubernetes
ENTRYPOINT ["/usr/local/bin/git-safe-entrypoint.sh"]
CMD gunicorn \
  --pythonpath=/edx/app/insights/edx_analytics_dashboard/analytics_dashboard \
  --timeout=300 \
  -b 0.0.0.0:8110 \
  -w 2 \
  - analytics_dashboard.wsgi:application
