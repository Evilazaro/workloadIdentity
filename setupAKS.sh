#!/usr/bin/env bash
# filepath: d:\workloadIdentity\setupAKS.sh
#
# Description: Sets up an AKS cluster with workload identity integration
#
# This script creates all necessary resources to demonstrate Azure AD workload identity
# with AKS and KeyVault integration, including:
# - Resource group
# - AKS cluster with OIDC issuer and workload identity enabled
# - User-assigned managed identity
# - Kubernetes service account with workload identity
# - Federated identity credential
# - Azure Key Vault with RBAC permissions
#
# Usage: ./setupAKS.sh [location]
# Example: ./setupAKS.sh eastus2
#
# Author: [Your Name]
# Date: May 7, 2025
# Version: 1.1

# Stop script on first error and unhandled failed commands in a pipe
set -e
set -o pipefail

# Script configuration
readonly DEFAULT_LOCATION="eastus2"
readonly LOG_FILE="aks_workload_identity_setup.log"

# Global variables for resources
RANDOM_ID=""
RESOURCE_GROUP=""
LOCATION=""
CLUSTER_NAME=""
USER_ASSIGNED_IDENTITY_NAME=""
SERVICE_ACCOUNT_NAMESPACE="default"
SERVICE_ACCOUNT_NAME=""
FEDERATED_IDENTITY_CREDENTIAL_NAME=""
KEYVAULT_NAME=""
SUBSCRIPTION=""
USER_ASSIGNED_CLIENT_ID=""
AKS_OIDC_ISSUER=""
KEYVAULT_RESOURCE_ID=""
CALLER_OBJECT_ID=""
KEYVAULT_SECRET_NAME=""
IDENTITY_PRINCIPAL_ID=""
KEYVAULT_URL=""

#############################################
# Helper Functions
#############################################

# Enable logging to file and console
setup_logging() {
    # Create log directory if it doesn't exist
    local log_dir=$(dirname "${LOG_FILE}")
    [[ -d "${log_dir}" ]] || mkdir -p "${log_dir}"
    
    # Redirect output to both console and log file
    exec > >(tee -a "${LOG_FILE}") 2>&1
    log_info "Logging initialized to ${LOG_FILE}"
}

# Log a message with timestamp and level
log() {
    local level="$1"
    local message="$2"
    echo "$(date +"%Y-%m-%d %H:%M:%S") - [${level}] ${message}"
}

log_info() {
    log "INFO" "$1"
}

log_error() {
    log "ERROR" "$1"
}

log_success() {
    log "SUCCESS" "$1"
}

log_warning() {
    log "WARNING" "$1"
}

# Display usage information
show_usage() {
    cat << EOF
Usage: $(basename "$0") [LOCATION]

Sets up an AKS cluster with workload identity integration.

Arguments:
  LOCATION      Azure region to deploy resources (default: ${DEFAULT_LOCATION})

Examples:
  $(basename "$0")         # Deploy to ${DEFAULT_LOCATION}
  $(basename "$0") westus2 # Deploy to westus2
EOF
}

# Check if a command exists
check_command() {
    local cmd="$1"
    if ! command -v "${cmd}" &> /dev/null; then
        log_error "${cmd} is required but not installed"
        log_info "Please install ${cmd} before running this script"
        return 1
    fi
    return 0
}

# Clean up resources on error
cleanup_on_error() {
    log_error "An error occurred. Cleaning up resources..."
    if [[ -n "${RESOURCE_GROUP}" ]]; then
        log_info "Deleting resource group: ${RESOURCE_GROUP}"
        az group delete --name "${RESOURCE_GROUP}" --yes --no-wait || true
    fi
    exit 1
}

#############################################
# Core Functions
#############################################

# Verify all prerequisites are met
verify_prerequisites() {
    log_info "Verifying prerequisites..."
    
    local prereqs=("az" "kubectl" "openssl")
    local missing_prereqs=0
    
    for cmd in "${prereqs[@]}"; do
        if ! check_command "${cmd}"; then
            missing_prereqs=$((missing_prereqs+1))
        fi
    done
    
    if [[ ${missing_prereqs} -gt 0 ]]; then
        log_error "${missing_prereqs} prerequisite(s) missing. Please install them and try again."
        exit 1
    fi

    # Check if logged in to Azure
    if ! az account show --query name -o tsv &>/dev/null; then
        log_error "Not logged into Azure. Run 'az login' first"
        exit 1
    fi
    
    log_success "All prerequisites verified"
}

# Initialize environment variables
initialize_environment() {
    log_info "Setting up environment variables..."
    
    RANDOM_ID="$(openssl rand -hex 3)"
    RESOURCE_GROUP="myResourceGroup${RANDOM_ID}"
    LOCATION="${1:-$DEFAULT_LOCATION}"
    CLUSTER_NAME="myAKSCluster${RANDOM_ID}"
    USER_ASSIGNED_IDENTITY_NAME="myIdentity${RANDOM_ID}"
    SERVICE_ACCOUNT_NAME="workload-identity-sa${RANDOM_ID}"
    FEDERATED_IDENTITY_CREDENTIAL_NAME="myFedIdentity${RANDOM_ID}"
    KEYVAULT_NAME="keyvault-workload-id${RANDOM_ID}"

    # Truncate Key Vault name if too long (max 24 characters)
    if [ ${#KEYVAULT_NAME} -gt 24 ]; then
        KEYVAULT_NAME="${KEYVAULT_NAME:0:24}"
    fi

    log_info "Using the following configuration:"
    log_info "- Resource Group: ${RESOURCE_GROUP}"
    log_info "- Location: ${LOCATION}"
    log_info "- AKS Cluster Name: ${CLUSTER_NAME}"
}

# Create Azure resource group
create_resource_group() {
    log_info "Creating resource group: ${RESOURCE_GROUP}"
    
    az group create \
        --name "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --output none || {
        log_error "Failed to create resource group"
        exit 1
    }
    
    # Get subscription ID
    log_info "Getting subscription ID"
    SUBSCRIPTION="$(az account show --query id --output tsv)"
    
    log_success "Resource group created successfully"
}

# Create AKS cluster with required features
create_aks_cluster() {
    log_info "Creating AKS cluster: ${CLUSTER_NAME} (this may take several minutes)"
    
    az aks create \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${CLUSTER_NAME}" \
        --enable-oidc-issuer \
        --enable-workload-identity \
        --generate-ssh-keys \
        --node-count 1 \
        --output none || {
        log_error "Failed to create AKS cluster"
        exit 1
    }
    
    log_success "AKS cluster created successfully"
}

# Create and configure user-assigned managed identity
create_managed_identity() {
    log_info "Creating user-assigned managed identity: ${USER_ASSIGNED_IDENTITY_NAME}"
    
    az identity create \
        --name "${USER_ASSIGNED_IDENTITY_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --subscription "${SUBSCRIPTION}" \
        --output none || {
        log_error "Failed to create user-assigned managed identity"
        exit 1
    }

    # Get user-assigned managed identity client ID
    log_info "Getting user-assigned managed identity client ID"
    USER_ASSIGNED_CLIENT_ID="$(az identity show \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${USER_ASSIGNED_IDENTITY_NAME}" \
        --query 'clientId' \
        --output tsv)"

    if [ -z "${USER_ASSIGNED_CLIENT_ID}" ]; then
        log_error "Failed to get user-assigned managed identity client ID"
        exit 1
    fi
    
    log_success "Managed identity created successfully"
}

# Configure AKS credentials and get OIDC issuer URL
configure_aks_credentials() {
    log_info "Getting AKS credentials"
    
    az aks get-credentials \
        --name "${CLUSTER_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --overwrite-existing || {
        log_error "Failed to get AKS credentials"
        exit 1
    }

    # Get AKS OIDC issuer URL
    log_info "Getting AKS OIDC issuer URL"
    AKS_OIDC_ISSUER="$(az aks show \
        --name "${CLUSTER_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query "oidcIssuerProfile.issuerUrl" \
        --output tsv)"

    if [ -z "${AKS_OIDC_ISSUER}" ]; then
        log_error "Failed to get AKS OIDC issuer URL"
        exit 1
    fi
    
    log_success "AKS credentials configured successfully"
}

# Create Kubernetes service account with workload identity
create_service_account() {
    log_info "Creating Kubernetes service account with workload identity"
    
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  annotations:
    azure.workload.identity/client-id: "${USER_ASSIGNED_CLIENT_ID}"
  name: "${SERVICE_ACCOUNT_NAME}"
  namespace: "${SERVICE_ACCOUNT_NAMESPACE}"
EOF

    # Verify service account was created
    if ! kubectl get serviceaccount "${SERVICE_ACCOUNT_NAME}" -n "${SERVICE_ACCOUNT_NAMESPACE}" &>/dev/null; then
        log_error "Failed to create Kubernetes service account"
        exit 1
    fi
    
    log_success "Kubernetes service account created successfully"
}

# Create federated identity credential
create_federated_identity() {
    log_info "Creating federated identity credential: ${FEDERATED_IDENTITY_CREDENTIAL_NAME}"
    
    az identity federated-credential create \
        --name "${FEDERATED_IDENTITY_CREDENTIAL_NAME}" \
        --identity-name "${USER_ASSIGNED_IDENTITY_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --issuer "${AKS_OIDC_ISSUER}" \
        --subject "system:serviceaccount:${SERVICE_ACCOUNT_NAMESPACE}:${SERVICE_ACCOUNT_NAME}" \
        --audience "api://AzureADTokenExchange" \
        --output none || {
        log_error "Failed to create federated identity credential"
        exit 1
    }
    
    log_success "Federated identity credential created successfully"
}

# Create and configure Azure Key Vault
create_key_vault() {
    log_info "Creating Azure Key Vault: ${KEYVAULT_NAME}"
    
    az keyvault create \
        --name "${KEYVAULT_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --enable-purge-protection true \
        --enable-rbac-authorization true \
        --output none || {
        log_error "Failed to create Key Vault"
        exit 1
    }

    # Get Key Vault resource ID
    log_info "Getting Key Vault resource ID"
    KEYVAULT_RESOURCE_ID=$(az keyvault show \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${KEYVAULT_NAME}" \
        --query id \
        --output tsv) || {
        log_error "Failed to get Key Vault resource ID"
        exit 1
    }
    
    log_success "Azure Key Vault created successfully"
}

# Configure current user access to Key Vault
configure_user_access() {
    log_info "Getting current user object ID"
    
    CALLER_OBJECT_ID=$(az ad signed-in-user show \
        --query id \
        --output tsv) || {
        log_error "Failed to get current user object ID"
        exit 1
    }

    # Add role assignment for current user
    log_info "Assigning Key Vault Secrets Officer role to current user"
    az role assignment create \
        --assignee "${CALLER_OBJECT_ID}" \
        --role "Key Vault Secrets Officer" \
        --scope "${KEYVAULT_RESOURCE_ID}" \
        --output none || {
        log_error "Failed to create role assignment for current user"
        exit 1
    }
    
    log_success "User access configured successfully"
}

# Create a test secret in Key Vault
create_key_vault_secret() {
    KEYVAULT_SECRET_NAME="my-secret${RANDOM_ID}"
    log_info "Creating secret: ${KEYVAULT_SECRET_NAME} in Key Vault"
    
    az keyvault secret set \
        --vault-name "${KEYVAULT_NAME}" \
        --name "${KEYVAULT_SECRET_NAME}" \
        --value "Hello!" \
        --output none || {
        log_error "Failed to set Key Vault secret"
        exit 1
    }
    
    log_success "Key Vault secret created successfully"
}

# Configure managed identity access to Key Vault
configure_identity_access() {
    log_info "Getting managed identity principal ID"
    
    IDENTITY_PRINCIPAL_ID=$(az identity show \
        --name "${USER_ASSIGNED_IDENTITY_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query principalId \
        --output tsv) || {
        log_error "Failed to get managed identity principal ID"
        exit 1
    }

    # Assign role to managed identity
    log_info "Assigning Key Vault Secrets User role to managed identity"
    az role assignment create \
        --assignee-object-id "${IDENTITY_PRINCIPAL_ID}" \
        --role "Key Vault Secrets User" \
        --scope "${KEYVAULT_RESOURCE_ID}" \
        --assignee-principal-type ServicePrincipal \
        --output none || {
        log_error "Failed to create role assignment for managed identity"
        exit 1
    }

    # Get Key Vault URI
    log_info "Getting Key Vault URI"
    KEYVAULT_URL="$(az keyvault show \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${KEYVAULT_NAME}" \
        --query properties.vaultUri \
        --output tsv)" || {
        log_error "Failed to get Key Vault URI"
        exit 1
    }
    
    log_success "Managed identity access configured successfully"
}

# Display setup summary
display_summary() {
    log_success "Setup completed successfully!"
    log_info "AKS Resources:"
    log_info "- Resource Group: ${RESOURCE_GROUP}"
    log_info "- Location: ${LOCATION}"
    log_info "- AKS Cluster: ${CLUSTER_NAME}"
    log_info "- User-assigned Identity: ${USER_ASSIGNED_IDENTITY_NAME} (Client ID: ${USER_ASSIGNED_CLIENT_ID})"
    log_info "- Kubernetes Service Account: ${SERVICE_ACCOUNT_NAME}"
    log_info "- Federated Identity Credential: ${FEDERATED_IDENTITY_CREDENTIAL_NAME}"

    log_info "Key Vault Resources:"
    log_info "- Key Vault Name: ${KEYVAULT_NAME}"
    log_info "- Key Vault URL: ${KEYVAULT_URL}"
    log_info "- Secret Name: ${KEYVAULT_SECRET_NAME}"

    log_info "To clean up resources, run: az group delete --name ${RESOURCE_GROUP} --yes"
}

# Main execution function
main() {
    # Show help if requested
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        show_usage
        exit 0
    fi
    
    # Setup logging
    setup_logging
    
    log_info "Starting AKS Workload Identity setup script"
    
    # Execute steps in sequence
    verify_prerequisites
    initialize_environment "$1"
    
    # Trap errors from this point to ensure cleanup
    trap 'cleanup_on_error' ERR
    
    create_resource_group
    create_aks_cluster
    create_managed_identity
    configure_aks_credentials
    create_service_account
    create_federated_identity
    create_key_vault
    configure_user_access
    create_key_vault_secret
    configure_identity_access
    display_summary
    
    log_info "Script execution completed"
}

# Execute main function
main "$@"