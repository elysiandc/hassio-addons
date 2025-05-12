ARG BUILD_FROM
FROM "ghcr.io/home-assistant/amd64-base:latest"

# Set shell
#SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Enable verbose output for build logs
# Set S6 to report any failure during add-on startup
ENV S6_VERBOSITY=2
ENV S6_BEHAVIOUR_IF_STAGE2_FAILS=2

# Print debug info
RUN echo "===> CRAFTY-ADDON: Build environment information:" && env

# Set environment variables
ENV PYTHONUNBUFFERED=1
ENV PATH="/usr/local/bin:${PATH}"
ENV CRAFTY_INSTALL_DIR="/crafty"
ENV CRAFTY_USER="crafty"
ENV TZ=UTC

# Add dependencies
RUN \
    echo "** Checking available Java versions **" \
    && apk search "openjdk*" \
    && echo "** Installing base dependencies **" \
    # && apk add --no-cache \
    && apk add \
        bash \
        curl \
        wget \
        git \
        python3 \
        py3-pip \
        py3-wheel \
        build-base \
        python3-dev \
        # Multiple Java versions for different Minecraft servers
        openjdk8-jre \
        openjdk11-jre \
        openjdk17-jre \
        openjdk21-jre \
        # Development kits for potential server plugins
        openjdk8 \
        openjdk11 \
        openjdk17 \
        openjdk21 \
        zip \
        unzip \
        tar \
        fontconfig \
        ttf-dejavu \
        ca-certificates \
        nginx \
        libstdc++ \
        libc6-compat \
        gcompat \
        # Extra utilities for Minecraft servers
        nano \
        htop \
        jq \
    && echo "** Finished installing base dependencies **"
    # Bashio is already included in the base image

# Setup the folders in the host for mappings
COPY install /
RUN chmod a+x /install

# Create crafty user and directories
RUN \
    echo "** Creating crafty user **" \
    && mkdir -p ${CRAFTY_INSTALL_DIR} \
    && addgroup -g 1000 crafty \
    && adduser -u 1000 -G crafty -D -H -s /bin/bash crafty \
    && mkdir -p ${CRAFTY_INSTALL_DIR}/app \
    && mkdir -p ${CRAFTY_INSTALL_DIR}/servers \
    && mkdir -p ${CRAFTY_INSTALL_DIR}/backups \
    && mkdir -p ${CRAFTY_INSTALL_DIR}/import \
    && mkdir -p ${CRAFTY_INSTALL_DIR}/logs

# Clone Crafty Controller repo
ARG CRAFTY_VERSION
RUN \
    echo "** Cloning Crafty Controller ${CRAFTY_VERSION} **" \
    && cd /tmp \
    && git clone --branch master https://gitlab.com/crafty-controller/crafty-4.git \
    && cd crafty-4 \
    && echo "** Crafty version: $(git describe --tags) **" \
    && cp -R . ${CRAFTY_INSTALL_DIR}/ \
    && cd ${CRAFTY_INSTALL_DIR}/app \
    && echo "** Installing Crafty requirements **" \
    # Alpine-specific modifications for Crafty requirements
    && apk add --no-cache --virtual .build-deps \
        gcc \
        musl-dev \
        libffi-dev \
        openssl-dev \
    && apk del .build-deps \
    && echo "** Cleanup after installation **" \
    && rm -rf /tmp/crafty-4 \
    && chown -R crafty:crafty ${CRAFTY_INSTALL_DIR}

# Switch to working dir and prepare virtualenv
WORKDIR $CRAFTY_INSTALL_DIR
USER $CRAFTY_USER
# Set up Python virtual environment for Crafty
RUN echo "** Creating Python virtual environment for Crafty **" \
    && python3 -m venv /crafty/.venv \
    && . /crafty/.venv/bin/activate \
    && pip install --upgrade pip setuptools wheel packaging \
    && echo "** Installing Crafty requirements in virtualenv **" \
    && pip install --no-cache-dir -r /crafty/requirements.txt \
    && echo "** Python environment setup complete **"
USER root

# Copy run script and make executable
COPY run.sh /
RUN chmod a+x /run.sh
#COPY run.sh /etc/services.d/crafty/run
#RUN chmod +x /etc/services.d/crafty/run

# Working directory
WORKDIR ${CRAFTY_INSTALL_DIR}/app

# Create persistent directories and set permissions
RUN mkdir -p /data && chown -R crafty:crafty /data

# Define volumes
VOLUME [ "/crafty/app/config", "/crafty/servers", "/crafty/backups", "/crafty/import", "/crafty/logs" ]

# Expose ports (WebUI, Minecraft servers, etc.)
EXPOSE 8000 8443 8100 19132/udp 19134/udp 25500

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

CMD ["/run.sh"]