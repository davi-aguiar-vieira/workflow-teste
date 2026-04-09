#!/usr/bin/env bash
# =============================================================
# Apache Ranger Admin – container entrypoint
# 1. Waits for the Ranger PostgreSQL instance to be ready
# 2. Injects runtime environment variables into install.properties
# 3. Runs the one-time setup (DB schema creation, admin user)
# 4. Starts the Ranger admin server and tails its log
# =============================================================
set -euo pipefail

RANGER_HOME="${RANGER_HOME:-/opt/ranger-admin}"

echo "========================================================"
echo " Apache Ranger Admin – starting up"
echo " RANGER_HOME : ${RANGER_HOME}"
echo " Ranger DB   : ${RANGER_DB_HOST:-ranger-postgres}:${RANGER_DB_PORT:-5432}"
echo "========================================================"

# ---- 1. Wait for PostgreSQL -------------------------------------
DB_HOST="${RANGER_DB_HOST:-ranger-postgres}"
DB_PORT="${RANGER_DB_PORT:-5432}"
DB_USER="${RANGER_DB_USER:-ranger_user}"

echo "Waiting for PostgreSQL at ${DB_HOST}:${DB_PORT} ..."
until pg_isready -h "${DB_HOST}" -p "${DB_PORT}" -U "${DB_USER}" >/dev/null 2>&1; do
    echo "  PostgreSQL not ready – retrying in 5 s …"
    sleep 5
done
echo "PostgreSQL is ready."

# ---- 2. Inject env vars into install.properties -----------------
INSTALL_PROPS="${RANGER_HOME}/install.properties"

update_prop() {
    local key="$1" val="$2"
    if grep -q "^${key}=" "${INSTALL_PROPS}" 2>/dev/null; then
        sed -i "s|^${key}=.*|${key}=${val}|g" "${INSTALL_PROPS}"
    else
        echo "${key}=${val}" >> "${INSTALL_PROPS}"
    fi
}

update_prop "db_host"            "${RANGER_DB_HOST:-ranger-postgres}"
update_prop "db_port"            "${RANGER_DB_PORT:-5432}"
update_prop "db_name"            "${RANGER_DB_NAME:-ranger}"
update_prop "db_root_user"       "${RANGER_DB_USER:-ranger_user}"
update_prop "db_root_password"   "${RANGER_DB_PASS:-ranger_pass}"
update_prop "db_user"            "${RANGER_DB_USER:-ranger_user}"
update_prop "db_password"        "${RANGER_DB_PASS:-ranger_pass}"
update_prop "rangerAdmin_password" \
    "${RANGER_ADMIN_PASSWORD:-rangeradmin1}"
update_prop "rangerTagsync_password" \
    "${RANGER_ADMIN_PASSWORD:-rangeradmin1}"
update_prop "rangerUsersync_password" \
    "${RANGER_ADMIN_PASSWORD:-rangeradmin1}"

echo "install.properties updated."

# ---- 3. One-time setup ------------------------------------------
SETUP_FLAG="${RANGER_HOME}/.setup_done"

if [ ! -f "${SETUP_FLAG}" ]; then
    echo "Running Ranger setup (first boot) …"
    cd "${RANGER_HOME}"
    python3 setup.py setup
    touch "${SETUP_FLAG}"
    echo "Ranger setup finished."
else
    echo "Ranger already set up – skipping."
fi

# ---- 4. Start Ranger admin server --------------------------------
echo "Starting Ranger Admin …"
"${RANGER_HOME}/ews/ranger-admin" start

# Keep the container alive and stream the log
LOG_FILE=$(ls "${RANGER_HOME}/ews/logs/ranger-admin"-*.log 2>/dev/null | head -1 || true)
if [ -n "${LOG_FILE}" ]; then
    echo "Tailing ${LOG_FILE}"
    tail -F "${LOG_FILE}"
else
    echo "No log file found – sleeping indefinitely."
    sleep infinity
fi
