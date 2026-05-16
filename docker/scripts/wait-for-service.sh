#!/usr/bin/env bash
# =============================================================
# wait-for-service.sh
# Polls a URL until it returns HTTP 2xx or the timeout expires.
#
# Usage:
#   ./wait-for-service.sh <url> [timeout_seconds]
# =============================================================
set -euo pipefail

URL="${1:?Usage: wait-for-service.sh <url> [timeout_seconds]}"
TIMEOUT="${2:-120}"
INTERVAL=5

echo "Waiting for ${URL} (timeout: ${TIMEOUT}s) …"
ELAPSED=0
until curl -sf --output /dev/null "${URL}"; do
    if [ "${ELAPSED}" -ge "${TIMEOUT}" ]; then
        echo "TIMEOUT: ${URL} did not become available within ${TIMEOUT}s."
        exit 1
    fi
    echo "  Not ready yet – retrying in ${INTERVAL}s … (${ELAPSED}s elapsed)"
    sleep "${INTERVAL}"
    ELAPSED=$((ELAPSED + INTERVAL))
done
echo "${URL} is ready (${ELAPSED}s elapsed)."
