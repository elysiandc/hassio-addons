# This is largely based on https://gitlab.com/crafty-controller/crafty-4/-/blob/master/Dockerfile

ARG BUILD_FROM
FROM $BUILD_FROM

ENV LANG C.UTF-8

# Install dependencies
RUN apk add --no-cache \
    docker \
    bash \
    curl \
    sudo \
    unzip \
    sudo \
    # Following dependencies from https://gitlab.com/crafty-controller/crafty-4/-/blob/master/Dockerfile
    gcc \
    libcurl4 \
    python3 \
    python3-dev \
    python3-pip \
    python3-venv \
    libmariadb-dev \
    default-jre \
    openjdk-8-jre-headless \
    openjdk-11-jre-headless \
    openjdk-17-jre-headless \
    openjdk-21-jre-headless \
    tzdata \


# Install Crafty
RUN useradd -g root -M crafty && \
    mkdir -p /crafty && \
    chown -R crafty:root /crafty
#    curl -L https://craftycontrol.com/releases/latest/crafty4.zip -o /crafty/crafty4.zip && \
#    unzip /crafty/crafty4.zip -d /crafty && \
#    rm /crafty/crafty4.zip

# Switch to service user for installing crafty deps
USER crafty
WORKDIR /crafty
COPY --chown=crafty:root requirements.txt ./
RUN python3 -m venv ./.venv \
    && . .venv/bin/activate \
    && pip3 install --no-cache-dir --upgrade setuptools==75.6.0 pip==24.3.1 \
    && pip3 install --no-cache-dir -r requirements.txt \
    && deactivate
USER root

# Copy Source w/ perms & prepare default config from example
COPY --chown=crafty:root ./ ./
RUN mv ./app/config ./app/config_original \
    && mv ./app/config_original/default.json.example ./app/config_original/default.json
 #   && chmod +x ./docker_launcher.sh

# Expose Web Interface port & Server port range
EXPOSE 8000
EXPOSE 8443
EXPOSE 8100
EXPOSE 8124
EXPOSE 19132
EXPOSE 19134
EXPOSE 25500-25600

# Start Crafty through wrapper
ENTRYPOINT ["/crafty/run.sh"]
CMD ["-d", "-i"]

# Add meta labels
ARG BUILD_DATE
ARG BUILD_REF
ARG CRAFTY_VER
LABEL \
    maintainer="Zedifus <https://gitlab.com/zedifus>" \
    org.opencontainers.image.created=${BUILD_DATE} \
    org.opencontainers.image.revision=${BUILD_REF} \
    org.opencontainers.image.version=${CRAFTY_VER} \
    org.opencontainers.image.title="Crafty Controller" \
    org.opencontainers.image.description="A Game Server Control Panel / Launcher" \
    org.opencontainers.image.url="https://craftycontrol.com/" \
    org.opencontainers.image.documentation="https://docs.craftycontrol.com" \
    org.opencontainers.image.source="https://gitlab.com/crafty-controller/crafty-4" \
    org.opencontainers.image.vendor="Arcadia Technology, LLC." \
    org.opencontainers.image.licenses="GPL-3.0" \
    io.hass.version="VERSION" \
    io.hass.type="addon" \


#RUN chmod +x crafty.sh

#CMD [ "./crafty.sh" ]
