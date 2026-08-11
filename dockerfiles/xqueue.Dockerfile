FROM ubuntu:focal AS app

# ENV variables for Python 3.11 support
ARG PYTHON_VERSION=3.11
ENV TZ=UTC
ENV TERM=xterm-256color
ENV DEBIAN_FRONTEND=noninteractive

# software-properties-common is needed to setup Python 3.11 env
#
# NOTE: The deadsnakes PPA is no longer used to install Python 3.11. deadsnakes
# no longer has these packages for Ubuntu Focal, which is EOL. See BOMS-239 and
# BOMS-238. Python 3.11 is instead installed from vendored deb packages below.
RUN apt-get update && \
  apt-get install -y software-properties-common
  # Remember to add "&& \" to above line when restoring this:
  #apt-add-repository -y ppa:deadsnakes/ppa

# System requirements

RUN apt-get upgrade -qy && \
    apt-get install -qy \
    build-essential \
    language-pack-en locales git curl \
    libmysqlclient-dev libssl-dev \
    pkg-config wget unzip && \
    rm -rf /var/lib/apt/lists/*

# This section is a hack for installing Python 3.11 on out-of-support Ubuntu.
# These packages are built using the deadsnakes py3.11 repo and runbook.

# Packages that are needed for installing the vendored Python packages, but
# that can be found in the regular Ubuntu repositories. See BOMS-239. This
# bit should be entirely removed once we're installing Python 3.11 via apt.
RUN apt-get update && \
    apt-get -y install --no-install-recommends \
      libexpat1 libexpat1-dev mime-support tzdata libreadline8 libsqlite3-0

# This is a variable passed in via BuildKit that represents the architecture
# the docker image is being built for.
ARG TARGETARCH

RUN <<EOCMD
#!/usr/bin/env bash
    set -eu -o pipefail
    # Base URL for deb packages. For repeatability, we hardcode a
    # commit. (Normally this would be done using a build arg, but this is
    # intended as a quick hack.)
    url_base="https://raw.githubusercontent.com/edx/vendored/35b1ada7111d308f6b2c9413fc4e64f2a129f708/deadsnakes-py3.11-focal"
    # Build string that's present in the deb file names. (Just used to make the
    # names below easier to read.)
    build_version="3.11.13-15-g8adac492d4-1+focal1"
    # These must be kept topologically sorted, dependant packages last, as they
    # will be installed one at a time.
    #
    # The only packages we actually want are `python3.11{,-dev,-venv}`
    # but we need to include all of their dependencies first.
    vendored_pkgs=(
      "libpython3.11-minimal_${build_version}_${TARGETARCH}.deb"
      "python3.11-lib2to3_${build_version}_all.deb"
      "python3.11-minimal_${build_version}_${TARGETARCH}.deb"
      "python3.11-distutils_${build_version}_all.deb"
      "libpython3.11-stdlib_${build_version}_${TARGETARCH}.deb"
      "python3.11_${build_version}_${TARGETARCH}.deb"
      "libpython3.11_${build_version}_${TARGETARCH}.deb"
      "libpython3.11-dev_${build_version}_${TARGETARCH}.deb"
      "python3.11-dev_${build_version}_${TARGETARCH}.deb"
      # `python3.11-venv` was not one of the packages installed in EC2
      "python3.11-venv_${build_version}_${TARGETARCH}.deb"
    )
    mkdir /tmp/vendored_python
    for pkg in "${vendored_pkgs[@]}"; do
        debfile="/tmp/vendored_python/$pkg"
        curl -fLsS -o "$debfile" "$url_base/$pkg"
        dpkg -i "$debfile"
    done
    rm -rf /tmp/vendored_python
EOCMD

# End of vendored Python 3.11 section.

RUN update-alternatives --install /usr/bin/python3 python3 /usr/bin/python${PYTHON_VERSION} 1

# Bootstrap a Python 3.11 pip. We can't use Focal's apt python3-pip because it is
# built for the system Python 3.8 and breaks when run under Python 3.11.
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

# Copy the requirements explicitly even though we copy everything below.
# This prevents the image cache from busting unless the dependencies have changed.
RUN curl -L -o requirements.txt https://raw.githubusercontent.com/edx/xqueue/master/requirements.txt

# Dependencies are installed as root so they cannot be modified by the application user.
RUN pip install -r requirements.txt

# Create placeholder file for devstack provisioning, if needed
RUN touch ${XQUEUE_APP_DIR}/xqueue_env

# This line is after the requirements so that changes to the code will not
# bust the image cache.
RUN curl -L https://github.com/edx/xqueue/archive/refs/heads/master.tar.gz | tar -xz --strip-components=1

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
