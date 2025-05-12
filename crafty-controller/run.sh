#!/usr/bin/with-contenv bashio
# shellcheck shell=bashio

#source /usr/lib/hassio-addons/bashio.sh

bashio::log.info "===> CRAFTY-ADDON: run.sh started"
bashio::log.info "Running as: $(whoami)"

set -e pipefail

# Import functions and variables from Home Assistant
bashio::log.info "===> CRAFTY-ADDON: Starting Crafty Controller add-on script..."

# Set paths for clarity
CRAFTY_DIR="/crafty"
APP_DIR="${CRAFTY_DIR}/app"
CONFIG_DIR="${CRAFTY_DIR}/app/config"
SERVERS_DIR="${CRAFTY_DIR}/servers"
BACKUP_DIR="${CRAFTY_DIR}/backups"
IMPORT_DIR="${CRAFTY_DIR}/import"
LOGS_DIR="${CRAFTY_DIR}/logs"

# Ensure proper ownership of mapped volumes
# bashio::log.info "===> CRAFTY-ADDON: Setting up directory permissions..."
# for dir in "${CONFIG_DIR}" "${SERVERS_DIR}" "${BACKUP_DIR}" "${IMPORT_DIR}" "${LOGS_DIR}"; do
#     if mkdir -p "$dir"; then
#         bashio::log.info "===> Created directory: ${dir}"
#     else
#         bashio::log.error "!!! Failed to create directory: ${dir}"
#         continue
#     fi

#     if chown -R crafty:crafty "$dir"; then
#         bashio::log.info "===> Set ownership for: ${dir}"
#     else
#         bashio::log.error "!!! Failed to set ownership for: ${dir}"
#         continue
#     fi

#     bashio::log.info "===> CRAFTY-ADDON: ${dir} DONE..."
# done

# Check if first run (initialize if needed)
if [ ! -f "${CONFIG_DIR}/config.yml" ]; then
    bashio::log.info "===> CRAFTY-ADDON: First run detected, initializing Crafty configuration..."

    if mkdir -p "${CONFIG_DIR}"; then
        bashio::log.info "===> Created config directory: ${CONFIG_DIR}"
    else
        bashio::log.error "!!! Failed to create config directory: ${CONFIG_DIR}"
    fi

    # Create default config.yml
    if [ ! -f "${CONFIG_DIR}/config.yml" ]; then
        if [ -f "${CONFIG_DIR}/config.yml.default" ]; then
            cp "${CONFIG_DIR}/config.yml.default" "${CONFIG_DIR}/config.yml" && \
                bashio::log.info "===> Default config.yml created." || \
                bashio::log.warning "!!! Failed to copy default config.yml."
        else
            bashio::log.warning "!!! Missing default config.yml.default!"
        fi
    fi

    # Create default users.json
    if [ ! -f "${CONFIG_DIR}/users.json" ]; then
        if [ -f "${CONFIG_DIR}/users.json.default" ]; then
            cp "${CONFIG_DIR}/users.json.default" "${CONFIG_DIR}/users.json" && \
                bashio::log.info "===> Default users.json created." || \
                bashio::log.warning "!!! Failed to copy default users.json."
        else
            bashio::log.warning "!!! Missing default users.json.default!"
        fi
    fi

    # Create session key
    if [ ! -f "${CONFIG_DIR}/session_key.txt" ]; then
        if python -c "import secrets; print(secrets.token_hex(16))" > "${CONFIG_DIR}/session_key.txt"; then
            bashio::log.info "===> Session key created successfully."
        else
            bashio::log.error "!!! Failed to create session key."
        fi
    fi
fi

# Check for import files
if [ -d "${IMPORT_DIR}" ] && [ "$(ls -A ${IMPORT_DIR} 2>/dev/null)" ]; then
    bashio::log.info "===> CRAFTY-ADDON: Import directory not empty, checking for files to import..."
    # Handle server imports
    shopt -s nullglob
    for server_archive in ${IMPORT_DIR}/*.tar.gz ${IMPORT_DIR}/*.zip; do

        if [ -f "$server_archive" ]; then
            basename=$(basename "$server_archive")
            server_name="${basename%.*}"

            bashio::log.info "===> CRAFTY-ADDON: Importing server: $server_name"

            mkdir -p "${SERVERS_DIR}/${server_name}"

            if [[ "$server_archive" == *.tar.gz ]]; then
                tar -xzf "$server_archive" -C "${SERVERS_DIR}/${server_name}"
            elif [[ "$server_archive" == *.zip ]]; then
                unzip "$server_archive" -d "${SERVERS_DIR}/${server_name}"
            fi

            # Move imported file to backup dir to prevent reimporting
            mv "$server_archive" "${BACKUP_DIR}/"

            bashio::log.info "===> CRAFTY-ADDON: Server $server_name imported successfully"
        fi
    done
fi

# Run Crafty as the crafty user
bashio::log.info "===> CRAFTY-ADDON: Starting Crafty Controller Server..."
cd ${APP_DIR}

# Set execution options
EXEC_OPTS="--no_prompt --config_dir=${CONFIG_DIR} --servers_dir=${SERVERS_DIR} --logs_dir=${LOGS_DIR} --backups_dir=${BACKUP_DIR}"

# Print Python & pip versions for debugging
python_version=$(python3 --version)
pip_version=$(pip3 --version)
bashio::log.info "===> CRAFTY-ADDON: Python version: ${python_version}"
bashio::log.info "===> CRAFTY-ADDON: Pip version: ${pip_version}"

# Display Crafty version
#if [ -f "${APP_DIR}/VERSION" ]; then
#    version=$(cat ${APP_DIR}/VERSION)
#    bashio::log.info "===> CRAFTY-ADDON: Crafty Controller version: ${version}"
#else
#    bashio::log.info "===> CRAFTY-ADDON: Crafty Controller version: unknown (VERSION file not found)"
#fi

# Set up environment variables
export PYTHONPATH="${APP_DIR}:${PYTHONPATH:-}"
export PYTHONUNBUFFERED=1

# Activate virtual environment if it exists
if [ -f "${CRAFTY_DIR}/.venv/bin/activate" ]; then
    bashio::log.info "===> Activating virtual environment..."
    source "${CRAFTY_DIR}/.venv/bin/activate"
else
    bashio::log.warning "===> Virtual environment not found! Falling back to system Python (not recommended)."
fi

# Start Crafty Controller
bashio::log.info "===> CRAFTY-ADDON: Executing: python3 ${CRAFTY_DIR}/main.py -i -d"
cd ${CRAFTY_DIR} && exec python3 main.py -i -d

bashio::log.warning "===> Crafty didn't start. Sleeping forever for debug."
tail -f /dev/null