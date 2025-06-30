# Azure Container Registry (ACR) Integration with AKS

This guide explains how to attach and use Azure Container Registry with your AKS cluster in this workload identity setup.

## Overview

The Bicep templates in this repository automatically:
1. Create an Azure Container Registry (ACR)
2. Create an AKS cluster with workload identity enabled
3. Grant the AKS cluster permissions to pull images from ACR
4. Configure the necessary role assignments

## Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Developer     │    │      ACR        │    │      AKS        │
│                 │    │                 │    │                 │
│ docker build    │───▶│ Store Images    │───▶│ Pull & Deploy   │
│ docker push     │    │                 │    │                 │
└─────────────────┘    └─────────────────┘    └─────────────────┘
                              │                        │
                              ▼                        ▼
                    ┌─────────────────┐    ┌─────────────────┐
                    │   Managed       │    │   Workload      │
                    │   Identity      │    │   Identity      │
                    │   (AcrPull)     │    │   Service       │
                    │                 │    │   Account       │
                    └─────────────────┘    └─────────────────┘
```

## How It Works

### 1. ACR Configuration

The ACR is configured with:
- **System-assigned managed identity** for secure authentication
- **Standard SKU** (configurable to Premium for advanced features)
- **Security policies** including quarantine and retention policies
- **Diagnostic logging** integration with Log Analytics

### 2. AKS-ACR Integration

The integration works through:
- **Role Assignment**: AKS cluster's system-assigned managed identity gets `AcrPull` role on the ACR
- **Automatic Authentication**: AKS nodes can pull images without additional configuration
- **Workload Identity**: Applications can use managed identities for secure service-to-service communication

### 3. Key Components

#### Bicep Files:
- `infra/workload/acr.bicep` - ACR resource definition with security best practices
- `infra/workload/aks.bicep` - AKS cluster with ACR integration parameters
- `infra/modules/workload.bicep` - Orchestrates ACR and AKS deployment

#### Key Features:
- **Secure by default**: No admin user or anonymous pull access
- **Monitoring**: Diagnostic settings enabled for both ACR and AKS
- **Zone redundancy**: Available for Premium SKU
- **Content trust**: Support for signed images (Premium SKU)

## Usage Examples

### 1. Build and Push Images to ACR

```bash
# Get ACR login server from deployment outputs
ACR_NAME=$(azd env get-values --output json | jq -r .AZURE_CONTAINER_REGISTRY_NAME)
ACR_LOGIN_SERVER=$(azd env get-values --output json | jq -r .AZURE_CONTAINER_REGISTRY_LOGIN_SERVER)

# Login to ACR
az acr login --name $ACR_NAME

# Build and tag your image
docker build -t $ACR_LOGIN_SERVER/myapp:v1.0.0 .

# Push to ACR
docker push $ACR_LOGIN_SERVER/myapp:v1.0.0
```

### 2. Deploy Applications Using ACR Images

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
spec:
  replicas: 3
  selector:
    matchLabels:
      app: myapp
  template:
    metadata:
      labels:
        app: myapp
    spec:
      serviceAccountName: workload-identity-sa
      containers:
      - name: myapp
        image: <your-acr>.azurecr.io/myapp:v1.0.0
        ports:
        - containerPort: 80
```

### 3. Using Workload Identity with ACR

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: workload-identity-sa
  annotations:
    azure.workload.identity/client-id: "<managed-identity-client-id>"
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: secure-app
spec:
  template:
    spec:
      serviceAccountName: workload-identity-sa
      containers:
      - name: app
        image: <your-acr>.azurecr.io/secure-app:latest
        # This container can now authenticate to Azure services
        # using the workload identity without storing credentials
```

## Security Best Practices

### 1. Network Security
- **Private endpoints**: Use private endpoints for ACR in production
- **Network policies**: Implement Kubernetes network policies
- **IP restrictions**: Configure authorized IP ranges for ACR access

### 2. Image Security
- **Vulnerability scanning**: Enable Azure Defender for container registries
- **Content trust**: Use signed images (Premium SKU)
- **Retention policies**: Configure automatic cleanup of old images

### 3. Access Control
- **Least privilege**: Use role-based access control (RBAC)
- **Workload identity**: Prefer workload identity over service principal
- **Regular audits**: Monitor access logs and permissions

## Configuration Options

### ACR SKU Comparison

| Feature | Basic | Standard | Premium |
|---------|-------|----------|---------|
| Storage | 10 GB | 100 GB | 500 GB |
| Webhooks | ❌ | ✅ | ✅ |
| Geo-replication | ❌ | ❌ | ✅ |
| Content trust | ❌ | ❌ | ✅ |
| Private endpoints | ❌ | ❌ | ✅ |
| Zone redundancy | ❌ | ❌ | ✅ |

### Customization Parameters

In your Bicep parameters, you can customize:

```bicep
// ACR Configuration
param acrSku string = 'Standard'  // Basic, Standard, Premium
param enableZoneRedundancy bool = false  // Premium only
param enableContentTrust bool = false    // Premium only
param retentionDays int = 7              // Image retention policy

// AKS-ACR Integration
param enableAcrIntegration bool = true   // Enable/disable integration
```

## Troubleshooting

### Common Issues

1. **Image pull errors**
   ```bash
   # Check role assignments
   az role assignment list --assignee <aks-managed-identity-id> --scope <acr-resource-id>
   
   # Verify AKS can access ACR
   kubectl get events --field-selector reason=Failed
   ```

2. **Authentication issues**
   ```bash
   # Test ACR connectivity from AKS
   kubectl run test-pod --image=<acr-login-server>/hello-world:latest --rm -it
   ```

3. **Workload identity problems**
   ```bash
   # Check service account annotations
   kubectl describe sa workload-identity-sa
   
   # Verify OIDC issuer configuration
   kubectl get pod <pod-name> -o yaml | grep -A 10 serviceAccount
   ```

### Monitoring and Logs

- **ACR logs**: Check Azure Monitor for registry operations
- **AKS logs**: Use kubectl and Azure Monitor for cluster events
- **Application logs**: Implement structured logging in your applications

## Cost Optimization

1. **Right-size ACR SKU**: Start with Standard, upgrade to Premium when needed
2. **Image cleanup**: Use retention policies to remove old images
3. **Compression**: Use multi-stage Docker builds to reduce image size
4. **Monitoring**: Set up cost alerts for ACR storage and data transfer

## Next Steps

1. **Set up CI/CD**: Integrate with Azure DevOps or GitHub Actions
2. **Implement scanning**: Enable vulnerability scanning for images
3. **Configure networking**: Set up private endpoints for production
4. **Monitoring**: Set up comprehensive monitoring and alerting

For more detailed examples, see the `examples/` directory in this repository.
