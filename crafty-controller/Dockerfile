ARG BUILD_FROM=ghcr.io/home-assistant/amd64-base-python:3.12-alpine3.21
FROM ${BUILD_FROM}

# Define environment variables
ENV CRAFTY_HOME=/crafty \
    PYTHONUNBUFFERED=1

# Install runtime dependencies and setup system
RUN apk add --no-cache \
    bash \
    git \
    jq \
    openssl \
    python3 \
    python3-dev \
    su-exec \
    sudo \
    unzip \
    wget \
    zip \
    build-base \
    libffi-dev \
    openjdk8-jre-base \
    openjdk11-jre-headless \
    openjdk17-jre-headless \
    openjdk21-jre-headless \
    && addgroup -S crafty \
    && adduser -G root -D crafty \
    && addgroup crafty root \
    && echo "crafty ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers.d/crafty \
    && mkdir -p ${CRAFTY_HOME}

# Copy run script
COPY run.sh /run.sh
RUN chmod a+x /run.sh

# Expose ports
EXPOSE 8443/tcp 8433/tcp 8100/tcp 8023/tcp 19132/udp 19134/udp 25500/tcp 25565-25570/tcp

# Labels
ARG BUILD_ARCH BUILD_DATE BUILD_DESCRIPTION BUILD_NAME BUILD_REF BUILD_REPOSITORY BUILD_VERSION
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