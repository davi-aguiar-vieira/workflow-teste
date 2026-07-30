#!/usr/bin/env bash
# =============================================================
# test-integration.sh
# End-to-end integration tests for the PostgreSQL + Trino + Ranger stack.
#
# Prerequisites:
#   - docker compose up (from docker/ directory) must have been called
#   - trino CLI (trino) must be on PATH  *or*  Docker is used to exec
#
# Usage (from the docker/ directory):
#   ./scripts/test-integration.sh
# =============================================================
set -euo pipefail

TRINO_URL="${TRINO_URL:-http://localhost:8080}"
RANGER_URL="${RANGER_URL:-http://localhost:6080}"

PASS=0
FAIL=0
SKIP=0

ok()   { echo "  [PASS] $*"; PASS=$((PASS+1)); }
fail() { echo "  [FAIL] $*"; FAIL=$((FAIL+1)); }
skip() { echo "  [SKIP] $*"; SKIP=$((SKIP+1)); }

section() { echo ""; echo "=== $* ==="; }

# ---- Trino REST helper -----------------------------------------
# Runs a query via the Trino REST API and returns the result rows.
# Trino expects the raw SQL as the POST body (plain text).
trino_query() {
    local query="$1"
    local user="${2:-test_user}"

    # Submit the query (raw SQL as POST body – Trino expects text/plain)
    local response
    response=$(curl -sf -X POST \
        -H "X-Trino-User: ${user}" \
        -H "Content-Type: text/plain" \
        --data-binary "${query}" \
        "${TRINO_URL}/v1/statement" 2>/dev/null || true)

    if [ -z "${response}" ]; then
        echo ""
        return 1
    fi

    local next_uri
    next_uri=$(echo "${response}" | python3 -c \
        "import sys,json; d=json.load(sys.stdin); print(d.get('nextUri',''))" 2>/dev/null || true)

    # Poll until the query finishes
    local max_polls=60
    local polls=0
    local all_data=""
    while [ -n "${next_uri}" ] && [ "${polls}" -lt "${max_polls}" ]; do
        sleep 1
        response=$(curl -sf "${next_uri}" 2>/dev/null || true)
        [ -z "${response}" ] && break

        local data
        data=$(echo "${response}" | python3 -c \
            "import sys,json; d=json.load(sys.stdin); rows=d.get('data',[]); [print(','.join(str(c) for c in r)) for r in rows]" 2>/dev/null || true)
        [ -n "${data}" ] && all_data="${all_data}${data}"$'\n'

        next_uri=$(echo "${response}" | python3 -c \
            "import sys,json; d=json.load(sys.stdin); print(d.get('nextUri',''))" 2>/dev/null || true)
        polls=$((polls+1))
    done
    echo "${all_data}"
}

# ---- Ranger REST helper ----------------------------------------
ranger_get() {
    curl -su "admin:rangeradmin1" \
         -H "Accept: application/json" \
         "${RANGER_URL}/service/public/v2/api/$*" 2>/dev/null || true
}

# ================================================================
section "1. Trino health check"
# ================================================================

if curl -sf "${TRINO_URL}/v1/info" | python3 -c \
        "import sys,json; d=json.load(sys.stdin); assert d.get('starting')==False" 2>/dev/null; then
    ok "Trino is up and not in 'starting' state"
else
    fail "Trino health check failed (${TRINO_URL}/v1/info)"
fi

# ================================================================
section "2. Trino → PostgreSQL catalog connectivity"
# ================================================================

CATALOGS=$(trino_query "SHOW CATALOGS")
if echo "${CATALOGS}" | grep -q "postgresql"; then
    ok "Catalog 'postgresql' is visible in Trino"
else
    fail "Catalog 'postgresql' not found. Got: ${CATALOGS}"
fi

# ================================================================
section "3. Schema and table visibility"
# ================================================================

SCHEMAS=$(trino_query "SHOW SCHEMAS FROM postgresql")
if echo "${SCHEMAS}" | grep -qE "employees|customers"; then
    ok "Schemas 'employees' / 'customers' are visible"
else
    fail "Expected schemas not found. Got: ${SCHEMAS}"
fi

TABLES_EMP=$(trino_query "SHOW TABLES FROM postgresql.employees")
if echo "${TABLES_EMP}" | grep -q "employees"; then
    ok "Table 'employees.employees' exists"
else
    fail "Table 'employees.employees' not found. Got: ${TABLES_EMP}"
fi

TABLES_CUST=$(trino_query "SHOW TABLES FROM postgresql.customers")
if echo "${TABLES_CUST}" | grep -q "customers"; then
    ok "Table 'customers.customers' exists"
else
    fail "Table 'customers.customers' not found. Got: ${TABLES_CUST}"
fi

# ================================================================
section "4. Query data via Trino"
# ================================================================

# Count employees
COUNT=$(trino_query "SELECT COUNT(*) FROM postgresql.employees.employees")
if echo "${COUNT}" | grep -q "10"; then
    ok "Employees table has 10 rows"
else
    fail "Expected 10 employees, got: '${COUNT}'"
fi

# Count customers
COUNT=$(trino_query "SELECT COUNT(*) FROM postgresql.customers.customers")
if echo "${COUNT}" | grep -q "10"; then
    ok "Customers table has 10 rows"
else
    fail "Expected 10 customers, got: '${COUNT}'"
fi

# Count transactions
COUNT=$(trino_query "SELECT COUNT(*) FROM postgresql.customers.transactions")
if [ -n "${COUNT}" ]; then
    ok "Transactions table is queryable (${COUNT} rows)"
else
    fail "Could not query transactions table"
fi

# ================================================================
section "5. Aggregate queries"
# ================================================================

AVG=$(trino_query "SELECT ROUND(AVG(salary), 2) FROM postgresql.employees.employees")
if [ -n "${AVG}" ]; then
    ok "AVG(salary) = ${AVG}"
else
    fail "AVG salary query failed"
fi

TOP_DEPT=$(trino_query \
    "SELECT department, COUNT(*) AS cnt FROM postgresql.employees.employees GROUP BY department ORDER BY cnt DESC LIMIT 1")
if [ -n "${TOP_DEPT}" ]; then
    ok "Department aggregation works: ${TOP_DEPT}"
else
    fail "Department aggregation failed"
fi

TOTAL_SALES=$(trino_query \
    "SELECT SUM(amount) FROM postgresql.customers.transactions WHERE status='completed'")
if [ -n "${TOTAL_SALES}" ]; then
    ok "Total completed sales = ${TOTAL_SALES}"
else
    fail "Sales aggregation failed"
fi

# ================================================================
section "6. PII fields present (unmasked – no Ranger plugin active)"
# ================================================================

EMAIL=$(trino_query \
    "SELECT email FROM postgresql.employees.employees LIMIT 1")
if echo "${EMAIL}" | grep -q "@"; then
    ok "Email field is readable: ${EMAIL}"
else
    fail "Email field unexpected result: ${EMAIL}"
fi

SSN=$(trino_query \
    "SELECT ssn FROM postgresql.employees.employees LIMIT 1")
if echo "${SSN}" | grep -qE "[0-9]{3}-[0-9]{2}-[0-9]{4}"; then
    ok "SSN field is readable: ${SSN}"
else
    fail "SSN field unexpected result: ${SSN}"
fi

CC=$(trino_query \
    "SELECT credit_card FROM postgresql.customers.customers LIMIT 1")
if echo "${CC}" | grep -qE "[0-9-]+"; then
    ok "Credit card field is readable: ${CC}"
else
    fail "Credit card field unexpected result: ${CC}"
fi

# ================================================================
section "7. JOIN query (employees × transactions via customers)"
# ================================================================

JOIN_RESULT=$(trino_query \
    "SELECT c.full_name, t.amount, t.status
     FROM postgresql.customers.customers c
     JOIN postgresql.customers.transactions t ON c.id = t.customer_id
     WHERE t.status = 'completed'
     ORDER BY t.amount DESC
     LIMIT 3")
if [ -n "${JOIN_RESULT}" ]; then
    ok "JOIN query returned results"
else
    fail "JOIN query failed"
fi

# ================================================================
section "8. Ranger Admin health check"
# ================================================================

RANGER_RESPONSE=$(ranger_get "servicedef" 2>/dev/null || true)
if echo "${RANGER_RESPONSE}" | python3 -c \
        "import sys,json; d=json.load(sys.stdin); assert isinstance(d,list)" 2>/dev/null; then
    SVC_COUNT=$(echo "${RANGER_RESPONSE}" | python3 -c \
        "import sys,json; d=json.load(sys.stdin); print(len(d))")
    ok "Ranger Admin is up – ${SVC_COUNT} service definition(s) registered"
else
    skip "Ranger Admin not yet available at ${RANGER_URL} (start it with: docker compose up ranger-admin)"
fi

# ================================================================
section "9. Ranger masking policies"
# ================================================================

POLICIES=$(ranger_get "policy?serviceType=trino" 2>/dev/null || true)
if echo "${POLICIES}" | python3 -c \
        "import sys,json; d=json.load(sys.stdin); assert isinstance(d,list) and len(d)>0" 2>/dev/null; then
    POLICY_COUNT=$(echo "${POLICIES}" | python3 -c \
        "import sys,json; d=json.load(sys.stdin); print(len(d))")
    ok "Found ${POLICY_COUNT} Ranger masking policy/policies for Trino"
else
    skip "No Ranger masking policies found (run docker/ranger/create-policies.sh after Ranger starts)"
fi

# ================================================================
echo ""
echo "========================================================"
echo " Test Results"
echo "   PASS : ${PASS}"
echo "   FAIL : ${FAIL}"
echo "   SKIP : ${SKIP}"
echo "========================================================"

if [ "${FAIL}" -gt 0 ]; then
    exit 1
fi
exit 0
