ARG BUILD_FROM=ghcr.io/home-assistant/amd64-base-ubuntu:20.04
FROM ${BUILD_FROM}

# Set shell
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=off \
    S6_BEHAVIOUR_IF_STAGE2_FAILS=2 \
    S6_CMD_WAIT_FOR_SERVICES=1 \
    CRAFTY_HOME=/crafty \
    PATH="/crafty/venv/bin:$PATH"

# Copy local files
COPY run.sh /
RUN chmod a+x /run.sh

# Install dependencies and setup environment
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        openjdk-8-jre-headless \
        openjdk-11-jre-headless \
        openjdk-17-jre-headless \
        openjdk-21-jre-headless \
        software-properties-common \
        curl \
        sudo \
        wget \
        zip \
        unzip \
        git \
        gnupg \
        dirmngr \
        ca-certificates \
        build-essential \
        libffi-dev \
        jq \
        openssl \
    && add-apt-repository -y ppa:deadsnakes/ppa \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        python3.9 \
        python3.9-dev \
        python3.9-venv \
        python3.9-distutils \
        openjdk-11-jre-headless \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && curl -sS https://bootstrap.pypa.io/get-pip.py | python3.9

# Create crafty user and group
RUN groupadd -r crafty && \
    useradd -r -g crafty -G root -d ${CRAFTY_HOME} -s /bin/bash crafty && \
    echo "crafty ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers.d/craft

# Create required directories
    #${CRAFTY_HOME}/app \
    #${CRAFTY_HOME}/app/config \
RUN mkdir -p ${CRAFTY_HOME}/backups \
    ${CRAFTY_HOME}/config \
    ${CRAFTY_HOME}/app/config \
    ${CRAFTY_HOME}/import \
    ${CRAFTY_HOME}/logs \
    ${CRAFTY_HOME}/servers \
    ${CRAFTY_HOME}/git

# Clone Crafty Controller repository
RUN git clone --depth=1 https://gitlab.com/crafty-controller/crafty-4.git ${CRAFTY_HOME}/git

# Copy Crafty app files to expected location
RUN cp -R ${CRAFTY_HOME}/git/app/ ${CRAFTY_HOME}/
RUN cp -R ${CRAFTY_HOME}/app/config ${CRAFTY_HOME}/app/config_original \
    && mv ${CRAFTY_HOME}/app/config/default.json.example ${CRAFTY_HOME}/app/config/default.json
# Copy Crafty python launcher to expected location
RUN cp ${CRAFTY_HOME}/git/main.py ${CRAFTY_HOME}/

# Create virtual environment and install required packages
WORKDIR ${CRAFTY_HOME}/git
RUN python3.9 -m venv ${CRAFTY_HOME}/venv \
    && ${CRAFTY_HOME}/venv/bin/pip install --upgrade pip \
    && ${CRAFTY_HOME}/venv/bin/pip install wheel setuptools \
    && ${CRAFTY_HOME}/venv/bin/pip install -r requirements.txt \
    && ${CRAFTY_HOME}/venv/bin/pip install tzdata backports.zoneinfo

# Copy the docker launcher script to make it compatible with Home Assistant
#RUN cp ${CRAFTY_HOME}/git/docker_launcher.sh ${CRAFTY_HOME}/

# Set appropriate permissions
RUN chown -R crafty:root ${CRAFTY_HOME} && \
    chmod -R 755 ${CRAFTY_HOME}

# Expose ports (WebUI, Minecraft servers, etc.)
EXPOSE 8443 8100 8023 19132/udp 19134/udp 25500 25565-25570

# Labels
ARG BUILD_ARCH
ARG BUILD_DATE
ARG BUILD_DESCRIPTION
ARG BUILD_NAME
ARG BUILD_REF
ARG BUILD_REPOSITORY
ARG BUILD_VERSION

LABEL \
    io.hass.name="${BUILD_NAME}" \
    io.hass.description="${BUILD_DESCRIPTION}" \
    io.hass.arch="${BUILD_ARCH}" \
    io.hass.type="addon" \
    io.hass.version=${BUILD_VERSION} \
    maintainer="The BFG" \
    org.opencontainers.image.title="${BUILD_NAME}" \
    org.opencontainers.image.description="${BUILD_DESCRIPTION}" \
    org.opencontainers.image.vendor="Home Assistant Add-on" \
    org.opencontainers.image.authors="The BFG" \
    org.opencontainers.image.licenses="MIT" \
    org.opencontainers.image.url="https://github.com/elysiandc/hassio-addons" \
    org.opencontainers.image.source="https://github.com/elysiandc/hassio-addons/tree/main/crafty-controller" \
    org.opencontainers.image.documentation="https://github.com/elysiandc/hassio-addons/blob/main/crafty-controller/README.md" \
    org.opencontainers.image.created=${BUILD_DATE} \
    org.opencontainers.image.revision=${BUILD_REF} \
    org.opencontainers.image.version=${BUILD_VERSION}

WORKDIR ${CRAFTY_HOME}
ENTRYPOINT ["/run.sh"]