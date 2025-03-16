# Base image with common system packages
FROM ubuntu:24.04 AS base
ARG DEBIAN_FRONTEND=noninteractive
ENV TZ='America/Montreal'
RUN apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y  --no-install-recommends \
    python3-dev python3 python3-full python3-pip python3-wheel python3-venv libpython3-dev \
    ninja-build gperf ccache dfu-util device-tree-compiler libicu-dev libsdl2-dev libmagic1 \
    make gcc gcc-multilib g++-multilib gdb gdbserver cmake build-essential clang-format xz-utils \
    file wget curl jq git rsync sudo

# User setup layer
FROM base AS user-setup

# Create a non-root user for better security practices
ARG HOST_UID=1000
ARG HOST_GID=1000
ARG FSW_WDIR=/fprime-zephyr-reference
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

WORKDIR $FSW_WDIR

USER user
# Setup python virtual environment
ENV VIRTUAL_ENV=/home/user/venv
RUN python3 -m venv $VIRTUAL_ENV
ENV PATH="/home/user/.local/bin:$VIRTUAL_ENV/bin:$PATH"

# Activate virtual environment in various shell initialization files
# Upgrade pip in virtual environment
RUN echo "source $VIRTUAL_ENV/bin/activate" >> ~/.bashrc && \
    echo "source $VIRTUAL_ENV/bin/activate" >> ~/.profile && \
    pip install --upgrade pip

ENV PATH="/home/user/.local/bin:${PATH}"

# Set the working directory for fprime software
WORKDIR $FSW_WDIR

# Install fprime specific dev env
RUN pip install setuptools setuptools_scm wheel pip

COPY tmp_requirements.txt .

RUN pip install -r tmp_requirements.txt

# Remove these as they are no longer needed
USER root
RUN rm -f tmp_requirements.txt
USER user

FROM project-setup AS zephyr-setup

# install west and leverage that to install dependencies
RUN pip install west

WORKDIR ${FSW_WDIR}/LedBlinker

ENV ZEPHYR_BASE=${FSW_WDIR}/deps/zephyr
ENV PATH=$PATH:/home/user/zephyr-sdk-0.17.0/arm-zephyr-eabi/bin
# RUN west update
# This can be done on main
# RUN west packages pip --install

COPY ./deps/zephyr/scripts/requirements.txt .

# RUN pip install -r requirements.txt
# RUN west sdk install -t arm-zephyr-eabi
# RUN west zephyr-export

WORKDIR $FSW_WDIR
