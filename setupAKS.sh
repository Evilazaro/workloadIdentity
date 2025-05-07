#!/usr/bin/env bash
# filepath: e:\workloadIdentity\setupAKS.sh
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
# Author: [Your Name]
# Date: May 6, 2025
# Version: 1.0

# Stop script on first error and unhandled failed commands in a pipe
set -e
set -o pipefail

# Script configuration
readonly DEFAULT_LOCATION="eastus2"
readonly LOG_FILE="aks_workload_identity_setup.log"

# Enable logging to file and console
exec > >(tee -a "${LOG_FILE}") 2>&1

#############################################
# Helper Functions
#############################################

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

# Check if a command exists
check_command() {
    if ! command -v "$1" &> /dev/null; then
        log_error "$1 is required but not installed"
        log_info "Please install $1 before running this script"
        exit 1
    fi
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

# Trap errors
trap 'cleanup_on_error' ERR

#############################################
# Verify Prerequisites
#############################################
log_info "Verifying prerequisites..."
check_command "az"
check_command "kubectl"
check_command "openssl"

# Check if logged in to Azure
if ! az account show --query name -o tsv &>/dev/null; then
    log_error "Not logged into Azure. Run 'az login' first"
    exit 1
fi

#############################################
# Environment Setup
#############################################
log_info "Setting up environment variables..."
RANDOM_ID="$(openssl rand -hex 3)"
RESOURCE_GROUP="myResourceGroup${RANDOM_ID}"
LOCATION="${1:-$DEFAULT_LOCATION}"
CLUSTER_NAME="myAKSCluster${RANDOM_ID}"
USER_ASSIGNED_IDENTITY_NAME="myIdentity${RANDOM_ID}"
SERVICE_ACCOUNT_NAMESPACE="default"
SERVICE_ACCOUNT_NAME="workload-identity-sa${RANDOM_ID}"
FEDERATED_IDENTITY_CREDENTIAL_NAME="myFedIdentity${RANDOM_ID}"
KEYVAULT_NAME="keyvault-workload-id${RANDOM_ID}"

# Truncate Key Vault name if too long (max 24 characters)
if [ ${#KEYVAULT_NAME} -gt 24 ]; then
    KEYVAULT_NAME="${KEYVAULT_NAME:0:24}"
fi

# Export vars for potential external use
export RANDOM_ID RESOURCE_GROUP LOCATION CLUSTER_NAME 
export USER_ASSIGNED_IDENTITY_NAME SERVICE_ACCOUNT_NAMESPACE SERVICE_ACCOUNT_NAME
export FEDERATED_IDENTITY_CREDENTIAL_NAME KEYVAULT_NAME

log_info "Using the following configuration:"
log_info "- Resource Group: ${RESOURCE_GROUP}"
log_info "- Location: ${LOCATION}"
log_info "- AKS Cluster Name: ${CLUSTER_NAME}"

#############################################
# Create Azure Resources
#############################################

# Create resource group
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
export SUBSCRIPTION

# Create AKS cluster
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

# Create user-assigned managed identity
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
export USER_ASSIGNED_CLIENT_ID

# Get AKS credentials
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
export AKS_OIDC_ISSUER

#############################################
# Configure Kubernetes Service Account
#############################################

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

#############################################
# Create Federated Identity
#############################################

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

#############################################
# Setup Azure Key Vault
#############################################

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
export KEYVAULT_RESOURCE_ID

# Get current user object ID
log_info "Getting current user object ID"
CALLER_OBJECT_ID=$(az ad signed-in-user show \
    --query id \
    --output tsv) || {
    log_error "Failed to get current user object ID"
    exit 1
}
export CALLER_OBJECT_ID

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

# Create a test secret
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
export KEYVAULT_SECRET_NAME

# Get managed identity principal ID
log_info "Getting managed identity principal ID"
IDENTITY_PRINCIPAL_ID=$(az identity show \
    --name "${USER_ASSIGNED_IDENTITY_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --query principalId \
    --output tsv) || {
    log_error "Failed to get managed identity principal ID"
    exit 1
}
export IDENTITY_PRINCIPAL_ID

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
export KEYVAULT_URL

#############################################
# Summary
#############################################

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