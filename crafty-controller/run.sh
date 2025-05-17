#!/bin/bash
set -e

# Color output functions
printf_info() {
    printf "\033[36mWrapper | $(date '+%Y-%m-%d %H:%M:%S') | \033[32m%s\033[0m\n" "$1"
}

printf_warn() {
    printf "\033[36mWrapper | $(date '+%Y-%m-%d %H:%M:%S') | \033[33m%s\033[0m\n" "$1"
}

printf_step() {
    printf "\033[36mWrapper | $(date '+%Y-%m-%d %H:%M:%S') | \033[35m%s\033[0m\n" "$1"
}

printf_debug() {
    printf "\033[36mWrapper | $(date '+%Y-%m-%d %H:%M:%S') | \033[34m%s\033[0m\n" "$1"
}

repair_permissions() {
    printf_step "📋 (1/3) Ensuring root group ownership..."
    find . ! -group root -print0 | xargs -0 -r chgrp root
    printf_step "📋 (2/3) Ensuring group read-write is present on files..."
    find . ! -perm g+rw -print0 | xargs -0 -r chmod g+rw
    printf_step "📋 (3/3) Ensuring sticky bit is present on directories..."
    find . -type d ! -perm g+s -print0 | xargs -0 -r chmod g+s
}

# Initialize script
printf_info "=== Starting Crafty Controller Addon $(date '+%Y-%m-%d %H:%M:%S') ==="

# Get config values from options.json
printf_info "Loading configuration from Home Assistant..."
OPTIONS_FILE="/data/options.json"
USERNAME=$(jq -r '.username // "admin"' $OPTIONS_FILE)
PASSWORD=$(jq -r '.password // empty' $OPTIONS_FILE)
LOG_LEVEL=$(jq -r '.log_level // "info"' $OPTIONS_FILE)

# Validate password complexity
if [ -n "$PASSWORD" ] && [ ${#PASSWORD} -lt 8 ]; then
    printf_warn "🚫 Password must be at least 8 characters"
    exit 1
fi

# Set default CRAFTY_HOME if not set
: "${CRAFTY_HOME:=/crafty}"
# Set location for persistent data
: "${DATA_DIR:=/share/crafty}"

# Create data directories if they don't exist
if [ ! -d "${DATA_DIR}" ]; then
    printf_info "Creating base data directory: ${DATA_DIR}"
    mkdir -p "${DATA_DIR}"
else
    printf_info "Data directory ${DATA_DIR} already exists"
fi

# Create subdirectories only if they don't already exist
for SUBDIR in "servers" "backups" "import" "logs"; do
    if [ ! -d "${DATA_DIR}/${SUBDIR}" ]; then
        printf_info "Creating ${DATA_DIR}/${SUBDIR} directory"
        mkdir -p "${DATA_DIR}/${SUBDIR}"
    else
        printf_info "Directory ${DATA_DIR}/${SUBDIR} already exists"
    fi
done

# Clean previous installation if exists
printf_info "Cleaning previous Crafty installation if it exists..."
rm -rf ${CRAFTY_HOME}/* ${CRAFTY_HOME}/.* 2>/dev/null || true

# Clone into a temporary directory
printf_info "Cloning latest Crafty Controller from repository..."
TEMP_DIR=$(mktemp -d)
git clone --depth=1 https://gitlab.com/crafty-controller/crafty-4.git "$TEMP_DIR"

# Remove application files only (not touching persistent storage in /share/crafty)
printf_info "Cleaning application directory..."
rm -rf ${CRAFTY_HOME}/* ${CRAFTY_HOME}/.* 2>/dev/null || true

# Selectively copy only necessary files
printf_info "Installing required Crafty files (excluding unnecessary files)..."
mkdir -p ${CRAFTY_HOME}

# Copy only the essential files
cp "$TEMP_DIR/main.py" "${CRAFTY_HOME}/"
cp "$TEMP_DIR/requirements.txt" "${CRAFTY_HOME}/"
cp -r "$TEMP_DIR/app" "${CRAFTY_HOME}/"
cp "$TEMP_DIR/LICENSE" "${CRAFTY_HOME}/" 2>/dev/null || true

# Clean up temp directory
rm -rf "$TEMP_DIR"

# Create symbolic links for persistent storage
printf_info "Setting up data directory links..."
for DIR in "servers" "backups" "import" "logs"; do
    # Remove directory if it exists in CRAFTY_HOME
    if [ -d "${CRAFTY_HOME}/${DIR}" ]; then
        rm -rf "${CRAFTY_HOME}/${DIR}"
    fi

    # Create symbolic link to persistent storage
    ln -sf "${DATA_DIR}/${DIR}" "${CRAFTY_HOME}/${DIR}"
    printf_info "Created link: ${CRAFTY_HOME}/${DIR} -> ${DATA_DIR}/${DIR}"
done

# Setup Python virtual environment
printf_info "Setting up Python virtual environment..."
python3 -m venv "${CRAFTY_HOME}/venv"
"${CRAFTY_HOME}/venv/bin/pip" install --upgrade pip wheel setuptools
printf_info "Installing requirements..."
"${CRAFTY_HOME}/venv/bin/pip" install -r "${CRAFTY_HOME}/requirements.txt" tzdata

# Set up default.json with credentials
printf_info "Setting up login configuration..."
cat > "${CRAFTY_HOME}/app/config/default.json" << EOL
{
    "username": "${USERNAME}",
    "password": "${PASSWORD}"
}
EOL

# Setup SSL configuration
printf_info "Setting up SSL configuration..."
if [ -f "/ssl/fullchain.pem" ] && [ -f "/ssl/privkey.pem" ]; then
    printf_info "Installing SSL certificates from Home Assistant..."
    cp "/ssl/fullchain.pem" "${CRAFTY_HOME}/app/config/web/certs/commander.cert.pem"
    cp "/ssl/privkey.pem" "${CRAFTY_HOME}/app/config/web/certs/commander.key.pem"
    chmod 644 "${CRAFTY_HOME}/app/config/web/certs/commander.cert.pem"
    chmod 640 "${CRAFTY_HOME}/app/config/web/certs/commander.key.pem"
    chown crafty:root "${CRAFTY_HOME}/app/config/web/certs/commander.cert.pem" "${CRAFTY_HOME}/app/config/web/certs/commander.key.pem"
else
    printf_warn "SSL certificates not found in /ssl, using Crafty's own self-signed certificates"
fi

# Ensure proper permissions on all directories
printf_info "Setting proper permissions on Crafty installation..."
cd ${CRAFTY_HOME}
chown -R crafty:root ${CRAFTY_HOME}
repair_permissions

# Debug output of directory contents
printf_debug "Debug: Current directory=$(pwd)"
printf_debug "Debug: CRAFTY_HOME=${CRAFTY_HOME}"
printf_debug "Debug: Root Directory contents: ${CRAFTY_HOME}"
ls -la ${CRAFTY_HOME}
printf_debug "Debug: App Directory contents: ${CRAFTY_HOME}/app"
ls -la ${CRAFTY_HOME}/app
printf_debug "Debug: Config Directory contents: ${CRAFTY_HOME}/app/config"
ls -la ${CRAFTY_HOME}/app/config
printf_debug "Debug: DATA_DIR=${DATA_DIR}"
printf_debug "Debug: Mapped share folder contents: ${DATA_DIR}"
ls -la ${DATA_DIR}
printf_debug "Debug: Imports folder contents: ${DATA_DIR}/import"
ls -la ${DATA_DIR}/import
printf_debug "Debug: Servers folder contents: ${DATA_DIR}/servers"
ls -la ${DATA_DIR}/servers
printf_debug "Debug: Backups folder contents: ${DATA_DIR}/backups"
ls -la ${DATA_DIR}/backups
printf_debug "Debug: Logs folder contents: ${DATA_DIR}/logs"
ls -la ${DATA_DIR}/logs

# Launch Crafty
printf_info "🚀 Launching Crafty Controller..."

# Launch using Crafty's standard pattern
exec su-exec crafty bash -c "cd ${CRAFTY_HOME} && source ${CRAFTY_HOME}/venv/bin/activate && exec python3 main.py -d -i"