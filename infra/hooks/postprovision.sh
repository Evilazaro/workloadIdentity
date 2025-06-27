#!/bin/bash

# Variables - update these as needed
KEYVAULT_NAME=$1
CERT_NAME="my-cert-demo"
SUBJECT="CN=example.com"
POLICY_FILE="cert-policy.json"

# Create a certificate policy file if it doesn't exist
cat <<EOF > $POLICY_FILE
{
  "issuerParameters": {
    "name": "Self"
  },
  "x509CertificateProperties": {
    "subject": "CN=mydomain.com",
    "validityInMonths": 12,
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
EOF

# Create the certificate in the Key Vault
az keyvault certificate create \
  --vault-name "$KEYVAULT_NAME" \
  --name "$CERT_NAME" \
  --policy @"$POLICY_FILE"

echo "Certificate '$CERT_NAME' created in Key Vault '$KEYVAULT_NAME'."

pemSecret = az keyvault secret show \
            --vault-name "$KEYVAULT_NAME" \
            --name "$CERT_NAME" \
            --query "value" -o tsv

echo "AZURE_PEM_SECRET=\"$pemSecret\"" >> "$ENV_FILE"