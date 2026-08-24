#!/usr/bin/env bash

set -euo pipefail

config_file="${1:-deployment.env}"

if [[ ! -f "$config_file" ]]; then
  printf 'Configuration file not found: %s\n' "$config_file" >&2
  printf 'Copy deployment.env.example to deployment.env and enter your Azure values.\n' >&2
  exit 1
fi

set -a
# The developer owns this local configuration file; it is never committed.
# shellcheck disable=SC1090
source "$config_file"
set +a

required_variables=(
  AZURE_ENV_NAME
  AZURE_TENANT_ID
  AZURE_SUBSCRIPTION_ID
  AZURE_LOCATION
  BUDGET_CONTACT_EMAIL
)

for variable_name in "${required_variables[@]}"; do
  if [[ -z "${!variable_name:-}" ]]; then
    printf 'Missing required value: %s\n' "$variable_name" >&2
    exit 1
  fi
done

uuid_pattern='^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
placeholder_guid='00000000-0000-0000-0000-000000000000'
for variable_name in AZURE_TENANT_ID AZURE_SUBSCRIPTION_ID; do
  if [[ ! "${!variable_name}" =~ $uuid_pattern ]]; then
    printf '%s must be a GUID.\n' "$variable_name" >&2
    exit 1
  fi

  if [[ "${!variable_name}" == "$placeholder_guid" ]]; then
    printf 'Replace the placeholder value for %s.\n' "$variable_name" >&2
    exit 1
  fi
done

AZURE_PRINCIPAL_ID="${AZURE_PRINCIPAL_ID:-}"
if [[ -n "$AZURE_PRINCIPAL_ID" && ! "$AZURE_PRINCIPAL_ID" =~ $uuid_pattern ]]; then
  printf 'AZURE_PRINCIPAL_ID must be empty or a GUID.\n' >&2
  exit 1
fi

azd auth login --tenant-id "$AZURE_TENANT_ID"
az login --tenant "$AZURE_TENANT_ID" --output none
az account set --subscription "$AZURE_SUBSCRIPTION_ID"

selected_subscription="$(az account show --query id --output tsv)"
selected_tenant="$(az account show --query tenantId --output tsv)"

if [[ "$selected_subscription" != "$AZURE_SUBSCRIPTION_ID" ]]; then
  printf 'Azure CLI selected subscription %s instead of %s.\n' \
    "$selected_subscription" "$AZURE_SUBSCRIPTION_ID" >&2
  exit 1
fi

if [[ "$selected_tenant" != "$AZURE_TENANT_ID" ]]; then
  printf 'Azure CLI selected tenant %s instead of %s.\n' \
    "$selected_tenant" "$AZURE_TENANT_ID" >&2
  exit 1
fi

if [[ -d ".azure/$AZURE_ENV_NAME" ]]; then
  azd env select "$AZURE_ENV_NAME"
else
  azd env new "$AZURE_ENV_NAME" \
    --subscription "$AZURE_SUBSCRIPTION_ID" \
    --location "$AZURE_LOCATION" \
    --no-prompt
fi

azd env set AZURE_TENANT_ID "$AZURE_TENANT_ID"
azd env set AZURE_SUBSCRIPTION_ID "$AZURE_SUBSCRIPTION_ID"
azd env set AZURE_LOCATION "$AZURE_LOCATION"
azd env set AZURE_PRINCIPAL_ID "$AZURE_PRINCIPAL_ID"
azd env set BUDGET_CONTACT_EMAIL "$BUDGET_CONTACT_EMAIL"

printf '\nAzure context configured. Review it before deployment:\n'
azd env get-values
