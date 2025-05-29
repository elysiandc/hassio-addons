ARG BUILD_FROM=registry.gitlab.com/crafty-controller/crafty-4:latest
FROM ${BUILD_FROM}

# Install jq for JSON parsing
RUN apt-get update && apt-get install -y jq lsof curl nano sqlite3 && rm -rf /var/lib/apt/lists/*

# Define additional Home Assistant environment variables
ENV PYTHONUNBUFFERED=1 \
    DATA_DIR=/share/crafty

# Copy Home Assistant addon run script
COPY run.sh /run.sh
RUN chmod a+x /run.sh

# Expose additional Home Assistant addon ports
EXPOSE 8433/tcp 8100/tcp 8022/tcp 8023/tcp 19132-19139/udp 25565-25570/tcp

# Home Assistant Labels
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

# Use our custom entrypoint instead of the Crafty one
ENTRYPOINT ["/run.sh"]