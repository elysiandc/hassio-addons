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

# Function to safely copy database files
safe_db_copy() {
    local src="$1"
    local dst="$2"
    local description="$3"

    if [ -d "$src" ]; then
        printf_info "Handling database files${description}"

        # Ensure destination exists
        mkdir -p "$dst"

        # Check if any database files are locked/in use
        local locked_files=$(lsof "$src"/* 2>/dev/null | awk '{print $9}' | sort -u)

        # Copy all files first
        cp -r "$src/"* "$dst/" 2>/dev/null || true

        # If there were locked files, handle them specially
        if [ -n "$locked_files" ]; then
            printf_warn "Some database files are in use, marking for sync on shutdown"
            echo "$locked_files" > "${DATA_DIR}/.db_sync_needed"
        fi
    fi
}

# Function to sync database files on shutdown
sync_db_files() {
    printf_info "Syncing database files to persistent storage..."

    # Ensure the database directory exists in persistent storage
    mkdir -p "${DATA_DIR}/config/db"

    # Small delay to allow any pending writes to complete
    sleep 2

    # Copy all database files to persistent storage
    if [ -d "${CRAFTY_HOME}/app/config/db" ]; then
        cp -r "${CRAFTY_HOME}/app/config/db/"* "${DATA_DIR}/config/db/" 2>/dev/null || true
    fi

    # Remove the sync needed flag
    rm -f "${DATA_DIR}/.db_sync_needed"
}

# Function to handle credentials
handle_credentials() {
    local config_dir="$1"

    if [ -n "$USERNAME" ] && [ -n "$PASSWORD" ]; then
        printf_info "Setting up login configuration with provided credentials..."

        # Backup existing default.json if it exists
        if [ -f "${config_dir}/default.json" ]; then
            cp "${config_dir}/default.json" "${DATA_DIR}/config_backup/default.json.$(date +%Y%m%d%H%M%S)"
        fi

        # Create new default.json
        cat > "${config_dir}/default.json" << EOL
{
    "username": "${USERNAME}",
    "password": "${PASSWORD}"
}
EOL
        # Also save to persistent storage
        cp "${config_dir}/default.json" "${DATA_DIR}/config/default.json"
    else
        printf_warn "No credentials provided, using existing credentials"
    fi
}

# Set up trap to handle shutdown
trap sync_db_files EXIT

# Initialize script
printf_info "=== Starting Crafty Controller Addon $(date '+%Y-%m-%d %H:%M:%S') ==="

# Get config values from options.json
printf_info "Loading configuration from Home Assistant..."
OPTIONS_FILE="/data/options.json"
USERNAME=$(jq -r '.username // "admin"' $OPTIONS_FILE)
PASSWORD=$(jq -r '.password // empty' $OPTIONS_FILE)
LOG_LEVEL=$(jq -r '.log_level // "info"' $OPTIONS_FILE)

# Convert Home Assistant log level to Python log level
case "${LOG_LEVEL}" in
    "trace")
        PYTHON_LOG_LEVEL="DEBUG"
        CRAFTY_ARGS="-d -i -v"
        ;;
    "debug")
        PYTHON_LOG_LEVEL="DEBUG"
        CRAFTY_ARGS="-d -i -v"
        ;;
    "info")
        PYTHON_LOG_LEVEL="INFO"
        CRAFTY_ARGS="-i"
        ;;
    "notice")
        PYTHON_LOG_LEVEL="INFO"
        CRAFTY_ARGS="-i"
        ;;
    "warning")
        PYTHON_LOG_LEVEL="WARNING"
        CRAFTY_ARGS=""
        ;;
    "error")
        PYTHON_LOG_LEVEL="ERROR"
        CRAFTY_ARGS=""
        ;;
    "fatal")
        PYTHON_LOG_LEVEL="CRITICAL"
        CRAFTY_ARGS=""
        ;;
    *)
        PYTHON_LOG_LEVEL="INFO"
        CRAFTY_ARGS="-i"
        ;;
esac

# Export log level for Python
export PYTHONUNBUFFERED=1
export LOG_LEVEL="${PYTHON_LOG_LEVEL}"

# Validate password complexity
if [ -n "$PASSWORD" ] && [ ${#PASSWORD} -lt 8 ]; then
    printf_warn "🚫 Password must be at least 8 characters"
    exit 1
fi

# Set default CRAFTY_HOME if not set (in official image, this is /crafty)
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
for SUBDIR in "servers" "backups" "import" "logs" "config" "config/db"; do
    if [ ! -d "${DATA_DIR}/${SUBDIR}" ]; then
        printf_info "Creating ${DATA_DIR}/${SUBDIR} directory"
        mkdir -p "${DATA_DIR}/${SUBDIR}"
    else
        printf_info "Directory ${DATA_DIR}/${SUBDIR} already exists"
    fi
done

# Handle config directories
printf_info "Setting up configuration..."

# Check if we have a config in persistent storage
if [ ! "$(ls -A ${DATA_DIR}/config 2>/dev/null)" ]; then
    printf_info "First run detected, initializing configuration from Crafty defaults..."

    # The official Crafty image stores the original config in app/config_original
    if [ -d "${CRAFTY_HOME}/app/config_original" ]; then
        printf_info "Copying default configuration from Crafty image..."
        # Copy the original config to both the container's config dir and persistent storage
        cp -r "${CRAFTY_HOME}/app/config_original/"* "${CRAFTY_HOME}/app/config/"
        cp -r "${CRAFTY_HOME}/app/config_original/"* "${DATA_DIR}/config/"

        # Handle initial credentials
        handle_credentials "${CRAFTY_HOME}/app/config"
    else
        printf_warn "No default configuration found in Crafty image at ${CRAFTY_HOME}/app/config_original"
        exit 1
    fi
else
    printf_info "Found existing configuration in persistent storage, restoring..."

    # First, handle any existing database files in the container
    if [ -d "${CRAFTY_HOME}/app/config/db" ]; then
        printf_info "Backing up current database files..."
        mkdir -p "${DATA_DIR}/config_backup/db_$(date +%Y%m%d%H%M%S)"
        cp -r "${CRAFTY_HOME}/app/config/db/"* "${DATA_DIR}/config_backup/db_$(date +%Y%m%d%H%M%S)/" 2>/dev/null || true
    fi

    # Backup the current config from the container (from the image)
    if [ -d "${CRAFTY_HOME}/app/config" ]; then
        printf_info "Backing up fresh image config..."
        mkdir -p "${DATA_DIR}/config_backup/image_$(date +%Y%m%d%H%M%S)"
        cp -r "${CRAFTY_HOME}/app/config/"* "${DATA_DIR}/config_backup/image_$(date +%Y%m%d%H%M%S)/" 2>/dev/null || true
    fi

    # Create fresh config directory structure
    mkdir -p "${CRAFTY_HOME}/app/config/db"

    # First copy everything except the db directory from persistent storage
    find "${DATA_DIR}/config" -mindepth 1 -maxdepth 1 ! -name "db" -exec cp -r {} "${CRAFTY_HOME}/app/config/" \;

    # Now handle database files specially
    safe_db_copy "${DATA_DIR}/config/db" "${CRAFTY_HOME}/app/config/db" ": restoring from persistent storage"

    # Update version.json from the image's config to ensure compatibility
    if [ -f "${CRAFTY_HOME}/app/config_original/version.json" ]; then
        printf_info "Updating version.json from image..."
        cp -f "${CRAFTY_HOME}/app/config_original/version.json" "${CRAFTY_HOME}/app/config/version.json"
        # Also update in persistent storage
        cp -f "${CRAFTY_HOME}/app/config_original/version.json" "${DATA_DIR}/config/version.json"
    fi

    # Handle credentials last
    handle_credentials "${CRAFTY_HOME}/app/config"
fi

# Create symbolic links for other persistent storage directories
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

# Setup SSL configuration
printf_info "Setting up SSL configuration..."
mkdir -p "${CRAFTY_HOME}/app/config/web/certs"
if [ -f "/ssl/fullchain.pem" ] && [ -f "/ssl/privkey.pem" ]; then
    printf_info "Installing SSL certificates from Home Assistant..."
    cp "/ssl/fullchain.pem" "${CRAFTY_HOME}/app/config/web/certs/commander.cert.pem"
    cp "/ssl/privkey.pem" "${CRAFTY_HOME}/app/config/web/certs/commander.key.pem"
    chmod 644 "${CRAFTY_HOME}/app/config/web/certs/commander.cert.pem"
    chmod 640 "${CRAFTY_HOME}/app/config/web/certs/commander.key.pem"
    chown crafty:root "${CRAFTY_HOME}/app/config/web/certs/commander.cert.pem" "${CRAFTY_HOME}/app/config/web/certs/commander.key.pem"
    # Also save to persistent storage
    mkdir -p "${DATA_DIR}/config/web/certs"
    cp -p "${CRAFTY_HOME}/app/config/web/certs/commander.cert.pem" "${DATA_DIR}/config/web/certs/"
    cp -p "${CRAFTY_HOME}/app/config/web/certs/commander.key.pem" "${DATA_DIR}/config/web/certs/"
else
    printf_warn "SSL certificates not found in /ssl, using Crafty's own self-signed certificates"
fi

# Ensure proper permissions on all directories
printf_info "Setting proper permissions on Crafty installation..."
cd "${CRAFTY_HOME}"
chown -R crafty:root "${CRAFTY_HOME}"
repair_permissions

# Configure Crafty server ports
export CRAFTY_WEBSERVER_PORT=8433
export CRAFTY_WEBSERVER_HOST="0.0.0.0"

# Debug output of directory contents
# printf_debug "Debug: Current directory=$(pwd)"
# printf_debug "Debug: CRAFTY_HOME=${CRAFTY_HOME}"
# printf_debug "Debug: Root Directory contents: ${CRAFTY_HOME}"
# ls -la ${CRAFTY_HOME}
# printf_debug "Debug: App Directory contents: ${CRAFTY_HOME}/app"
# ls -la ${CRAFTY_HOME}/app
# printf_debug "Debug: Config Directory contents: ${CRAFTY_HOME}/app/config"
# ls -la ${CRAFTY_HOME}/app/config
# printf_debug "Debug: DATA_DIR=${DATA_DIR}"
# printf_debug "Debug: Mapped share folder contents: ${DATA_DIR}"
# ls -la ${DATA_DIR}
# printf_debug "Debug: Imports folder contents: ${DATA_DIR}/import"
# ls -la ${DATA_DIR}/import
# printf_debug "Debug: Servers folder contents: ${DATA_DIR}/servers"
# ls -la ${DATA_DIR}/servers
# printf_debug "Debug: Backups folder contents: ${DATA_DIR}/backups"
# ls -la ${DATA_DIR}/backups
# printf_debug "Debug: Logs folder contents: ${DATA_DIR}/logs"
# ls -la ${DATA_DIR}/logs

# Launch Crafty
printf_info "🚀 Launching Crafty Controller with log level: ${LOG_LEVEL} (Python: ${PYTHON_LOG_LEVEL})"

# Using the official Crafty entrypoint pattern but with our parameters
exec sudo -u crafty bash -c "cd ${CRAFTY_HOME} && source ${CRAFTY_HOME}/.venv/bin/activate && exec python3 main.py ${CRAFTY_ARGS}"