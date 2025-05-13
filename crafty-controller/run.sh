#!/usr/bin/env bashio

set -e

# Logging function
log_info() {
    echo "[$(date '+%H:%M:%S')] INFO: $*"
}

log_warning() {
    echo "[$(date '+%H:%M:%S')] WARNING: $*"
}

log_error() {
    echo "[$(date '+%H:%M:%S')] ERROR: $*" >&2
}

# Use standard Home Assistant paths with crafty parent folder
CRAFTY_HOME="${CRAFTY_HOME:-/crafty}"
SHARE_DIR="/share/crafty"              # Persistent data
BACKUP_DIR="/share/backup/crafty"      # Backups
CONFIG_DIR="/data/crafty/config"       # Runtime config

# Ensure parent directories exist
mkdir -p "${SHARE_DIR}"
mkdir -p "${BACKUP_DIR}"
mkdir -p "${CONFIG_DIR}"

log_info "Preparing configuration"
log_info "CONFIG_DIR: $CONFIG_DIR"
log_info "PERSISTENT_CONFIG_DIR: $SHARE_DIR"

# Backup original config files before setting up symlinks
# This function copies essential files if they don't exist in persistent storage
backup_and_init_config() {
    log_info "Backing up original configuration files"

    # Keep a backup copy of original config
    if [ ! -d "${CRAFTY_HOME}/app/config_backup" ]; then
        mkdir -p "${CRAFTY_HOME}/app/config_backup"
        cp -a "${CRAFTY_HOME}/app/config/"* "${CRAFTY_HOME}/app/config_backup/"
        log_info "Original config backed up to ${CRAFTY_HOME}/app/config_backup"
    fi

    # Copy essential config files to persistent storage if they don't exist
    if [ ! -f "${SHARE_DIR}/version.json" ] && [ -f "${CRAFTY_HOME}/app/config_backup/version.json" ]; then
        cp "${CRAFTY_HOME}/app/config_backup/version.json" "${SHARE_DIR}/"
        log_info "Copied original version.json to persistent storage"
    fi

    # Ensure version.json exists with proper values
    if [ ! -f "${SHARE_DIR}/version.json" ]; then
        jq -n '{
            "major": 4,
            "minor": 4,
            "sub": 7,
            "version": "4.4.7"
        }' > "${SHARE_DIR}/version.json"
        log_info "Created new version.json in persistent storage"
    fi

    # Set proper permissions
    chmod 644 "${SHARE_DIR}/version.json"
    chown -f crafty:root "${SHARE_DIR}/version.json" 2>/dev/null || true

    log_info "Configuration initialization complete"
}

# Function to create symlinks in a safe way
safe_symlink() {
    local source="$1"
    local target="$2"

    log_info "Creating symlink: $source -> $target"

    # Ensure target directory exists
    mkdir -p "$(dirname "$target")"

    # If source exists and is a directory (not a symlink)
    if [ -d "$source" ] && [ ! -L "$source" ]; then
        # Create a temp directory for the content
        mkdir -p "${target}_temp"
        log_info "Copying content from $source to ${target}_temp"
        cp -a "$source/." "${target}_temp/"
        # Remove original directory
        rm -rf "$source"
    fi

    # Create symlink
    ln -sf "$target" "$source"

    # If we had temp contents, move them to the target
    if [ -d "${target}_temp" ]; then
        # Ensure target directory exists
        mkdir -p "$target"
        log_info "Moving temp content to $target"
        cp -a "${target}_temp/." "$target/"
        rm -rf "${target}_temp"
    fi
}

# Backup the original config files first
backup_and_init_config

# Create directory structure
mkdir -p "${SHARE_DIR}/servers"
mkdir -p "${SHARE_DIR}/import"
mkdir -p "${SHARE_DIR}/config"

# Setup symlinks with proper parent folders
safe_symlink "${CRAFTY_HOME}/servers" "${SHARE_DIR}/servers"
safe_symlink "${CRAFTY_HOME}/import" "${SHARE_DIR}/import"
safe_symlink "${CRAFTY_HOME}/backups" "${BACKUP_DIR}"
safe_symlink "${CRAFTY_HOME}/app/config" "${CONFIG_DIR}"

# Ensure proper permissions
chown -R crafty:root "${SHARE_DIR}"
chown -R crafty:root "${BACKUP_DIR}"
chown -R crafty:root "${CONFIG_DIR}"
chmod -R 755 "${SHARE_DIR}"
chmod -R 755 "${BACKUP_DIR}"
chmod -R 755 "${CONFIG_DIR}"

# Verify config files exist in persistent storage
if [ -f "${SHARE_DIR}/version.json" ]; then
    log_info "version.json exists in persistent storage:"
    ls -l "${SHARE_DIR}/version.json"
    cat "${SHARE_DIR}/version.json"
else
    log_error "version.json is missing from persistent storage!"
    exit 1
fi

# Get credentials from Home Assistant options
USERNAME=$(bashio::config 'username')
PASSWORD=$(bashio::config 'password')

# Validate password complexity
if [ ${#PASSWORD} -lt 12 ]; then
    log_error "Password must be at least 12 characters long"
    exit 1
fi

if ! echo "$PASSWORD" | grep -q "[A-Za-z]"; then
    log_error "Password must contain at least one letter"
    exit 1
fi

if ! echo "$PASSWORD" | grep -q "[0-9]"; then
    log_error "Password must contain at least one number"
    exit 1
fi

# Create or update default.json with credentials
if [ ! -f "${CONFIG_DIR}/default.json" ]; then
    log_info "Creating default.json with provided credentials"
    jq -n \
        --arg username "$USERNAME" \
        --arg password "$PASSWORD" \
        '{
            "username": $username,
            "password": $password
        }' > "${CONFIG_DIR}/default.json"
else
    # Update existing default.json while preserving other settings
    log_info "Updating existing default.json with new credentials"
    TEMP_FILE=$(mktemp)
    jq --arg username "$USERNAME" \
       --arg password "$PASSWORD" \
       '.username = $username | .password = $password' \
       "${CONFIG_DIR}/default.json" > "$TEMP_FILE" && mv "$TEMP_FILE" "${CONFIG_DIR}/default.json"
fi

# Set proper permissions on credentials file
chmod 600 "${CONFIG_DIR}/default.json"
chown crafty:root "${CONFIG_DIR}/default.json"

# Verify default.json was created/updated successfully
if [ ! -f "${CONFIG_DIR}/default.json" ]; then
    log_error "Failed to create/update default.json"
    exit 1
fi

log_info "Ensure crafty user has access to all directories"
chown -R crafty:root "${CRAFTY_HOME}" 2>/dev/null || true
chown -R crafty:root "${SHARE_DIR}" 2>/dev/null || true
chown -R crafty:root "${BACKUP_DIR}" 2>/dev/null || true
chown -R crafty:root "${CONFIG_DIR}" 2>/dev/null || true

# Log level configuration
declare -A LOG_LEVELS=(
    ["trace"]=10
    ["debug"]=20
    ["info"]=30
    ["notice"]=40
    ["warning"]=50
    ["error"]=60
    ["fatal"]=70
)
LOG_LEVEL=$(bashio::config 'log_level')
LOG_LEVEL_NUM=${LOG_LEVELS[$LOG_LEVEL]:-30}

# Create or update logging.json with correct version field
if [ ! -f "${SHARE_DIR}/logging.json" ]; then
    log_info "Creating logging configuration with version field"
    jq -n \
        --arg level "$LOG_LEVEL" \
        --arg level_num "$LOG_LEVEL_NUM" \
        '{
            "version": 1,
            "log_level": $level,
            "log_level_num": ($level_num | tonumber)
        }' > "${SHARE_DIR}/logging.json"
    chmod 664 "${SHARE_DIR}/logging.json"
    chown -f crafty:root "${SHARE_DIR}/logging.json" 2>/dev/null || true
else
    # If logging.json exists but doesn't have the version field, add it
    if ! grep -q '"version"' "${SHARE_DIR}/logging.json"; then
        log_info "Adding version field to existing logging.json"
        TMP_FILE=$(mktemp)
        jq '. + {"version": 1}' "${SHARE_DIR}/logging.json" > "$TMP_FILE"
        mv "$TMP_FILE" "${SHARE_DIR}/logging.json"
        chmod 664 "${SHARE_DIR}/logging.json"
        chown -f crafty:root "${SHARE_DIR}/logging.json" 2>/dev/null || true
    fi
fi

# Setup SSL if enabled
export USE_SSL="True"
export SSL_KEY="${SHARE_DIR}/ingress.key"
export SSL_CERT="${SHARE_DIR}/ingress.crt"

# Generate self-signed certificate if it doesn't exist
if [ ! -f "$SSL_KEY" ] || [ ! -f "$SSL_CERT" ]; then
    log_info "Generating self-signed certificate for Crafty Ingress"
    openssl req -x509 -nodes -days 3650 \
        -newkey rsa:2048 \
        -keyout "$SSL_KEY" \
        -out "$SSL_CERT" \
        -subj "/CN=CraftyController"

    # Set appropriate permissions
    chmod 640 "$SSL_KEY"
    chmod 644 "$SSL_CERT"
    chown crafty:root "$SSL_KEY" "$SSL_CERT"
fi

# Handle Ingress
export CRAFTY_WEBSERVER_PORT=8433
export CRAFTY_WEBSERVER_HOST="0.0.0.0"

# Setup basic arguments
args="-d -i"

# Announce successful setup
log_info "Crafty Controller is starting with args: $args"
log_info "Login configured with username: $USERNAME"
log_info "Log level set to: $LOG_LEVEL"

# Run using our Python virtual environment without sudo
log_info "Starting Crafty Controller..."
exec sudo -u crafty bash -c "cd ${CRAFTY_HOME} && source ${CRAFTY_HOME}/venv/bin/activate && exec python3.9 main.py $args"