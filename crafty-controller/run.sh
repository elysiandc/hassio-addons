#!/usr/bin/env bashio

set -x

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

# Ensure CRAFTY_HOME is set
CRAFTY_HOME="${CRAFTY_HOME:-/crafty}"
CONFIG_DIR="${CRAFTY_HOME}/app/config"
PERSISTENT_CONFIG_DIR="/data/crafty/config"

# Ensure persistent config directories exist
mkdir -p "$PERSISTENT_CONFIG_DIR"

log_info "Preparing configuration"
log_info "CONFIG_DIR: $CONFIG_DIR"
log_info "PERSISTENT_CONFIG_DIR: $PERSISTENT_CONFIG_DIR"

# Backup original config files before setting up symlinks
# This function copies essential files if they don't exist in persistent storage
backup_and_init_config() {
    log_info "Backing up original configuration files"

    # Keep a backup copy of original config
    if [ ! -d "${CRAFTY_HOME}/app/config_backup" ]; then
        mkdir -p "${CRAFTY_HOME}/app/config_backup"
        cp -a "${CONFIG_DIR}"/* "${CRAFTY_HOME}/app/config_backup/"
        log_info "Original config backed up to ${CRAFTY_HOME}/app/config_backup"
    fi

    # Copy essential config files to persistent storage if they don't exist
    if [ ! -f "${PERSISTENT_CONFIG_DIR}/version.json" ] && [ -f "${CRAFTY_HOME}/app/config_backup/version.json" ]; then
        cp "${CRAFTY_HOME}/app/config_backup/version.json" "${PERSISTENT_CONFIG_DIR}/"
        log_info "Copied original version.json to persistent storage"
    fi

    # Ensure version.json exists with proper values
    if [ ! -f "${PERSISTENT_CONFIG_DIR}/version.json" ]; then
        jq -n '{
            "major": 4,
            "minor": 4,
            "sub": 7,
            "version": "4.4.7"
        }' > "${PERSISTENT_CONFIG_DIR}/version.json"
        log_info "Created new version.json in persistent storage"
    fi

    # Set proper permissions
    chmod 644 "${PERSISTENT_CONFIG_DIR}/version.json"
    chown -f crafty:root "${PERSISTENT_CONFIG_DIR}/version.json" 2>/dev/null || true

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

# Create symlinks for persistent storage
safe_symlink "${CRAFTY_HOME}/servers" "/data/crafty/servers"
safe_symlink "${CRAFTY_HOME}/import" "/data/crafty/import"
safe_symlink "${CRAFTY_HOME}/backups" "/data/crafty/backups"
safe_symlink "${CRAFTY_HOME}/app/config" "/data/crafty/config"

# Verify config files exist in persistent storage
if [ -f "${PERSISTENT_CONFIG_DIR}/version.json" ]; then
    log_info "version.json exists in persistent storage:"
    ls -l "${PERSISTENT_CONFIG_DIR}/version.json"
    cat "${PERSISTENT_CONFIG_DIR}/version.json"
else
    log_error "version.json is missing from persistent storage!"
    exit 1
fi

# Get credentials
get_config_value() {
    local key="$1"
    local default="${2:-}"

    # Try environment variable first (HOME ASSISTANT ADDON CONVENTION)
    env_var_name=$(echo "$key" | tr '[:lower:]' '[:upper:]' | tr '-' '_')
    env_value=$(printenv "CRAFTY_${env_var_name}" || true)

    if [ -n "$env_value" ]; then
        echo "$env_value"
        return 0
    fi

    # Fallback to default
    echo "$default"
}

# Get user credentials and settings
USERNAME=$(get_config_value 'username' 'admin')
PASSWORD=$(get_config_value 'password' 'craftyadmin')
LOG_LEVEL=$(get_config_value 'log_level' 'info')

log_info "Username and password: ${USERNAME}:${PASSWORD}"

# Create default.json with user credentials if it doesn't exist
if [ ! -f "${PERSISTENT_CONFIG_DIR}/default.json" ]; then
    log_info "Creating default.json with provided or default credentials"
    jq -n \
        --arg username "$USERNAME" \
        --arg password "$PASSWORD" \
        '{
            "login": {
                "username": $username,
                "password": $password
            }
        }' > "${PERSISTENT_CONFIG_DIR}/default.json"
    chmod 664 "${PERSISTENT_CONFIG_DIR}/default.json"
    chown -f crafty:root "${PERSISTENT_CONFIG_DIR}/default.json" 2>/dev/null || true
else
    log_info "Using existing default.json in persistent storage"
fi

log_info "Ensure crafty user has access to all directories"
chown -R crafty:root "${CRAFTY_HOME}" 2>/dev/null || true
chown -R crafty:root /data/crafty 2>/dev/null || true

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
LOG_LEVEL_NUM=${LOG_LEVELS[$LOG_LEVEL]:-30}

# Create or update logging.json with correct version field
if [ ! -f "${PERSISTENT_CONFIG_DIR}/logging.json" ]; then
    log_info "Creating logging configuration with version field"
    jq -n \
        --arg level "$LOG_LEVEL" \
        --arg level_num "$LOG_LEVEL_NUM" \
        '{
            "version": 1,
            "log_level": $level,
            "log_level_num": ($level_num | tonumber)
        }' > "${PERSISTENT_CONFIG_DIR}/logging.json"
    chmod 664 "${PERSISTENT_CONFIG_DIR}/logging.json"
    chown -f crafty:root "${PERSISTENT_CONFIG_DIR}/logging.json" 2>/dev/null || true
else
    # If logging.json exists but doesn't have the version field, add it
    if ! grep -q '"version"' "${PERSISTENT_CONFIG_DIR}/logging.json"; then
        log_info "Adding version field to existing logging.json"
        TMP_FILE=$(mktemp)
        jq '. + {"version": 1}' "${PERSISTENT_CONFIG_DIR}/logging.json" > "$TMP_FILE"
        mv "$TMP_FILE" "${PERSISTENT_CONFIG_DIR}/logging.json"
        chmod 664 "${PERSISTENT_CONFIG_DIR}/logging.json"
        chown -f crafty:root "${PERSISTENT_CONFIG_DIR}/logging.json" 2>/dev/null || true
    fi
fi

# Setup SSL if enabled
export USE_SSL="True"
export SSL_KEY="${PERSISTENT_CONFIG_DIR}/ingress.key"
export SSL_CERT="${PERSISTENT_CONFIG_DIR}/ingress.crt"

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
export CRAFTY_WEBSERVER_PORT=8443
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