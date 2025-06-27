#!/bin/bash

set -e

# Set version and directories
KUBELOGIN_VERSION="v0.1.2"
INSTALL_DIR="/usr/local/bin"
TMP_DIR="$HOME/tools/kubelogin-install"

echo "🔧 Creating temp directory..."
rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR"
cd "$TMP_DIR"

echo "🌐 Downloading kubelogin ${KUBELOGIN_VERSION}..."
curl -LO "https://github.com/Azure/kubelogin/releases/download/${KUBELOGIN_VERSION}/kubelogin-linux-amd64.zip"

echo "📦 Installing unzip if not present..."
sudo apt update && sudo apt install -y unzip

echo "📂 Extracting kubelogin..."
unzip kubelogin-linux-amd64.zip

# Updated path based on new structure
KUBELOGIN_BIN="bin/linux_amd64/kubelogin"

if [[ -f "$KUBELOGIN_BIN" ]]; then
    echo "✅ Setting executable permission..."
    chmod +x "$KUBELOGIN_BIN"

    echo "🚀 Moving binary to ${INSTALL_DIR}..."
    sudo mv "$KUBELOGIN_BIN" "${INSTALL_DIR}/kubelogin"

    echo "🧹 Cleaning up..."
    cd ~
    rm -rf "$TMP_DIR"

    echo "🔍 Verifying installation..."
    if command -v kubelogin >/dev/null 2>&1; then
        kubelogin --version
        echo "✅ kubelogin installed successfully!"
    else
        echo "❌ kubelogin installation failed (not in PATH)."
        exit 1
    fi
else
    echo "❌ Error: kubelogin binary not found after unzip. Check ZIP contents or version."
    exit 1
fi
