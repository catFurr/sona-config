#!/bin/sh
set -e

# Ensure the vault directory exists within the container
VAULT_DIR="/opt/keycloak/vault"
mkdir -p "${VAULT_DIR}"

# Populate vault files from environment variables
# This assumes your .env file has KC_REGISTRATION_API_URL and KC_WEBHOOK_SECRET defined

REALM_NAME="${KC_REALM_NAME:-jitsi}"

# https://docs.redhat.com/en/documentation/red_hat_build_of_keycloak/26.0/html/server_administration_guide/vault-administration
REGISTRATION_API_URL_FILE="${VAULT_DIR}/${REALM_NAME}_KC__REGISTRATION__API__URL"
WEBHOOK_SECRET_FILE="${VAULT_DIR}/${REALM_NAME}_KC__WEBHOOK__SECRET"

# Check if environment variables are set
if [ -z "${KC_REGISTRATION_API_URL}" ]; then
  echo "Warning: KC_REGISTRATION_API_URL is not set. The vault file will be empty or have its placeholder." >&2
else
  echo "Populating ${REGISTRATION_API_URL_FILE} with KC_REGISTRATION_API_URL"
  echo -n "${KC_REGISTRATION_API_URL}" > "${REGISTRATION_API_URL_FILE}"
fi

if [ -z "${KC_WEBHOOK_SECRET}" ]; then
  echo "Warning: KC_WEBHOOK_SECRET is not set. The vault file will be empty or have its placeholder." >&2
else
  echo "Populating ${WEBHOOK_SECRET_FILE} with KC_WEBHOOK_SECRET"
  echo -n "${KC_WEBHOOK_SECRET}" > "${WEBHOOK_SECRET_FILE}"
fi

# Process realm export file to replace client secret placeholder
TEMPLATE_REALM_FILE="/opt/keycloak/realm-template.json"
FINAL_REALM_FILE="/opt/keycloak/data/import/realm-export.json"

# Ensure the import directory exists
mkdir -p "/opt/keycloak/data/import"

if [ -f "${TEMPLATE_REALM_FILE}" ]; then
  echo "Processing realm template file and copying to import directory..."
  
  # Copy the template file to the import directory
  cp "${TEMPLATE_REALM_FILE}" "${FINAL_REALM_FILE}"
  
  # Replace the KC_CLIENT_SECRET placeholder with the actual value
  if [ -n "${KC_CLIENT_SECRET}" ]; then
    echo "Replacing \${KC_CLIENT_SECRET} with actual client secret value"
    sed -i "s/\${KC_CLIENT_SECRET}/${KC_CLIENT_SECRET}/g" "${FINAL_REALM_FILE}"
  else
    echo "Warning: KC_CLIENT_SECRET is not set. The placeholder will remain in the realm file." >&2
  fi
  
  echo "Realm file processed and ready for import at ${FINAL_REALM_FILE}"
else
  echo "Warning: Realm template file not found at ${TEMPLATE_REALM_FILE}" >&2
fi

# Original Keycloak command (from Docker image or previous compose command)
# The Dockerfile for Keycloak sets ENTRYPOINT ["/opt/keycloak/bin/kc.sh"].
# The original command in compose was: ["start", "--optimized", "--import-realm", "--spi-events-listener-ext-event-webhook-store-webhook-events=true"]
# We pass these as arguments to kc.sh

exec /opt/keycloak/bin/kc.sh "$@" 