#!/bin/bash
# Setup ubuntu user for GitHub Actions CI/CD
# Run this script on the Server VM as root or with sudo
# This script is idempotent - safe to run multiple times

set -e

DEPLOY_USER="ubuntu"
VRITTI_DIR="/opt/vritti"

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
log_info "[CONFIG] Deploy User Setup Script"
echo ""

# Check if deploy user exists
if ! id "$DEPLOY_USER" &>/dev/null; then
    log_error "User '$DEPLOY_USER' does not exist. Please create the user first."
    exit 1
fi

log_success "User '$DEPLOY_USER' exists"

# Check if docker group exists
if ! getent group docker &>/dev/null; then
    log_error "Docker group does not exist. Please install Docker first."
    log_info "Run: ./install-docker.sh"
    exit 1
fi

log_success "Docker group exists"

# Add ubuntu user to docker group
log_info "Checking docker group membership..."
if id -nG "$DEPLOY_USER" | grep -qw "docker"; then
    log_warning "User '$DEPLOY_USER' is already in docker group"
else
    log_info "Adding '$DEPLOY_USER' to docker group..."
    usermod -aG docker "$DEPLOY_USER"
    log_success "User '$DEPLOY_USER' added to docker group"
fi

# Create vritti directory structure
log_info "Creating directory structure..."

declare -a DIRS=(
    "$VRITTI_DIR"
    "$VRITTI_DIR/www"
    "$VRITTI_DIR/logs"
    "$VRITTI_DIR/logs/nginx"
    "$VRITTI_DIR/logs/api"
    "$VRITTI_DIR/backups"
    "$VRITTI_DIR/backups/www"
    "$VRITTI_DIR/ssl"
)

for dir in "${DIRS[@]}"; do
    if [ -d "$dir" ]; then
        log_warning "Directory already exists: $dir"
    else
        mkdir -p "$dir"
        log_success "Created directory: $dir"
    fi
done

# Set ownership
log_info "Setting ownership and permissions..."
chown -R "$DEPLOY_USER:$DEPLOY_USER" "$VRITTI_DIR"
chmod 755 "$VRITTI_DIR"
chmod 755 "$VRITTI_DIR/ssl"  # Allow nginx container to read SSL certificates
chmod 777 "$VRITTI_DIR/logs/nginx"  # Allow nginx container to write logs
log_success "Ownership and permissions set"

# Create placeholder index.html if it doesn't exist
if [ ! -f "$VRITTI_DIR/www/index.html" ]; then
    log_info "Creating placeholder index.html..."
    cat > "$VRITTI_DIR/www/index.html" <<'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Vritti - Coming Soon</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, sans-serif;
            display: flex;
            justify-content: center;
            align-items: center;
            min-height: 100vh;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
        }
        .container {
            text-align: center;
            padding: 2rem;
        }
        h1 {
            font-size: 3rem;
            margin-bottom: 1rem;
            font-weight: 700;
        }
        p {
            font-size: 1.25rem;
            opacity: 0.9;
        }
        .status {
            margin-top: 2rem;
            padding: 1rem;
            background: rgba(255, 255, 255, 0.1);
            border-radius: 8px;
            backdrop-filter: blur(10px);
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>Vritti</h1>
        <p>Application deployment in progress...</p>
        <div class="status">
            <p>Server infrastructure is ready</p>
            <p>Waiting for application deployment</p>
        </div>
    </div>
</body>
</html>
EOF
    chown "$DEPLOY_USER:$DEPLOY_USER" "$VRITTI_DIR/www/index.html"
    log_success "Placeholder index.html created"
else
    log_warning "index.html already exists, skipping"
fi

echo ""
log_success "[OK] Deploy user setup complete!"
echo ""
log_info " Directory structure:"
ls -la "$VRITTI_DIR"
echo ""
log_info " Next steps:"
echo "  1. Upload SSL certificates to: $VRITTI_DIR/ssl/"
echo "  2. Deploy docker-compose.yml to: $VRITTI_DIR/"
echo "  3. Create .env file with secrets"
echo "  4. Run: cd $VRITTI_DIR && docker compose up -d"
echo ""