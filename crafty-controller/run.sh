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
    local target_dir="${1:-.}"
    printf_step "📋 Optimizing permission repairs..."

    # Use parallel for large directories
    if command -v parallel >/dev/null 2>&1; then
        printf_debug "Using parallel for permission repairs"

        # Process directories first (handles sticky bit and ownership)
        find "$target_dir" -type d -print0 | parallel -0 --will-cite -n 100 'chmod g+s {} 2>/dev/null; chgrp root {} 2>/dev/null'

        # Process files (handles group read-write and ownership)
        find "$target_dir" -type f -print0 | parallel -0 --will-cite -n 100 'chmod g+rw {} 2>/dev/null; chgrp root {} 2>/dev/null'
    else
        printf_debug "Parallel not available, using sequential processing"

        # Combine tests to reduce process spawning
        # For directories: check group ownership and sticky bit in one pass
        find "$target_dir" -type d \( ! -group root -o ! -perm -g+s \) -exec sh -c '
            for d; do
                if [ "$(stat -c %G "$d")" != "root" ]; then
                    chgrp root "$d"
                fi
                if [ ! -g "$d" ] || [ ! -k "$d" ]; then
                    chmod g+s "$d"
                fi
            done
        ' sh {} +

        # For files: check group ownership and read-write permissions in one pass
        find "$target_dir" -type f \( ! -group root -o ! -perm -g+rw \) -exec sh -c '
            for f; do
                if [ "$(stat -c %G "$f")" != "root" ]; then
                    chgrp root "$f"
                fi
                if [ ! -g "$f" ] || [ ! -w "$f" ]; then
                    chmod g+rw "$f"
                fi
            done
        ' sh {} +
    fi
}

# Function to quickly check if permissions need repair
needs_permission_repair() {
    local target_dir="${1:-.}"
    local sample_size=100
    local issues=0

    # Quick sample check of files and directories
    printf_debug "Sampling permissions to determine if repair is needed..."

    # Check a sample of directories
    issues=$(find "$target_dir" -type d -print0 | head -z -n "$sample_size" | xargs -0 -I{} sh -c '
        if [ "$(stat -c %G "{}")" != "root" ] || [ ! -g "{}" ] || [ ! -k "{}" ]; then
            echo 1
            exit 0
        fi' 2>/dev/null | wc -l)

    # If directory issues found, repair needed
    if [ "$issues" -gt 0 ]; then
        return 0
    fi

    # Check a sample of files
    issues=$(find "$target_dir" -type f -print0 | head -z -n "$sample_size" | xargs -0 -I{} sh -c '
        if [ "$(stat -c %G "{}")" != "root" ] || [ ! -g "{}" ] || [ ! -w "{}" ]; then
            echo 1
            exit 0
        fi' 2>/dev/null | wc -l)

    # Return 0 (true) if issues found, 1 (false) if no issues
    [ "$issues" -gt 0 ]
}

# Function to safely copy database files
safe_db_copy() {
    local src="$1"
    local dst="$2"
    local description="$3"

    if [ -d "$src" ]; then
        printf_info "=== Starting database copy operation${description} ==="
        printf_info "Source: ${src}"
        printf_info "Destination: ${dst}"

        # List and log source directory contents with sizes
        printf_info "Source directory contents before copy:"
        ls -lah "${src}" || printf_warn "Could not list source directory"

        # Ensure destination exists with proper permissions
        printf_debug "Setting up destination directory..."
        mkdir -p "$dst"
        chmod 2775 "$dst"  # Sets SGID bit and group write permission
        chown crafty:root "$dst"
        printf_info "Destination directory prepared with permissions $(stat -c '%a' "$dst")"

        # First ensure SQLite is in a consistent state
        if [ -f "${src}/crafty.sqlite" ]; then
            printf_info "Database found, checking WAL mode and size..."
            printf_debug "Main DB size: $(stat -c '%s' "${src}/crafty.sqlite") bytes"

            # First copy WAL and SHM files if they exist, BEFORE checkpointing
            for file in crafty.sqlite-wal crafty.sqlite-shm; do
                if [ -f "${src}/${file}" ]; then
                    printf_debug "${file} exists, size: $(stat -c '%s' "${src}/${file}") bytes"
                    printf_info "Copying ${file} before checkpoint..."

                    if ! cp --preserve=all "${src}/${file}" "${dst}/${file}.new"; then
                        printf_warn "Failed to copy ${file} from ${src}/${file} to ${dst}/${file}.new"
                        rm -f "${dst}/${file}.new"
                        continue
                    fi

                    # Verify the temporary file
                    if [ -f "${dst}/${file}.new" ]; then
                        printf_debug "Temporary file created, size: $(stat -c '%s' "${dst}/${file}.new") bytes"

                        # Compare source and destination sizes
                        SRC_SIZE=$(stat -c '%s' "${src}/${file}")
                        DST_SIZE=$(stat -c '%s' "${dst}/${file}.new")
                        if [ "$SRC_SIZE" != "$DST_SIZE" ]; then
                            printf_warn "Size mismatch for ${file}: source=${SRC_SIZE}, dest=${DST_SIZE}"
                            rm -f "${dst}/${file}.new"
                            continue
                        fi

                        # Atomic move
                        if mv "${dst}/${file}.new" "${dst}/${file}"; then
                            printf_debug "Atomic move successful for ${file}"
                            # Set permissions
                            chown crafty:root "${dst}/${file}"
                            chmod 664 "${dst}/${file}"
                            printf_debug "Set permissions on ${file}: $(stat -c '%a' "${dst}/${file}")"
                        else
                            printf_warn "Atomic move failed for ${file}"
                            rm -f "${dst}/${file}.new"
                        fi
                    else
                        printf_warn "Temporary file creation failed for ${file}"
                    fi
                else
                    printf_debug "Source file not found: ${src}/${file}"
                fi
            done

            # Now do the checkpoint after WAL/SHM files are copied
            printf_info "Forcing SQLite checkpoint..."
            if command -v sqlite3 >/dev/null 2>&1; then
                CHECKPOINT_RESULT=$(sqlite3 "${src}/crafty.sqlite" "PRAGMA wal_checkpoint(FULL);" 2>&1)
                printf_info "Checkpoint result: ${CHECKPOINT_RESULT}"
                sync
                printf_debug "Sync completed after checkpoint"
            else
                printf_warn "sqlite3 command not found, skipping checkpoint"
            fi

            # Now copy the main database file
            printf_info "Copying main database file..."
            if ! cp --preserve=all "${src}/crafty.sqlite" "${dst}/crafty.sqlite.new"; then
                printf_warn "Failed to copy crafty.sqlite from ${src}/crafty.sqlite to ${dst}/crafty.sqlite.new"
                rm -f "${dst}/crafty.sqlite.new"
                return 1
            fi

            # Verify the temporary file
            if [ -f "${dst}/crafty.sqlite.new" ]; then
                printf_debug "Temporary file created, size: $(stat -c '%s' "${dst}/crafty.sqlite.new") bytes"

                # Compare source and destination sizes
                SRC_SIZE=$(stat -c '%s' "${src}/crafty.sqlite")
                DST_SIZE=$(stat -c '%s' "${dst}/crafty.sqlite.new")
                if [ "$SRC_SIZE" != "$DST_SIZE" ]; then
                    printf_warn "Size mismatch for crafty.sqlite: source=${SRC_SIZE}, dest=${DST_SIZE}"
                    rm -f "${dst}/crafty.sqlite.new"
                    return 1
                fi

                # Atomic move
                if mv "${dst}/crafty.sqlite.new" "${dst}/crafty.sqlite"; then
                    printf_debug "Atomic move successful for crafty.sqlite"
                    # Set permissions
                    chown crafty:root "${dst}/crafty.sqlite"
                    chmod 664 "${dst}/crafty.sqlite"
                    printf_debug "Set permissions on crafty.sqlite: $(stat -c '%a' "${dst}/crafty.sqlite")"
                else
                    printf_warn "Atomic move failed for crafty.sqlite"
                    rm -f "${dst}/crafty.sqlite.new"
                    return 1
                fi
            else
                printf_warn "Temporary file creation failed for crafty.sqlite"
                return 1
            fi

            # Verify the final copy
            printf_info "=== Final verification of copied files ==="
            printf_info "Destination directory contents:"
            ls -lah "${dst}" || printf_warn "Could not list destination directory"

            # Count files before listing them (prevents race conditions)
            DST_COUNT=$(find "${dst}" -maxdepth 1 -name "crafty.sqlite*" -type f | wc -l)

            # After checkpoint, we expect only the main DB file in source
            if [ "$DST_COUNT" -eq 3 ] && [ -f "${dst}/crafty.sqlite" ] && \
               [ -f "${dst}/crafty.sqlite-wal" ] && [ -f "${dst}/crafty.sqlite-shm" ]; then
                printf_info "Verification successful: All database files present in destination"
                printf_debug "Destination files:"
                find "${dst}" -maxdepth 1 -name "crafty.sqlite*" -type f -ls
            else
                printf_warn "Unexpected file count in destination (expected 3, got ${DST_COUNT})"
                printf_info "Source files (expect only main DB after checkpoint):"
                find "${src}" -maxdepth 1 -name "crafty.sqlite*" -type f -ls
                printf_info "Destination files (should have all 3 files):"
                find "${dst}" -maxdepth 1 -name "crafty.sqlite*" -type f -ls
                # Don't return error if we at least have the main DB
                [ ! -f "${dst}/crafty.sqlite" ] && return 1
            fi

            # Force a final sync
            sync
            printf_info "Final sync completed"
        else
            printf_warn "Main database file not found in source directory"
            return 1
        fi
    else
        printf_warn "Source directory does not exist: ${src}"
        return 1
    fi

    printf_info "=== Database copy operation completed ==="
    return 0
}

# Function to sync database files on shutdown
sync_db_files() {
    printf_info "Syncing database files to persistent storage..."

    # Ensure the database directory exists in persistent storage
    mkdir -p "${DATA_DIR}/config/db"

    # Small delay to allow any pending writes to complete
    sleep 2

    # Force SQLite to checkpoint and sync before copying
    if [ -f "${CRAFTY_HOME}/app/config/db/crafty.sqlite" ] && command -v sqlite3 >/dev/null 2>&1; then
        printf_debug "Forcing final SQLite checkpoint before sync..."
        sqlite3 "${CRAFTY_HOME}/app/config/db/crafty.sqlite" "PRAGMA wal_checkpoint(FULL);" || printf_warn "Failed to checkpoint database during sync"
        sync
    fi

    # Use safe_db_copy for the final sync
    safe_db_copy "${CRAFTY_HOME}/app/config/db" "${DATA_DIR}/config/db" " during shutdown"
}

# Function to periodically sync database files
periodic_db_sync() {
    while true; do
        sleep 300  # Sync every 5 minutes
        printf_debug "Performing periodic database sync..."

        # Only sync if the database exists and has been modified
        if [ -f "${CRAFTY_HOME}/app/config/db/crafty.sqlite" ]; then
            CURRENT_DB_SIZE=$(stat -c %s "${CRAFTY_HOME}/app/config/db/crafty.sqlite" 2>/dev/null || echo "0")
            CURRENT_WAL_SIZE=$(stat -c %s "${CRAFTY_HOME}/app/config/db/crafty.sqlite-wal" 2>/dev/null || echo "0")

            if [ -f "/tmp/last_db_size" ]; then
                LAST_DB_SIZE=$(cat "/tmp/last_db_size")
                LAST_WAL_SIZE=$(cat "/tmp/last_wal_size")

                if [ "$CURRENT_DB_SIZE" != "$LAST_DB_SIZE" ] || [ "$CURRENT_WAL_SIZE" != "$LAST_WAL_SIZE" ]; then
                    printf_debug "Database changes detected, syncing to persistent storage..."
                    safe_db_copy "${CRAFTY_HOME}/app/config/db" "${DATA_DIR}/config/db" " during periodic sync"
                fi
            fi

            # Store current sizes for next comparison
            echo "$CURRENT_DB_SIZE" > "/tmp/last_db_size"
            echo "$CURRENT_WAL_SIZE" > "/tmp/last_wal_size"
        fi
    done
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

# Function to handle shutdown gracefully
shutdown_crafty() {
    local pid=$1
    printf_info "Initiating graceful shutdown..."

    # First try graceful shutdown through stdin if process exists
    if [ -n "$pid" ] && kill -0 $pid 2>/dev/null; then
        printf_debug "Sending stop command to Crafty..."
        echo "stop" > /tmp/crafty_cmd
        # Give it time to process the stop command
        sleep 5
    fi

    # Sync database files
    sync_db_files

    # Kill any remaining processes
    if [ -n "$pid" ] && kill -0 $pid 2>/dev/null; then
        printf_warn "Crafty still running, sending SIGTERM..."
        kill -TERM $pid 2>/dev/null

        # Wait up to 30 seconds for process to end
        for i in {1..30}; do
            if ! kill -0 $pid 2>/dev/null; then
                break
            fi
            sleep 1
        done

        # If still running, force kill
        if kill -0 $pid 2>/dev/null; then
            printf_warn "Force stopping Crafty..."
            kill -9 $pid 2>/dev/null
        fi
    fi

    # Kill background tasks
    kill $PERIODIC_SYNC_PID 2>/dev/null

    printf_info "Shutdown complete"
    exit 0
}

# Set up trap to handle shutdown
trap 'sync_db_files; kill $PERIODIC_SYNC_PID 2>/dev/null' EXIT

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
        CRAFTY_ARGS="-d -i"
        ;;
    "notice")
        PYTHON_LOG_LEVEL="INFO"
        CRAFTY_ARGS="-d -i"
        ;;
    "warning")
        PYTHON_LOG_LEVEL="WARNING"
        CRAFTY_ARGS="-d"
        ;;
    "error")
        PYTHON_LOG_LEVEL="ERROR"
        CRAFTY_ARGS="-d"
        ;;
    "fatal")
        PYTHON_LOG_LEVEL="CRITICAL"
        CRAFTY_ARGS="-d"
        ;;
    *)
        PYTHON_LOG_LEVEL="INFO"
        CRAFTY_ARGS="-d -i"
        ;;
esac

# Export log level for Python
export PYTHONUNBUFFERED=1
export LOG_LEVEL="${PYTHON_LOG_LEVEL}"

# SQLite optimizations
export SQLITE_OPEN_FLAGS="SQLITE_OPEN_READWRITE|SQLITE_OPEN_CREATE|SQLITE_OPEN_WAL|SQLITE_OPEN_FULLMUTEX"
export SQLITE_TIMEOUT=60000
export SQLITE_BUSY_TIMEOUT=60000

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
    printf_debug "Copying non-database files from persistent storage..."
    if ! find "${DATA_DIR}/config" -mindepth 1 -maxdepth 1 ! -name "db" -exec cp -rv {} "${CRAFTY_HOME}/app/config/" \;; then
        printf_warn "Some files failed to copy from persistent storage"
    fi

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
printf_info "Checking permissions on Crafty installation..."
cd "${CRAFTY_HOME}"
chown -R crafty:root "${CRAFTY_HOME}"

if needs_permission_repair; then
    printf_info "Permission issues detected, starting repair..."
    repair_permissions
else
    printf_info "Permissions appear correct, skipping repair..."
fi

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

# Start periodic database sync in the background
periodic_db_sync &
PERIODIC_SYNC_PID=$!

# Launch Crafty
printf_info "🚀 Launching Crafty Controller with log level: ${LOG_LEVEL} (Python: ${PYTHON_LOG_LEVEL})"

# Using the official Crafty entrypoint pattern but with our parameters
exec sudo -u crafty bash -c "cd ${CRAFTY_HOME} && source ${CRAFTY_HOME}/.venv/bin/activate && exec python3 main.py ${CRAFTY_ARGS}"