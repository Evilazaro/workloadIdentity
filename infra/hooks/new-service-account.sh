#!/bin/bash


# Example usage (uncomment to test):
SERVICE_ACCOUNT_NAME="workload-identity-sa"
SERVICE_ACCOUNT_NAMESPACE="default"
AZURE_MANAGED_IDENTITY_CLIENT_ID="${1:-}"
LOG_FILE="./setup.log"

# Function: create_service_account
# Description: Creates Kubernetes service account with workload identity
# Creates a Kubernetes service account with the necessary annotations for workload identity
create_service_account() {
    log_message "INFO" "Creating Kubernetes service account with workload identity"
    
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
            log_message "ERROR" "Failed to apply service account YAML"
            exit_code=1
        else
            # Verify service account was created
            if ! kubectl get serviceaccount "${SERVICE_ACCOUNT_NAME}" -n "${SERVICE_ACCOUNT_NAMESPACE}" >/dev/null 2>&1; then
                log_message "ERROR" "Failed to verify Kubernetes service account creation"
                exit_code=1
            else
                log_message "SUCCESS" "Kubernetes service account created successfully"
            fi
        fi
        
    } || {
        log_message "ERROR" "Failed to create Kubernetes service account: $?"
        exit_code=1
    }
    
    # Clean up temporary file
    rm -f "${temp_file}"
    
    # Exit if there was an error
    if [[ ${exit_code} -ne 0 ]]; then
        exit 1
    fi
}

# Helper function for logging (assuming this exists in the main script)
log_message() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "${level}" in
        "ERROR")
            echo -e "\033[31m${timestamp} - [${level}] ${message}\033[0m" >&2
            ;;
        "SUCCESS")
            echo -e "\033[32m${timestamp} - [${level}] ${message}\033[0m"
            ;;
        "WARNING")
            echo -e "\033[33m${timestamp} - [${level}] ${message}\033[0m"
            ;;
        *)
            echo "${timestamp} - [${level}] ${message}"
            ;;
    esac
    
    # Also log to file if LOG_FILE is set
    if [[ -n "${LOG_FILE}" ]]; then
        echo "${timestamp} - [${level}] ${message}" >> "${LOG_FILE}"
    fi
}


# create_service_account
