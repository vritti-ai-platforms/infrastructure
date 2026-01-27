#!/bin/bash
# Setup ubuntu user for GitHub Actions CI/CD
# Run this script on the Server VM as root or with sudo

set -e

DEPLOY_USER="ubuntu"
VRITTI_DIR="/opt/vritti"

echo "🔧 Setting up $DEPLOY_USER user for CI/CD..."

# Add ubuntu user to docker group
echo "Adding $DEPLOY_USER to docker group..."
usermod -aG docker "$DEPLOY_USER"

# Create vritti directory structure
echo "Creating directory structure..."
mkdir -p "$VRITTI_DIR"/{www,logs,backups/www,ssl}

# Set ownership
echo "Setting ownership..."
chown -R "$DEPLOY_USER:$DEPLOY_USER" "$VRITTI_DIR"

echo ""
echo "✅ Setup complete!"
echo ""
echo "📋 Directory structure created:"
ls -la "$VRITTI_DIR"