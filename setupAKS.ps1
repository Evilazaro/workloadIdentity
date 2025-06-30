<#
.SYNOPSIS
    Sets up an AKS cluster with workload identity integration using Azure CLI.

.DESCRIPTION
    This script creates all necessary resources to demonstrate Azure AD workload identity
    with AKS and KeyVault integration using Azure CLI commands, including:
    - Resource group
    - AKS cluster with OIDC issuer and workload identity enabled
    - User-assigned managed identity
    - Kubernetes service account with workload identity
    - Federated identity credential
    - Azure Key Vault with RBAC permissions

.PARAMETER Location
    Azure region to deploy resources (default: eastus2)

.EXAMPLE
    .\SetupAKS.ps1
    # Deploy to default location (eastus2)

.EXAMPLE
    .\SetupAKS.ps1 -Location "westus2"
    # Deploy to westus2

.NOTES
    Author: [Your Name]
    Date: May 7, 2025
    Version: 2.0
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Location = "eastus2"
)

#region Configuration
# Script configuration
$script:LogFile = "aks_workload_identity_setup.log"

# Resource variables
$script:RandomId = $null
$script:ResourceGroupName = $null
$script:ClusterName = $null
$script:UserAssignedIdentityName = $null
$script:ServiceAccountNamespace = "default"
$script:ServiceAccountName = $null
$script:FederatedIdentityCredentialName = $null
$script:KeyVaultName = $null
$script:SubscriptionId = $null
$script:UserAssignedClientId = $null
$script:AksOidcIssuer = $null
$script:KeyVaultResourceId = $null
$script:CallerObjectId = $null
$script:KeyVaultSecretName = $null
$script:KeyVaultCertificateName = $null
$script:IdentityPrincipalId = $null
$script:KeyVaultUrl = $null
#endregion

#region Helper Functions
function Initialize-Logging {
    <#
    .SYNOPSIS
        Sets up logging to file and console.
    .DESCRIPTION
        Creates log directory if it doesn't exist and initializes logging.
    #>
    [CmdletBinding()]
    param()

    try {
        $logDir = Split-Path -Parent $script:LogFile
        if (-not (Test-Path -Path $logDir) -and $logDir -ne "") {
            New-Item -Path $logDir -ItemType Directory -Force | Out-Null
        }
        
        Write-LogMessage -Level "INFO" -Message "Logging initialized to $($script:LogFile)"
    }
    catch {
        Write-Error "Failed to initialize logging: $_"
        exit 1
    }
}

function Write-LogMessage {
    <#
    .SYNOPSIS
        Writes a log message with timestamp and level.
    .DESCRIPTION
        Formats and writes a log message to both console and log file.
    .PARAMETER Level
        Log level (INFO, ERROR, SUCCESS, WARNING).
    .PARAMETER Message
        The message to log.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateSet("INFO", "ERROR", "SUCCESS", "WARNING")]
        [string]$Level,
        
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "$timestamp - [$Level] $Message"
    
    # Output to console with appropriate color
    switch ($Level) {
        "ERROR" { 
            Write-Host $logMessage -ForegroundColor Red 
        }
        "WARNING" { 
            Write-Host $logMessage -ForegroundColor Yellow 
        }
        "SUCCESS" { 
            Write-Host $logMessage -ForegroundColor Green 
        }
        default { 
            Write-Host $logMessage 
        }
    }
    
    # Output to log file
    Add-Content -Path $script:LogFile -Value $logMessage
}

function Test-CommandExists {
    <#
    .SYNOPSIS
        Checks if a command exists.
    .DESCRIPTION
        Verifies if the specified command is available in the system.
    .PARAMETER Command
        The command to check.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Command
    )

    try {
        if (Get-Command $Command -ErrorAction Stop) {
            return $true
        }
    }
    catch {
        Write-LogMessage -Level "ERROR" -Message "$Command is required but not installed"
        Write-LogMessage -Level "INFO" -Message "Please install $Command before running this script"
        return $false
    }
}

function Clear-ResourcesOnError {
    <#
    .SYNOPSIS
        Cleans up resources when an error occurs.
    .DESCRIPTION
        Deletes the resource group to clean up all created resources.
    #>
    [CmdletBinding()]
    param()

    Write-LogMessage -Level "ERROR" -Message "An error occurred. Cleaning up resources..."
    if ($script:ResourceGroupName) {
        Write-LogMessage -Level "INFO" -Message "Deleting resource group: $($script:ResourceGroupName)"
        try {
            az group delete --name $script:ResourceGroupName --yes --no-wait
        }
        catch {
            # Continue even if cleanup fails
        }
    }
}
#endregion

function Initialize-Environment {
    <#
    .SYNOPSIS
        Initializes environment variables for the deployment.
    .DESCRIPTION
        Sets up resource names and other variables needed for the deployment.
    .PARAMETER LocationName
        Azure region to deploy resources.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$LocationName
    )

    Write-LogMessage -Level "INFO" -Message "Setting up environment variables..."
    
    # Generate a random ID for resource names
    $randomHex = -join ((48..57) + (97..102) | Get-Random -Count 6 | ForEach-Object { [char]$_ })
    $script:RandomId = $randomHex
    
    $script:ResourceGroupName = "myResourceGroup$script:RandomId"
    $script:ClusterName = "myAKSCluster$script:RandomId"
    $script:UserAssignedIdentityName = "workload-identity-id"
    $script:ServiceAccountName = "workload-identity-sa"
    $script:FederatedIdentityCredentialName = "workload-identity-fa"
    $script:KeyVaultName = "keyvault-workload-id$script:RandomId"

    # Truncate Key Vault name if too long (max 24 characters)
    if ($script:KeyVaultName.Length -gt 24) {
        $script:KeyVaultName = $script:KeyVaultName.Substring(0, 24)
    }

    Write-LogMessage -Level "INFO" -Message "Using the following configuration:"
    Write-LogMessage -Level "INFO" -Message "- Resource Group: $script:ResourceGroupName"
    Write-LogMessage -Level "INFO" -Message "- Location: $LocationName"
    Write-LogMessage -Level "INFO" -Message "- AKS Cluster Name: $script:ClusterName"
}

function New-AzureResourceGroup {
    <#
    .SYNOPSIS
        Creates Azure resource group using Azure CLI.
    .DESCRIPTION
        Creates a resource group in the specified location and gets the subscription ID.
    #>
    [CmdletBinding()]
    param()

    Write-LogMessage -Level "INFO" -Message "Creating resource group: $script:ResourceGroupName"
    
    try {
        # Create resource group
        az group create --name $script:ResourceGroupName --location $Location --output none
        
        # Get subscription ID
        Write-LogMessage -Level "INFO" -Message "Getting subscription ID"
        $script:SubscriptionId = $(az account show --query id --output tsv)
        
        Write-LogMessage -Level "SUCCESS" -Message "Resource group created successfully"
    }
    catch {
        Write-LogMessage -Level "ERROR" -Message "Failed to create resource group: $_"
        exit 1
    }
}

function New-AksCluster {
    <#
    .SYNOPSIS
        Creates AKS cluster with required features using Azure CLI.
    .DESCRIPTION
        Creates an AKS cluster with OIDC issuer and workload identity enabled.
    #>
    [CmdletBinding()]
    param()

    Write-LogMessage -Level "INFO" -Message "Creating AKS cluster: $script:ClusterName (this may take several minutes)"
    
    try {
        az aks create `
            --resource-group $script:ResourceGroupName `
            --name $script:ClusterName `
            --enable-addons azure-keyvault-secrets-provider  `
            --enable-oidc-issuer `
            --enable-workload-identity `
            --generate-ssh-keys `
            --node-count 1 `
            --output none
        
        Write-LogMessage -Level "SUCCESS" -Message "AKS cluster created successfully"
    }
    catch {
        Write-LogMessage -Level "ERROR" -Message "Failed to create AKS cluster: $_"
        exit 1
    }
}

function New-ManagedIdentity {
    <#
    .SYNOPSIS
        Creates and configures user-assigned managed identity using Azure CLI.
    .DESCRIPTION
        Creates a user-assigned managed identity and retrieves its client ID.
    #>
    [CmdletBinding()]
    param()

    Write-LogMessage -Level "INFO" -Message "Creating user-assigned managed identity: $script:UserAssignedIdentityName"
    
    try {
        # Create managed identity
        az identity create `
            --name $script:UserAssignedIdentityName `
            --resource-group $script:ResourceGroupName `
            --location $Location `
            --subscription $script:SubscriptionId `
            --output none
            
        # Get user-assigned managed identity client ID
        Write-LogMessage -Level "INFO" -Message "Getting user-assigned managed identity client ID"
        $script:UserAssignedClientId = $(az identity show `
            --resource-group $script:ResourceGroupName `
            --name $script:UserAssignedIdentityName `
            --query 'clientId' `
            --output tsv)

        if ([string]::IsNullOrEmpty($script:UserAssignedClientId)) {
            throw "Failed to get user-assigned managed identity client ID"
        }
        
        # Get principal ID for later use
        $script:IdentityPrincipalId = $(az identity show `
            --resource-group $script:ResourceGroupName `
            --name $script:UserAssignedIdentityName `
            --query 'principalId' `
            --output tsv)
            
        Write-LogMessage -Level "SUCCESS" -Message "Managed identity created successfully"
    }
    catch {
        Write-LogMessage -Level "ERROR" -Message "Failed to create user-assigned managed identity: $_"
        exit 1
    }
}

function Set-AksCredentials {
    <#
    .SYNOPSIS
        Configures AKS credentials and gets OIDC issuer URL using Azure CLI.
    .DESCRIPTION
        Gets AKS credentials for kubectl and retrieves the OIDC issuer URL.
    #>
    [CmdletBinding()]
    param()

    Write-LogMessage -Level "INFO" -Message "Getting AKS credentials"
    
    try {
        # Get AKS credentials
        az aks get-credentials `
            --name $script:ClusterName `
            --resource-group $script:ResourceGroupName `
            --overwrite-existing

        # Get AKS OIDC issuer URL
        Write-LogMessage -Level "INFO" -Message "Getting AKS OIDC issuer URL"
        $script:AksOidcIssuer = $(az aks show `
            --name $script:ClusterName `
            --resource-group $script:ResourceGroupName `
            --query "oidcIssuerProfile.issuerUrl" `
            --output tsv)

        if ([string]::IsNullOrEmpty($script:AksOidcIssuer)) {
            throw "Failed to get AKS OIDC issuer URL"
        }
        
        Write-LogMessage -Level "SUCCESS" -Message "AKS credentials configured successfully"
    }
    catch {
        Write-LogMessage -Level "ERROR" -Message "Failed to configure AKS credentials: $_"
        exit 1
    }
}

function New-ServiceAccount {
    <#
    .SYNOPSIS
        Creates Kubernetes service account with workload identity.
    .DESCRIPTION
        Creates a Kubernetes service account with the necessary annotations for workload identity.
    #>
    [CmdletBinding()]
    param()

    Write-LogMessage -Level "INFO" -Message "Creating Kubernetes service account with workload identity"
    
    try {
        $serviceAccountYaml = @"
apiVersion: v1
kind: ServiceAccount
metadata:
  annotations:
    azure.workload.identity/client-id: "$script:UserAssignedClientId"
  name: "$script:ServiceAccountName"
  namespace: "$script:ServiceAccountNamespace"
"@

        # Apply the service account YAML
        $tempFile = New-TemporaryFile
        $serviceAccountYaml | Out-File -FilePath $tempFile -Encoding utf8
        kubectl apply -f $tempFile
        Remove-Item -Path $tempFile

        # Verify service account was created
        $result = kubectl get serviceaccount $script:ServiceAccountName -n $script:ServiceAccountNamespace 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to create Kubernetes service account: $result"
        }
        
        Write-LogMessage -Level "SUCCESS" -Message "Kubernetes service account created successfully"
    }
    catch {
        Write-LogMessage -Level "ERROR" -Message "Failed to create Kubernetes service account: $_"
        exit 1
    }
}

function New-FederatedIdentity {
    <#
    .SYNOPSIS
        Creates federated identity credential using Azure CLI.
    .DESCRIPTION
        Creates a federated identity credential linking the Kubernetes service account to the managed identity.
    #>
    [CmdletBinding()]
    param()

    Write-LogMessage -Level "INFO" -Message "Creating federated identity credential: $script:FederatedIdentityCredentialName"
    
    try {
        az identity federated-credential create `
            --name $script:FederatedIdentityCredentialName `
            --identity-name $script:UserAssignedIdentityName `
            --resource-group $script:ResourceGroupName `
            --issuer $script:AksOidcIssuer `
            --subject "system:serviceaccount:${script:ServiceAccountNamespace}:${script:ServiceAccountName}" `
            --audience "api://AzureADTokenExchange" `
            --output none
        
        Write-LogMessage -Level "SUCCESS" -Message "Federated identity credential created successfully"
    }
    catch {
        Write-LogMessage -Level "ERROR" -Message "Failed to create federated identity credential: $_"
        exit 1
    }
}

function New-KeyVault {
    <#
    .SYNOPSIS
        Creates and configures Azure Key Vault using Azure CLI.
    .DESCRIPTION
        Creates an Azure Key Vault with RBAC authorization enabled and retrieves its resource ID.
    #>
    [CmdletBinding()]
    param()

    Write-LogMessage -Level "INFO" -Message "Creating Azure Key Vault: $script:KeyVaultName"
    
    try {
        # Create Key Vault with RBAC enabled
        az keyvault create `
            --name $script:KeyVaultName `
            --resource-group $script:ResourceGroupName `
            --location $Location `
            --enable-purge-protection true `
            --enable-rbac-authorization true `
            --output none

        # Get Key Vault resource ID
        Write-LogMessage -Level "INFO" -Message "Getting Key Vault resource ID"
        $script:KeyVaultResourceId = $(az keyvault show `
            --name $script:KeyVaultName `
            --resource-group $script:ResourceGroupName `
            --query id `
            --output tsv)

        if ([string]::IsNullOrEmpty($script:KeyVaultResourceId)) {
            throw "Failed to get Key Vault resource ID"
        }
        
        # Get Key Vault URL for later use
        $script:KeyVaultUrl = $(az keyvault show `
            --name $script:KeyVaultName `
            --resource-group $script:ResourceGroupName `
            --query properties.vaultUri `
            --output tsv)
        
        Write-LogMessage -Level "SUCCESS" -Message "Azure Key Vault created successfully"
    }
    catch {
        Write-LogMessage -Level "ERROR" -Message "Failed to create Key Vault: $_"
        exit 1
    }
}

function Set-UserAccess {
    <#
    .SYNOPSIS
        Configures current user access to Key Vault using Azure CLI.
    .DESCRIPTION
        Gets the current user's object ID and assigns the Key Vault Secrets Officer role.
    #>
    [CmdletBinding()]
    param()

    Write-LogMessage -Level "INFO" -Message "Getting current user object ID"
    
    try {
        # Get current user object ID
        $script:CallerObjectId = $(az ad signed-in-user show --query id --output tsv)

        # Add role assignment for current user
        Write-LogMessage -Level "INFO" -Message "Assigning Key Vault Secrets Officer role to current user"
        az role assignment create `
            --assignee $script:CallerObjectId `
            --role "Key Vault Secrets Officer" `
            --scope $script:KeyVaultResourceId `
            --output none
        
        Write-LogMessage -Level "SUCCESS" -Message "User access configured successfully"

        Write-LogMessage -Level "INFO" -Message "Assigning Key Vault Certificates Officer role to current user"
        az role assignment create `
            --assignee $script:CallerObjectId `
            --role "Key Vault Certificates Officer" `
            --scope $script:KeyVaultResourceId `
            --output none
        
        Write-LogMessage -Level "SUCCESS" -Message "User access configured successfully"
    }
    catch {
        Write-LogMessage -Level "ERROR" -Message "Failed to configure user access: $_"
        exit 1
    }
}

function New-KeyVaultSecret {
    <#
    .SYNOPSIS
        Creates test secrets and certificates in Azure Key Vault.
    .DESCRIPTION
        Creates a test secret and self-signed certificate in the Key Vault using Azure CLI and
        exports the certificate to the local file system.
    .NOTES
        Follows Azure security best practices for certificate management.
    #>
    [CmdletBinding()]
    param()

    $script:KeyVaultSecretName = "mysql-secret"
    $script:KeyVaultCertificateName = "tls-crt"
    $certificateOutputPath = ".\certs"
    $tempPolicyPath = ".\cert-policy.json"
    
    try {
        Write-LogMessage -Level "INFO" -Message "Creating test secret in Key Vault: $script:KeyVaultSecretName"

        # Create a secret in Key Vault with expiration date (Azure best practice)
        $expiryDate = (Get-Date).AddYears(1).ToString("yyyy-MM-dd")
        az keyvault secret set `
            --vault-name $script:KeyVaultName `
            --name $script:KeyVaultSecretName `
            --value "Hello!" `
            --expires $expiryDate `
            --output none
        
        Write-LogMessage -Level "SUCCESS" -Message "Key Vault secret created successfully with 1-year expiration"

        # Create directory for certificate output if it doesn't exist
        if (-not (Test-Path -Path $certificateOutputPath)) {
            New-Item -Path $certificateOutputPath -ItemType Directory -Force | Out-Null
            Write-LogMessage -Level "INFO" -Message "Created certificate output directory: $certificateOutputPath"
        }

        # Create certificate in Key Vault
        Write-LogMessage -Level "INFO" -Message "Creating test certificate in Key Vault: $script:KeyVaultCertificateName"

        # Create certificate policy with Azure recommended settings
        $validityInMonths = 12 # 1 year validity (shorter is better for security)
        $policyJson = @"
{
  "issuerParameters": {
    "name": "Self"
  },
  "x509CertificateProperties": {
    "subject": "CN=mydomain.com",
    "validityInMonths": $validityInMonths,
    "keyUsage": [
      "digitalSignature",
      "keyEncipherment"
    ],
    "subjectAlternativeNames": {
      "dnsNames": ["mydomain.com"]
    }
  },
  "keyProperties": {
    "exportable": true,
    "keyType": "RSA",
    "keySize": 3072,
    "reuseKey": false
  },
  "secretProperties": {
    "contentType": "application/x-pem-file"
  }
}
"@ | Out-File -Encoding utf8 -FilePath $tempPolicyPath

        # Create certificate in Key Vault
        az keyvault certificate create `
            --vault-name $script:KeyVaultName `
            --name $script:KeyVaultCertificateName `
            --policy "@$tempPolicyPath" | Out-Null

        # Wait for certificate creation to complete
        Write-LogMessage -Level "INFO" -Message "Waiting for certificate creation to complete..."
        Start-Sleep -Seconds 10

        # Retrieve and save the certificate
        $pemPath = Join-Path -Path $certificateOutputPath -ChildPath "$script:KeyVaultCertificateName.pem"
        $pemSecret = az keyvault secret show `
            --vault-name $script:KeyVaultName `
            --name $script:KeyVaultCertificateName `
            --query "value" -o tsv
            
        if ([string]::IsNullOrWhiteSpace($pemSecret)) {
            throw "Failed to retrieve certificate content from Key Vault"
        }

        $pemSecret | Out-File -Encoding ascii -FilePath $pemPath
        Write-LogMessage -Level "SUCCESS" -Message "Key Vault certificate created and saved to '$pemPath'"
    }
    catch {
        Write-LogMessage -Level "ERROR" -Message "Failed to set Key Vault secret or certificate: $_"
        exit 1
    }
    finally {
        # Clean up temporary files (security best practice)
        if (Test-Path -Path $tempPolicyPath) {
            Remove-Item -Path $tempPolicyPath -Force
            Write-LogMessage -Level "INFO" -Message "Cleaned up temporary certificate policy file"
        }
    }
}

function Set-IdentityAccess {
    <#
    .SYNOPSIS
        Configures managed identity access to Key Vault using Azure CLI.
    .DESCRIPTION
        Uses the managed identity's principal ID and assigns the Key Vault Secrets User role.
    #>
    [CmdletBinding()]
    param()

    Write-LogMessage -Level "INFO" -Message "Configuring managed identity access to Key Vault"
    
    try {
        # Assign role to managed identity
        Write-LogMessage -Level "INFO" -Message "Assigning Key Vault Secrets User role to managed identity"
        az role assignment create `
            --assignee-object-id $script:IdentityPrincipalId `
            --assignee-principal-type ServicePrincipal `
            --role "Key Vault Secrets User" `
            --scope $script:KeyVaultResourceId `
            --output none
        
        Write-LogMessage -Level "SUCCESS" -Message "Managed identity access configured successfully"

        Write-LogMessage -Level "INFO" -Message "Assigning Key Vault Certificate User role to managed identity"
        az role assignment create `
            --assignee-object-id $script:IdentityPrincipalId `
            --assignee-principal-type ServicePrincipal `
            --role "Key Vault Certificate User" `
            --scope $script:KeyVaultResourceId `
            --output none
        
        Write-LogMessage -Level "SUCCESS" -Message "Managed identity access configured successfully"
    }
    catch {
        Write-LogMessage -Level "ERROR" -Message "Failed to configure managed identity access: $_"
        exit 1
    }
}

function Install-CsiDrivers {
    <#
    .SYNOPSIS
        Installs the Secrets Store CSI Driver and Azure Key Vault provider.
    .DESCRIPTION
        Installs both the Secrets Store CSI Driver and the Azure Key Vault provider,
        which are required for accessing Azure Key Vault secrets from pods.
    #>
    [CmdletBinding()]
    param()

    Write-LogMessage -Level "INFO" -Message "Installing Secrets Store CSI Driver and Azure Key Vault provider"
    
    try {
        # Add the Azure Key Vault provider repository
        Write-LogMessage -Level "INFO" -Message "Adding Azure Key Vault provider repository"
        helm repo add csi-secrets-store-provider-azure https://azure.github.io/secrets-store-csi-driver-provider-azure/charts

        # Update Helm repositories
        Write-LogMessage -Level "INFO" -Message "Updating Helm repositories"
        helm repo update

        # Install the Azure Key Vault provider
        helm install azure-csi-provider csi-secrets-store-provider-azure/csi-secrets-store-provider-azure --namespace kube-system
    }
    catch {
        Write-LogMessage -Level "ERROR" -Message "Failed to install Secrets Store CSI Driver or Azure Key Vault provider: $_"
        Write-LogMessage -Level "INFO" -Message "For more troubleshooting, check pod logs: kubectl logs -n kube-system -l app=secrets-store-csi-driver"
        exit 1
    }
}

function Show-Summary {
    <#
    .SYNOPSIS
        Displays setup summary.
    .DESCRIPTION
        Shows a summary of all resources created during the setup process.
    #>
    [CmdletBinding()]
    param()

    Write-LogMessage -Level "SUCCESS" -Message "Setup completed successfully!"
    Write-LogMessage -Level "INFO" -Message "AKS Resources:"
    Write-LogMessage -Level "INFO" -Message "- Resource Group: $script:ResourceGroupName"
    Write-LogMessage -Level "INFO" -Message "- Location: $Location"
    Write-LogMessage -Level "INFO" -Message "- AKS Cluster: $script:ClusterName"
    Write-LogMessage -Level "INFO" -Message "- User-assigned Identity: $script:UserAssignedIdentityName (Client ID: $script:UserAssignedClientId)"
    Write-LogMessage -Level "INFO" -Message "- Kubernetes Service Account: $script:ServiceAccountName"
    Write-LogMessage -Level "INFO" -Message "- Federated Identity Credential: $script:FederatedIdentityCredentialName"

    Write-LogMessage -Level "INFO" -Message "Key Vault Resources:"
    Write-LogMessage -Level "INFO" -Message "- Key Vault Name: $script:KeyVaultName"
    Write-LogMessage -Level "INFO" -Message "- Key Vault URL: $script:KeyVaultUrl"
    Write-LogMessage -Level "INFO" -Message "- Secret Name: $script:KeyVaultSecretName"

    Write-LogMessage -Level "INFO" -Message "To clean up resources, run: az group delete --name $script:ResourceGroupName --yes"
}

#endregion

#region Main Execution
function Start-Deployment {
    <#
    .SYNOPSIS
        Main execution function.
    .DESCRIPTION
        Executes all the steps in sequence to set up AKS with workload identity.
    #>
    [CmdletBinding()]
    param()
    
    Write-LogMessage -Level "INFO" -Message "Starting AKS Workload Identity setup script"
    
    try {
        # Execute steps in sequence
        Initialize-Environment -LocationName $Location
        
        # Create resource group
        New-AzureResourceGroup
        Write-Host "Resource group created: $script:ResourceGroupName"
                
        # Create AKS cluster
        New-AksCluster
        Write-Host "AKS cluster created: $script:ClusterName"
        Write-Host "Press any key to continue..."
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        
        # Create user-assigned managed identity
        New-ManagedIdentity
        Write-Host "User-assigned managed identity created: $script:UserAssignedIdentityName"
                
        # In the Start-Deployment function, add this after Set-AksCredentials
        Set-AksCredentials
        Write-Host "AKS credentials configured"
        Write-Host "Press any key to continue..."
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

        # # Install Secrets Store CSI Driver and Azure Key Vault provider
        # Install-CsiDrivers
        # Write-Host "Secrets Store CSI Driver and Azure Key Vault provider installed"
        # Write-Host "Store CSI Driver and Azure Key Vault provider installed"
                
        # Create Kubernetes service account with workload identity
        New-ServiceAccount
        Write-Host "Kubernetes service account created: $script:ServiceAccountName"
                
        # Create federated identity credential
        New-FederatedIdentity
        Write-Host "Federated identity credential created: $script:FederatedIdentityCredentialName"
        Write-Host "Press any key to continue..."
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        
        # Create Key Vault and configure access
        New-KeyVault
        Write-Host "Key Vault created: $script:KeyVaultName"
        Write-Host "Press any key to continue..."
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        
        # Configure user access to Key Vault
        Set-UserAccess
        Write-Host "User access configured for Key Vault"
        Write-Host "Press any key to continue..."
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        
        # Create a test secret in Key Vault
        New-KeyVaultSecret
        Write-Host "Key Vault secret created: $script:KeyVaultSecretName"
        Write-Host "Press any key to continue..."
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        
        # Configure managed identity access to Key Vault
        Set-IdentityAccess
        Write-Host "Managed identity access configured for Key Vault"
               
        # Show summary of resources created
        Show-Summary
        
        Write-LogMessage -Level "INFO" -Message "Script execution completed"
    }
    catch {
        Write-LogMessage -Level "ERROR" -Message "Deployment failed: $_"
        Clear-ResourcesOnError
        exit 1
    }
}
#endregion

# Script entry point
try {
    # Setup logging
    Initialize-Logging
    
    # Start deployment
    Start-Deployment
}
catch {
    Write-Error "An unexpected error occurred: $_"
    exit 1
}