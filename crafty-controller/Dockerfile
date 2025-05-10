# This is largely based on https://gitlab.com/crafty-controller/crafty-4/-/blob/master/Dockerfile

ARG BUILD_FROM
FROM $BUILD_FROM

ENV CRAFTY_DIR=/crafty
ENV CRAFTY_USER=crafty
ENV CRAFTY_RELEASE_URL="https://api.github.com/repos/crafty-controller/crafty/releases/latest"

# Install dependencies
RUN apt-get update && apt-get -y --no-install-recommends install \
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
    && apt-get autoremove \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Create user and working directory
RUN id -u $CRAFTY_USER >/dev/null 2>&1 || useradd -g root -M $CRAFTY_USER && \
    mkdir -p $CRAFTY_DIR && \
    chown -R $CRAFTY_USER:root $CRAFTY_DIR

# Download and extract latest Crafty release into /crafty
RUN curl -s $CRAFTY_RELEASE_URL \
    | grep "browser_download_url.*Crafty.*\.zip" \
    | cut -d '"' -f 4 \
    | wget -i - -O /tmp/crafty.zip && \
    && unzip /tmp/crafty.zip -d $CRAFTY_DIR \
    && rm /tmp/crafty.zip \
    && chown -R $CRAFTY_USER:root $CRAFTY_DIR \
    && ls -lah / \
    && ls -lah /crafty

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
RUN ls -lah ./app \
    && -d ./app/config \
    && mv ./app/config ./app/config_original || echo "Directory ./app/config not found, skipping move." \
    && -f ./app/config_original/default.json.example \
    && mv ./app/config_original/default.json.example ./app/config_original/default.json || echo "default.json.example not found, skipping rename." \
    && chmod +x ./run.sh

# Expose Web Interface port & Server port range
EXPOSE 8000
EXPOSE 8443
EXPOSE 8100
EXPOSE 19132
EXPOSE 19134
EXPOSE 25500-25600

# Start Crafty through wrapper
ENTRYPOINT ["./run.sh"]
CMD ["-d", "-i"]

#CMD ["./run.sh -d -i"]

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
    io.hass.type="addon"


#RUN chmod +x ./run.sh

#CMD [ "./run.sh" ]
