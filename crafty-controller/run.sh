#!/usr/bin/env bashio

# Color output functions from Crafty
printf_info() {
    printf "\033[36mWrapper | \033[32m%s\033[0m\n" "$1"
}

printf_warn() {
    printf "\033[36mWrapper | \033[33m%s\033[0m\n" "$1"
}

printf_step() {
    printf "\033[36mWrapper | \033[35m%s\033[0m\n" "$1"
}

# Crafty's permission repair function
repair_permissions() {
    printf_step "📋 (1/3) Ensuring root group ownership..."
    find . ! -group root -print0 | xargs -0 -r chgrp root

    printf_step "📋 (2/3) Ensuring group read-write is present on files..."
    find . ! -perm g+rw -print0 | xargs -0 -r chmod g+rw

    printf_step "📋 (3/3) Ensuring sticky bit is present on directories..."
    find . -type d ! -perm g+s -print0 | xargs -0 -r chmod g+s
}

# Home Assistant specific configuration
CRAFTY_HOME="${CRAFTY_HOME:-/crafty}"
SHARE_DIR="/share/crafty"
BACKUP_DIR="/share/crafty/backups"
CONFIG_DIR="/data/crafty/config"

# Ensure directories exist
mkdir -p "${SHARE_DIR}" "${BACKUP_DIR}" "${CONFIG_DIR}"

# Get Home Assistant config
USERNAME=$(bashio::config 'username')
PASSWORD=$(bashio::config 'password')
LOG_LEVEL=$(bashio::config 'log_level')

# Validate password complexity
if [ ${#PASSWORD} -lt 12 ] || ! echo "$PASSWORD" | grep -q "[A-Za-z]" || ! echo "$PASSWORD" | grep -q "[0-9]"; then
    printf_warn "🚫 Password must be at least 12 characters and contain letters and numbers"
    exit 1
fi

# Check if config exists and initialize if needed
if [ ! "$(ls -A --ignore=.gitkeep ${CRAFTY_HOME}/app/config)" ]; then
    printf_warn "🏗️ Config not found, pulling defaults..."
    mkdir -p ${CRAFTY_HOME}/app/config/
    cp -r ${CRAFTY_HOME}/app/config_original/* ${CRAFTY_HOME}/app/config/

    # Create/update default.json with credentials
    jq -n \
        --arg username "$USERNAME" \
        --arg password "$PASSWORD" \
        '{
            "username": $username,
            "password": $password
        }' > "${CONFIG_DIR}/default.json"

    chmod 600 "${CONFIG_DIR}/default.json"
    chown crafty:root "${CONFIG_DIR}/default.json"
else
    # Keep version file up to date with image
    cp -f ${CRAFTY_HOME}/app/config_original/version.json ${CRAFTY_HOME}/app/config/version.json
fi

# Check and fix import directory permissions
if [ "$(find ${SHARE_DIR}/import -type f ! -name '.gitkeep' 2>/dev/null)" ]; then
    printf_warn "📋 Files present in import directory, checking/fixing permissions..."
    printf_warn "⏳ Please be patient for larger servers..."
    cd ${SHARE_DIR} && repair_permissions
    printf_info "✅ Permissions Fixed! (This will happen every boot until /import is empty!)"
fi

# Setup environment for Crafty
export USE_SSL="True"
export SSL_KEY="${SHARE_DIR}/ingress.key"
export SSL_CERT="${SHARE_DIR}/ingress.crt"
export CRAFTY_WEBSERVER_PORT=8433
export CRAFTY_WEBSERVER_HOST="0.0.0.0"

# Launch Crafty
printf_info "🚀 Launching Crafty Controller..."
cd ${CRAFTY_HOME}
exec sudo -u crafty bash -c "source ${CRAFTY_HOME}/venv/bin/activate && exec python3.9 main.py -d -i"