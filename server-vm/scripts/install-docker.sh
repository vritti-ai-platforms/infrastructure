#!/bin/bash
# Install Docker and Docker Compose on Server VM
# Run this script on the Server VM as root or with sudo
# This script is idempotent - safe to run multiple times

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]  ${1}${NC}"
}

log_success() {
    echo -e "${GREEN}[OK] ${1}${NC}"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]  ${1}${NC}"
}

log_error() {
    echo -e "${RED}[ERROR] ${1}${NC}"
}

echo ""
log_info "[DOCKER] Docker Installation Script"
echo ""

# Check if Docker is already installed
if command -v docker &> /dev/null; then
    DOCKER_VERSION=$(docker --version)
    log_warning "Docker is already installed: ${DOCKER_VERSION}"

    # Check if Docker is running
    if systemctl is-active --quiet docker; then
        log_success "Docker service is running"
    else
        log_warning "Docker service is not running, starting it..."
        systemctl start docker
        systemctl enable docker
        log_success "Docker service started"
    fi

    # Check if docker-compose plugin is installed
    if docker compose version &> /dev/null; then
        COMPOSE_VERSION=$(docker compose version)
        log_success "Docker Compose is installed: ${COMPOSE_VERSION}"
        echo ""
        log_success "Docker is already configured and running. Nothing to do."
        exit 0
    else
        log_warning "Docker Compose plugin not found, installing..."
    fi
else
    log_info "Docker not found, proceeding with installation..."
fi

# Remove old versions
log_info "Removing old Docker versions (if any)..."
apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true

# Install prerequisites
log_info "Installing prerequisites..."
apt-get update
apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release

# Add Docker's official GPG key
log_info "Adding Docker GPG key..."
mkdir -p /etc/apt/keyrings
if [ ! -f /etc/apt/keyrings/docker.gpg ]; then
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    log_success "GPG key added"
else
    log_warning "GPG key already exists, skipping"
fi

# Set up the repository
log_info "Setting up Docker repository..."
if [ ! -f /etc/apt/sources.list.d/docker.list ]; then
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    log_success "Repository added"
else
    log_warning "Repository already configured, skipping"
fi

# Install Docker Engine
log_info "Installing Docker Engine and components..."
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Start and enable Docker
log_info "Starting Docker service..."
systemctl start docker
systemctl enable docker

# Verify installation
echo ""
log_info "[CHECK] Verifying installation..."
DOCKER_VERSION=$(docker --version)
COMPOSE_VERSION=$(docker compose version)

log_success "Docker installed: ${DOCKER_VERSION}"
log_success "Docker Compose installed: ${COMPOSE_VERSION}"

# Check Docker service status
if systemctl is-active --quiet docker; then
    log_success "Docker service is active and running"
else
    log_error "Docker service is not running"
    exit 1
fi

# Test Docker with hello-world (optional, commented out to avoid unnecessary pulls)
# log_info "Testing Docker with hello-world..."
# docker run --rm hello-world > /dev/null 2>&1 && log_success "Docker test successful" || log_warning "Docker test failed"

echo ""
log_success "[OK] Docker installation complete!"
echo ""
log_info " Post-installation steps:"
echo "  1. Add users to docker group: usermod -aG docker <username>"
echo "  2. Log out and back in for group changes to take effect"
echo "  3. Test: docker run --rm hello-world"
echo ""
