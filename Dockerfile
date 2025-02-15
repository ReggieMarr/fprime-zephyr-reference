# Base image with common system packages
FROM ubuntu:24.04 AS base
ARG DEBIAN_FRONTEND=noninteractive
ENV TZ='America/Montreal'
RUN apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y --no-install-recommends git cmake ninja-build gperf \
    ccache dfu-util device-tree-compiler wget \
    python3.12-venv python3-dev python3-pip python3-setuptools python3-tk python3-wheel xz-utils file \
    make gcc gcc-multilib g++-multilib libsdl2-dev libmagic1

# User setup layer
FROM base AS user-setup
ARG WDIR=/fprime-zephyr-reference
ARG HOST_UID=1000
ARG HOST_GID=1000
ENV PATH="/home/user/.local/bin:${PATH}"

RUN userdel -r ubuntu || true && \
    getent group 1000 && getent group 1000 | cut -d: -f1 | xargs groupdel || true && \
    groupadd -g ${HOST_GID} user && \
    useradd -u ${HOST_UID} -g ${HOST_GID} -m user && \
    echo 'user ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

RUN apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# USB and permissions setup
RUN groupadd -f dialout && \
    usermod -a -G dialout user

# Grant permissions to /dev/tty* devices (required to avoid sudo for serial access)
RUN sudo chown user:dialout /dev/tty* || true

RUN usermod -a -G plugdev,dialout user
RUN service udev restart || true

USER user

# # Final layer with project setup
# FROM mplab-setup AS project
FROM user-setup AS project-setup
ARG WDIR=/fprime-zephyr-reference
ARG GIT_BRANCH
ARG GIT_COMMIT

WORKDIR $WDIR

USER user
RUN git clone https://github.com/ReggieMarr/fprime-zephyr-reference.git $WDIR && \
    git fetch && \
    git checkout $GIT_BRANCH && \
    git reset --hard $GIT_COMMIT && \
    git submodule update --init --depth 1 --recommend-shallow

# Create virtual environment
ENV VIRTUAL_ENV=/home/user/venv
# USER root
# # RUN chown -R user:user $WDIR


# USER user
RUN python3 -m venv $VIRTUAL_ENV
ENV PATH="$VIRTUAL_ENV/bin:$PATH"
# ENV PYTHONPATH="$VIRTUAL_ENV/lib/python$(python3 -c 'import sys; print(".".join(map(str, sys.version_info[:2])))')/site-packages:$PYTHONPATH"

# USER root
# # Set ownership
# WORKDIR $WDIR
# # RUN chown -R user:user $VIRTUAL_ENV
# USER user

# Activate virtual environment in various shell initialization files
RUN echo "source $VIRTUAL_ENV/bin/activate" >> ~/.bashrc && \
    echo "source $VIRTUAL_ENV/bin/activate" >> ~/.profile

# Upgrade pip in virtual environment
RUN pip install --upgrade pip

# Install Python packages (now using pip directly in virtualenv)
RUN pip install setuptools_scm && \
    pip install -r $WDIR/fprime/requirements.txt

FROM project-setup AS zephyr-setup

# install west and leverage that to install dependencies
RUN pip install west

WORKDIR ${WDIR}/LedBlinker

ENV ZEPHYR_BASE=${WDIR}/deps/zephyr
ENV PATH=$PATH:/home/user/zephyr-sdk-0.17.0/arm-zephyr-eabi/bin
RUN west update
# This can be done on main
# RUN west packages pip --install
RUN pip install -r ${ZEPHYR_BASE}/scripts/requirements.txt
RUN west sdk install -t arm-zephyr-eabi
RUN west zephyr-export

WORKDIR $WDIR
