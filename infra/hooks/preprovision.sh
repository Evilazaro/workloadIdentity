#!/bin/bash

set -e

KEY_DIR=".ssh"
KEY_FILE="${KEY_DIR}/id_rsa"
AZURE_ENV_NAME="${1:-}"
readonly ENV_FILE="./.azure/${AZURE_ENV_NAME}/.env"

mkdir -p "$KEY_DIR"

if [ ! -f "$KEY_FILE.pub" ]; then
  echo "[azd hook] Generating SSH key pair..."
  ssh-keygen -t rsa -b 4096 -f "$KEY_FILE" -N "" -q
else
  echo "[azd hook] SSH key already exists."
fi

SSH_PUBLIC_KEY=$(cat "$KEY_FILE.pub")

# Add to .env only if not already present
if ! grep -q "SSH_PUBLIC_KEY" "$ENV_FILE"; then
  echo "SSH_PUBLIC_KEY=\"$SSH_PUBLIC_KEY\"" >> "$ENV_FILE"
  echo "[azd hook] Added SSH_PUBLIC_KEY to $ENV_FILE"
else
  echo "[azd hook] SSH_PUBLIC_KEY already present in $ENV_FILE"
fi
