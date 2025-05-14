ARG BUILD_FROM=ghcr.io/home-assistant/amd64-base-ubuntu:20.04
FROM ${BUILD_FROM} as builder

# Set shell and environment variables
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=off \
    CRAFTY_HOME=/crafty

# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    software-properties-common \
    curl \
    git \
    build-essential \
    libffi-dev \
    python3.9 \
    python3.9-dev \
    python3.9-venv \
    python3.9-distutils \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && curl -sS https://bootstrap.pypa.io/get-pip.py | python3.9

# Clone Crafty and setup venv
WORKDIR ${CRAFTY_HOME}
RUN git clone --depth=1 https://gitlab.com/crafty-controller/crafty-4.git git
WORKDIR ${CRAFTY_HOME}/git
RUN python3.9 -m venv ${CRAFTY_HOME}/venv \
    && ${CRAFTY_HOME}/venv/bin/pip install --upgrade pip wheel setuptools \
    && ${CRAFTY_HOME}/venv/bin/pip install -r requirements.txt \
    && ${CRAFTY_HOME}/venv/bin/pip install tzdata backports.zoneinfo

FROM ${BUILD_FROM}

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    S6_BEHAVIOUR_IF_STAGE2_FAILS=2 \
    S6_CMD_WAIT_FOR_SERVICES=1 \
    CRAFTY_HOME=/crafty \
    PATH="/crafty/venv/bin:$PATH"

# Install runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    openjdk-8-jre-headless \
    openjdk-11-jre-headless \
    openjdk-17-jre-headless \
    openjdk-21-jre-headless \
    python3.9 \
    sudo \
    wget \
    zip \
    unzip \
    jq \
    openssl \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Create crafty user
RUN groupadd -r crafty && \
    useradd -r -g crafty -G root -d ${CRAFTY_HOME} -s /bin/bash crafty && \
    echo "crafty ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers.d/craft

# Copy from builder
COPY --from=builder ${CRAFTY_HOME}/venv ${CRAFTY_HOME}/venv
COPY --from=builder ${CRAFTY_HOME}/git/app ${CRAFTY_HOME}/app
COPY --from=builder ${CRAFTY_HOME}/git/main.py ${CRAFTY_HOME}/
COPY --from=builder ${CRAFTY_HOME}/git/docker_launcher.sh ${CRAFTY_HOME}/

# Create initial directory structure and set up persistent storage locations
RUN mkdir -p \
    ${CRAFTY_HOME}/backups \
    ${CRAFTY_HOME}/config \
    ${CRAFTY_HOME}/import \
    ${CRAFTY_HOME}/logs \
    ${CRAFTY_HOME}/servers \
    /share/crafty/servers \
    /share/crafty/import \
    /share/crafty/config \
    /share/crafty/backups \
    /data/crafty/config

# Setup initial configuration
RUN cp -R ${CRAFTY_HOME}/app/config ${CRAFTY_HOME}/app/config_original \
    && mv ${CRAFTY_HOME}/app/config/default.json.example ${CRAFTY_HOME}/app/config/default.json \
    && echo '{"major": 4, "minor": 4, "sub": 7, "version": "4.4.7"}' > ${CRAFTY_HOME}/app/config/version.json

# Generate SSL certificates
RUN openssl req -x509 -nodes -days 3650 \
    -newkey rsa:2048 \
    -keyout ${CRAFTY_HOME}/app/config/ingress.key \
    -out ${CRAFTY_HOME}/app/config/ingress.crt \
    -subj "/CN=CraftyController" \
    && chmod 640 ${CRAFTY_HOME}/app/config/ingress.key \
    && chmod 644 ${CRAFTY_HOME}/app/config/ingress.crt

# Set permissions
RUN chown -R crafty:root ${CRAFTY_HOME} \
    && chown -R crafty:root /share/crafty \
    && chown -R crafty:root /data/crafty \
    && chmod -R 755 ${CRAFTY_HOME} \
    && chmod -R 755 /share/crafty \
    && chmod -R 755 /data/crafty \
    && chmod 644 ${CRAFTY_HOME}/app/config/version.json

# Copy our modified launcher script based in Crafty docker-launcher.sh
COPY run.sh /
RUN chmod a+x /run.sh

# Expose ports (WebUI, Minecraft servers, etc.)
EXPOSE 8443/tcp \
    8433/tcp \
    8100/tcp \
    8023/tcp \
    19132/udp \
    19134/udp \
    25500/tcp \
    25565-25570/tcp

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