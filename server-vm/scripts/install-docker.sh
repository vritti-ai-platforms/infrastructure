#!/bin/bash
# Install Docker and Docker Compose on Server VM
# Run this script on the Server VM as root or with sudo

set -e

echo "🐳 Installing Docker..."

# Remove old versions
apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true

# Install prerequisites
apt-get update
apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release

# Add Docker's official GPG key
mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg

# Set up the repository
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker Engine
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Start and enable Docker
systemctl start docker
systemctl enable docker

# Verify installation
echo ""
echo "🔍 Verifying installation..."
docker --version
docker compose version

echo ""
echo "✅ Docker installation complete!"
echo ""
echo "📋 Post-installation:"
echo "1. Add users to docker group: usermod -aG docker <username>"
echo "2. Log out and back in for group changes to take effect"
