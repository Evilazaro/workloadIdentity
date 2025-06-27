#!/bin/bash

# Azure Post-Provision Hook Script
# Purpose: Create certificates in Key Vault and configure AKS credentials
# Usage: ./postprovision.sh <resource_group> <aks_cluster> <keyvault_name>

set -euo pipefail  # Exit on error, undefined vars, and pipe failures

# Global configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly CERT_NAME="${CERT_NAME:-workload-identity-cert}"
readonly CERT_SUBJECT="${CERT_SUBJECT:-CN=workload-identity.local}"
readonly CERT_DNS_NAME="${CERT_DNS_NAME:-workload-identity.local}"
readonly CERT_VALIDITY_MONTHS="${CERT_VALIDITY_MONTHS:-12}"
readonly POLICY_FILE="$(mktemp -t cert-policy-XXXXXX.json)"

# Input parameters with validation
AZURE_RESOURCE_GROUP_NAME="${1:-}"
AZURE_AKS_CLUSTER_NAME="${2:-}"
AZURE_KEYVAULT_NAME="${3:-}"
AZURE_ENV_NAME="${4:-}"
AZURE_MANAGED_IDENTITY_CLIENT_ID="${5:-}"
readonly ENV_FILE="./.azure/${AZURE_ENV_NAME}/.env"

# Cleanup function to remove temporary files
cleanup() {
    local exit_code=$?
    if [[ -f "$POLICY_FILE" ]]; then
        rm -f "$POLICY_FILE"
        log_info "Cleaned up temporary policy file"
    fi
    exit $exit_code
}

# Set up cleanup trap
trap cleanup EXIT

# Logging functions
log_info() {
    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - $*" >&2
}

log_error() {
    echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - $*" >&2
}

log_warn() {
    echo "[WARN] $(date '+%Y-%m-%d %H:%M:%S') - $*" >&2
}

# Validation function
validate_inputs() {
    local errors=0
    
    if [[ -z "$AZURE_RESOURCE_GROUP_NAME" ]]; then
        log_error "Resource group name is required as first argument"
        ((errors++))
    fi
    
    if [[ -z "$AZURE_AKS_CLUSTER_NAME" ]]; then
        log_error "AKS cluster name is required as second argument"
        ((errors++))
    fi
    
    if [[ -z "$AZURE_KEYVAULT_NAME" ]]; then
        log_error "Key Vault name is required as third argument"
        ((errors++))
    fi
    
    if ! command -v az >/dev/null 2>&1; then
        log_error "Azure CLI is not installed or not in PATH"
        ((errors++))
    fi
    
    if [[ $errors -gt 0 ]]; then
        echo "Usage: $0 <resource_group> <aks_cluster> <keyvault_name>" >&2
        exit 1
    fi
}

# Function to create certificate policy
create_certificate_policy() {
    log_info "Creating certificate policy for subject: $CERT_SUBJECT"
    
    cat <<EOF > "$POLICY_FILE"
{
  "issuerParameters": {
    "name": "Self"
  },
  "x509CertificateProperties": {
    "subject": "$CERT_SUBJECT",
    "validityInMonths": $CERT_VALIDITY_MONTHS,
    "keyUsage": [
      "digitalSignature",
      "keyEncipherment"
    ],
    "subjectAlternativeNames": {
      "dnsNames": ["$CERT_DNS_NAME"]
    }
  },
  "keyProperties": {
    "exportable": true,
    "keyType": "RSA",
    "keySize": 2048,
    "reuseKey": false
  },
  "secretProperties": {
    "contentType": "application/x-pem-file"
  }
}
EOF

    if [[ ! -f "$POLICY_FILE" ]] || [[ ! -s "$POLICY_FILE" ]]; then
        log_error "Failed to create certificate policy file"
        return 1
    fi
    
    log_info "Certificate policy created successfully"
}

# Function to create certificate in Key Vault
create_certificate() {
    log_info "Creating certificate '$CERT_NAME' in Key Vault '$AZURE_KEYVAULT_NAME'"
    
    if ! az keyvault certificate create \
        --vault-name "$AZURE_KEYVAULT_NAME" \
        --name "$CERT_NAME" \
        --policy "@$POLICY_FILE" \
        --output none; then
        log_error "Failed to create certificate in Key Vault"
        return 1
    fi
    
    log_info "Certificate '$CERT_NAME' created successfully in Key Vault '$AZURE_KEYVAULT_NAME'"
}

# Function to retrieve and store certificate secret
store_certificate_secret() {
    log_info "Retrieving certificate secret from Key Vault"
    
    local azure_pem_secret
    if ! azure_pem_secret=$(az keyvault secret show \
        --vault-name "$AZURE_KEYVAULT_NAME" \
        --name "$CERT_NAME" \
        --query "value" \
        --output tsv 2>/dev/null); then
        log_error "Failed to retrieve certificate secret from Key Vault"
        return 1
    fi
    
    if [[ -z "$azure_pem_secret" ]]; then
        log_error "Retrieved certificate secret is empty"
        return 1
    fi
    
    # Ensure ENV_FILE directory exists
    local env_dir
    env_dir="$(dirname "$ENV_FILE")"
    if [[ ! -d "$env_dir" ]]; then
        log_info "Creating environment directory: $env_dir"
        mkdir -p "$env_dir"
    fi
    
    # Store the secret in environment file
    echo "AZURE_PEM_SECRET=\"$azure_pem_secret\"" >> "$ENV_FILE"
    log_info "Certificate secret stored in environment file: $ENV_FILE"
}

# Function to configure AKS credentials
configure_aks_credentials() {
    log_info "Configuring AKS credentials for cluster '$AZURE_AKS_CLUSTER_NAME'"
    
    if ! az aks get-credentials \
        --resource-group "$AZURE_RESOURCE_GROUP_NAME" \
        --name "$AZURE_AKS_CLUSTER_NAME" \
        --overwrite-existing \
        --output none; then
        log_error "Failed to configure AKS credentials"
        return 1
    fi
    
    log_info "AKS credentials configured successfully"
}

# Function to create Kubernetes service account with workload identity
create_service_account() {
    log_info "Creating Kubernetes service account with workload identity"
    ./new-service-account.sh "$AZURE_MANAGED_IDENTITY_CLIENT_ID" || {
        log_error "Failed to create Kubernetes service account"
        return 1
    }
    log_info "Kubernetes service account created successfully"
}

# Main execution function
main() {
    log_info "Starting post-provision hook script"
    log_info "Parameters: RG=$AZURE_RESOURCE_GROUP_NAME, AKS=$AZURE_AKS_CLUSTER_NAME, KV=$AZURE_KEYVAULT_NAME"
    
    validate_inputs
    create_certificate_policy
    create_certificate
    store_certificate_secret
    configure_aks_credentials
    create_service_account

    log_info "Post-provision hook completed successfully"
}

# Execute main function
main "$@"