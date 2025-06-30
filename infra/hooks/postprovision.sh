#!/bin/bash

# Azure Post-Provision Hook Script
# Purpose: Create certificates in Key Vault and configure AKS credentials
# Usage: ./postprovision.sh <resource_group> <aks_cluster> <keyvault_name>

set -euo pipefail  # Exit on error, undefined vars, and pipe failures

# Global configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly CERT_NAME="${CERT_NAME:-tls-crt}"
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
AZURE_MANAGED_IDENTITY_NAME="${6:-}"
AZURE_OIDC_ISSUER_URL="${7:-}"
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

# Function to install Secrets Store CSI Driver and Azure Key Vault provider
install_csi_drivers() {
    log_info "Installing Secrets Store CSI Driver and Azure Key Vault provider"
    
    # Check if helm is available
    if ! command -v helm >/dev/null 2>&1; then
        log_error "Helm is not installed or not in PATH"
        return 1
    fi
    
    # Add the Azure Key Vault provider repository
    log_info "Adding Azure Key Vault provider repository"
    if ! helm repo add csi-secrets-store-provider-azure https://azure.github.io/secrets-store-csi-driver-provider-azure/charts; then
        log_error "Failed to add Azure Key Vault provider repository"
        return 1
    fi
    
    # Update Helm repositories
    log_info "Updating Helm repositories"
    if ! helm repo update; then
        log_error "Failed to update Helm repositories"
        return 1
    fi
    
    # Install the Azure Key Vault provider
    log_info "Installing Azure Key Vault provider"
    if ! helm install azure-csi-provider csi-secrets-store-provider-azure/csi-secrets-store-provider-azure --namespace kube-system; then
        log_error "Failed to install Secrets Store CSI Driver or Azure Key Vault provider"
        log_info "For more troubleshooting, check pod logs: kubectl logs -n kube-system -l app=secrets-store-csi-driver"
        return 1
    fi
    
    log_info "Secrets Store CSI Driver and Azure Key Vault provider installed successfully"
}

# Example usage (uncomment to test):
SERVICE_ACCOUNT_NAME="workload-identity-sa"
SERVICE_ACCOUNT_NAMESPACE="default"
LOG_FILE="./setup.log"

# Function: create_service_account
# Description: Creates Kubernetes service account with workload identity
# Creates a Kubernetes service account with the necessary annotations for workload identity
create_service_account() {
    log_info "INFO" "Creating Kubernetes service account with workload identity"
    
    # Create the service account YAML content
    local service_account_yaml=$(cat <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  annotations:
    azure.workload.identity/client-id: "${AZURE_MANAGED_IDENTITY_CLIENT_ID}"
  name: "${SERVICE_ACCOUNT_NAME}"
  namespace: "${SERVICE_ACCOUNT_NAMESPACE}"
EOF
)
    
    # Create temporary file for the YAML
    local temp_file=$(mktemp /tmp/service-account-XXXXXX.yaml)
    
    # Error handling with cleanup
    local exit_code=0
    
    {
        # Write YAML to temporary file
        echo "${service_account_yaml}" > "${temp_file}"
        
        # Apply the service account YAML
        if ! kubectl apply -f "${temp_file}"; then
            log_info "ERROR" "Failed to apply service account YAML"
            exit_code=1
        else
            # Verify service account was created
            if ! kubectl get serviceaccount "${SERVICE_ACCOUNT_NAME}" -n "${SERVICE_ACCOUNT_NAMESPACE}" >/dev/null 2>&1; then
                log_info "ERROR" "Failed to verify Kubernetes service account creation"
                exit_code=1
            else
                log_info "SUCCESS" "Kubernetes service account created successfully"
            fi
        fi
        
    } || {
        log_info "ERROR" "Failed to create Kubernetes service account: $?"
        exit_code=1
    }
    
    # Clean up temporary file
    rm -f "${temp_file}"
    
    # Exit if there was an error
    if [[ ${exit_code} -ne 0 ]]; then
        exit 1
    fi
}

installHelm() {
    log_info "Installing Helm"
    if command -v helm >/dev/null 2>&1; then
        log_info "Helm is already installed"
        return 0
    fi

    # Install Helm using the script provided in the Helm documentation
    if ! curl -fsSL https://baltocdn.com/helm/signing.asc | gpg --dearmor | sudo tee /usr/share/keyrings/helm.gpg > /dev/null; then
        log_error "Failed to download Helm signing key"
        return 1
    fi

    if ! sudo apt-get install -y apt-transport-https; then
        log_error "Failed to install apt-transport-https"
        return 1
    fi

    if ! echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list; then
        log_error "Failed to add Helm apt repository"
        return 1
    fi

    if ! sudo apt-get update; then
        log_error "Failed to update apt repositories"
        return 1
    fi

    if ! sudo apt-get install -y helm; then
        log_error "Failed to install Helm"
        return 1
    fi

    log_info "Helm installed successfully"
}

# Function to create federated identity credential using Azure CLI
create_federated_identity_credential() {
    local federated_identity_credential_name="workload-identity-fa"
    local service_account_namespace="default"
    local service_account_name="workload-identity-sa"

    if [[ -z "$AZURE_OIDC_ISSUER_URL" ]]; then
        log_error "AKS OIDC issuer URL is required (set AKS_OIDC_ISSUER env var)"
        return 1
    fi

    log_info "Creating federated identity credential: $federated_identity_credential_name"

    if ! az identity federated-credential create \
        --name "$federated_identity_credential_name" \
        --identity-name "$AZURE_MANAGED_IDENTITY_NAME" \
        --resource-group "$AZURE_RESOURCE_GROUP_NAME" \
        --issuer "$AZURE_OIDC_ISSUER_URL" \
        --subject "system:serviceaccount:${service_account_namespace}:${service_account_name}" \
        --audiences "api://AzureADTokenExchange" \
        --output none; then
        log_error "Failed to create federated identity credential"
        return 1
    fi

    log_info "Federated identity credential created successfully"
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
    create_federated_identity_credential
    installHelm

    log_info "Post-provision hook completed successfully"
}

# Execute main function
main "$@"