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

# USB and permissions setup
RUN groupadd -f dialout && \
    usermod -a -G dialout user

# Grant permissions to /dev/tty* devices (required to avoid sudo for serial access)
RUN sudo chown user:dialout /dev/tty* || true

RUN usermod -a -G plugdev,dialout user
# This seemed to be required in some cases for openocd loading
RUN service udev restart || true

USER user

FROM user-setup AS python-setup

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
    pip install --upgrade pip wheel

ENV PATH="/home/user/.local/bin:${PATH}"

# Path variable to the requirements.txt which specifies Fprime's python deps
ARG REQUIREMENTS_FILE
COPY $REQUIREMENTS_FILE .

# install the deps and remove after use
RUN pip install -r combined_requirements.txt && rm -f $REQUIREMENTS_FILE

FROM python-setup AS west-setup

WORKDIR $FSW_WDIR

ENV ZEPHYR_BASE=${FSW_WDIR}/deps/zephyr
ENV PATH=$PATH:/home/user/zephyr-sdk-0.17.0/arm-zephyr-eabi/bin

# Its unclear whether theres much advantage to be had to include the workspace
# in the image
COPY .west ${FSW_WDIR}/.west
COPY ./BaseDeployment/west.yml ${FSW_WDIR}/BaseDeployment/west.yml

# NOTE for zephyr deps, the latest branch supports this instead of a requirements.txt file
RUN pip install west && west update -n && west packages pip --install

RUN west sdk install -t arm-zephyr-eabi

# Remove the apt cache at the end to reduce image size
USER root
RUN apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
USER user
