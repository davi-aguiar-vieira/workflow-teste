#!/usr/bin/env bash
# =============================================================
# create-policies.sh
# Creates a Trino service definition in Ranger and then adds
# column-masking policies for PII fields (email, SSN, credit_card).
#
# Usage:
#   ./create-ranger-policies.sh [ranger_url] [admin_user] [admin_pass]
#
# Defaults:
#   ranger_url  = http://ranger-admin:6080
#   admin_user  = admin
#   admin_pass  = rangeradmin1
# =============================================================
set -euo pipefail

RANGER_URL="${1:-http://ranger-admin:6080}"
RANGER_USER="${2:-admin}"
RANGER_PASS="${3:-rangeradmin1}"

BASE="${RANGER_URL}/service/public/v2/api"

# Helper: authenticated curl call
rc() {
    curl -su "${RANGER_USER}:${RANGER_PASS}" \
         -H "Content-Type: application/json" \
         -H "Accept: application/json" \
         "$@"
}

# ---- Wait for Ranger admin to respond ---------------------------
echo "Waiting for Ranger Admin at ${RANGER_URL} …"
until rc "${BASE}/servicedef" -o /dev/null; do
    echo "  Ranger not ready – retrying in 10 s …"
    sleep 10
done
echo "Ranger Admin is reachable."

# ---- 1. Register Trino service definition -----------------------
echo ""
echo "Creating 'trino' service definition …"
SERVICE_DEF_ID=$(rc "${BASE}/servicedef/name/trino" 2>/dev/null \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('id',''))" 2>/dev/null || true)

if [ -z "${SERVICE_DEF_ID}" ]; then
    rc -X POST "${BASE}/servicedef" -d '{
      "name": "trino",
      "displayName": "Trino",
      "implClass": "org.apache.ranger.services.trino.RangerServiceTrino",
      "label": "Trino",
      "resources": [
        {"name":"catalog","type":"string","level":1,"parent":"","mandatory":true,
         "lookupSupported":true,"matcher":"org.apache.ranger.plugin.resourcematcher.RangerDefaultResourceMatcher",
         "matcherOptions":{"wildCard":"true","ignoreCase":"true"},"label":"Trino Catalog"},
        {"name":"schema","type":"string","level":2,"parent":"catalog","mandatory":true,
         "lookupSupported":true,"matcher":"org.apache.ranger.plugin.resourcematcher.RangerDefaultResourceMatcher",
         "matcherOptions":{"wildCard":"true","ignoreCase":"true"},"label":"Trino Schema"},
        {"name":"table","type":"string","level":3,"parent":"schema","mandatory":true,
         "lookupSupported":true,"matcher":"org.apache.ranger.plugin.resourcematcher.RangerDefaultResourceMatcher",
         "matcherOptions":{"wildCard":"true","ignoreCase":"true"},"label":"Trino Table"},
        {"name":"column","type":"string","level":4,"parent":"table","mandatory":true,
         "lookupSupported":true,"matcher":"org.apache.ranger.plugin.resourcematcher.RangerDefaultResourceMatcher",
         "matcherOptions":{"wildCard":"true","ignoreCase":"true"},"label":"Trino Column"}
      ],
      "accessTypes": [
        {"name":"select","label":"Select"},
        {"name":"insert","label":"Insert"},
        {"name":"update","label":"Update"},
        {"name":"delete","label":"Delete"},
        {"name":"use","label":"Use"}
      ],
      "dataMaskDef": {
        "maskTypes": [
          {"itemId":1,"name":"MASK",         "label":"Mask",               "description":"Replace with X/0"},
          {"itemId":2,"name":"MASK_SHOW_LAST_4","label":"Show last 4",     "description":"Show only last 4 chars"},
          {"itemId":3,"name":"MASK_SHOW_FIRST_4","label":"Show first 4",   "description":"Show only first 4 chars"},
          {"itemId":4,"name":"MASK_HASH",    "label":"Hash",               "description":"Hash value (SHA-256)"},
          {"itemId":5,"name":"MASK_NULL",    "label":"Nullify",            "description":"Replace with NULL"},
          {"itemId":6,"name":"MASK_NONE",    "label":"None (show plain)",  "description":"No masking"},
          {"itemId":7,"name":"CUSTOM",       "label":"Custom",             "description":"Custom masking expression"}
        ],
        "resources": [
          {"name":"catalog"},{"name":"schema"},{"name":"table"},{"name":"column"}
        ],
        "accessTypes": [{"name":"select"}]
      },
      "rowFilterDef": {
        "resources": [
          {"name":"catalog"},{"name":"schema"},{"name":"table"}
        ],
        "accessTypes": [{"name":"select"}]
      }
    }' | python3 -m json.tool
    echo "Service definition created."
else
    echo "Service definition already exists (id=${SERVICE_DEF_ID})."
fi

# ---- 2. Register Trino service instance -------------------------
echo ""
echo "Creating 'trino_warehouse' service instance …"
SVC_EXISTS=$(rc "${BASE}/service/name/trino_warehouse" 2>/dev/null \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('id',''))" 2>/dev/null || true)

if [ -z "${SVC_EXISTS}" ]; then
    rc -X POST "${BASE}/service" -d '{
      "name": "trino_warehouse",
      "type": "trino",
      "description": "Trino service for warehouse data",
      "isEnabled": true,
      "configs": {
        "username": "trino",
        "jdbc.driverClassName": "io.trino.jdbc.TrinoDriver",
        "jdbc.url": "jdbc:trino://trino:8080"
      }
    }' | python3 -m json.tool
    echo "Service instance created."
else
    echo "Service instance already exists."
fi

# ---- helper: create masking policy ------------------------------
create_mask_policy() {
    local policy_name="$1"
    local catalog="$2"
    local schema="$3"
    local table="$4"
    local column="$5"
    local mask_type="$6"   # e.g. MASK_SHOW_LAST_4 | MASK_HASH | MASK_NULL

    echo ""
    echo "Creating masking policy '${policy_name}' (${mask_type}) on ${table}.${column} …"
    rc -X POST "${BASE}/policy" -d "{
      \"service\": \"trino_warehouse\",
      \"name\": \"${policy_name}\",
      \"policyType\": 1,
      \"description\": \"Auto-generated column masking policy\",
      \"isEnabled\": true,
      \"isAuditEnabled\": false,
      \"resources\": {
        \"catalog\": {\"values\":[\"${catalog}\"],\"isExcludes\":false,\"isRecursive\":false},
        \"schema\":  {\"values\":[\"${schema}\"],  \"isExcludes\":false,\"isRecursive\":false},
        \"table\":   {\"values\":[\"${table}\"],   \"isExcludes\":false,\"isRecursive\":false},
        \"column\":  {\"values\":[\"${column}\"],  \"isExcludes\":false,\"isRecursive\":false}
      },
      \"dataMaskPolicyItems\": [
        {
          \"accesses\": [{\"type\":\"select\",\"isAllowed\":true}],
          \"users\": [\"public\"],
          \"groups\": [\"public\"],
          \"dataMaskInfo\": {\"dataMaskType\": \"${mask_type}\"}
        }
      ]
    }" | python3 -m json.tool
    echo "Policy '${policy_name}' created."
}

# ---- 3. Column masking policies ---------------------------------
# email fields → hash
create_mask_policy "mask-employees-email"  "postgresql" "employees" "employees" "email"       "MASK_HASH"
create_mask_policy "mask-customers-email"  "postgresql" "customers" "customers" "email"       "MASK_HASH"

# SSN → show last 4 digits only
create_mask_policy "mask-employees-ssn"    "postgresql" "employees" "employees" "ssn"         "MASK_SHOW_LAST_4"

# Credit card → show last 4 digits only
create_mask_policy "mask-customers-cc"     "postgresql" "customers" "customers" "credit_card" "MASK_SHOW_LAST_4"

# Phone numbers → full mask
create_mask_policy "mask-employees-phone"  "postgresql" "employees" "employees" "phone"       "MASK"
create_mask_policy "mask-customers-phone"  "postgresql" "customers" "customers" "phone"       "MASK"

echo ""
echo "========================================================"
echo " All Ranger masking policies created successfully."
echo " Open http://localhost:6080 (admin / rangeradmin1)"
echo " to review them in the Ranger UI."
echo "========================================================"
