#!/bin/bash
# Setup deploy user for GitHub Actions CI/CD
# Run this script on the Server VM as root or with sudo

set -e

DEPLOY_USER="deploy"
VRITTI_DIR="/opt/vritti"

echo "🔧 Setting up deploy user for CI/CD..."

# Create deploy user if it doesn't exist
if ! id "$DEPLOY_USER" &>/dev/null; then
    echo "Creating user: $DEPLOY_USER"
    adduser "$DEPLOY_USER" --disabled-password --gecos ""
else
    echo "User $DEPLOY_USER already exists"
fi

# Add deploy user to docker group
echo "Adding $DEPLOY_USER to docker group..."
usermod -aG docker "$DEPLOY_USER"

# Create vritti directory structure
echo "Creating directory structure..."
mkdir -p "$VRITTI_DIR"/{www,logs,backups/www,ssl}

# Set ownership
echo "Setting ownership..."
chown -R "$DEPLOY_USER:$DEPLOY_USER" "$VRITTI_DIR"

# Setup SSH directory for deploy user
echo "Setting up SSH..."
DEPLOY_HOME="/home/$DEPLOY_USER"
mkdir -p "$DEPLOY_HOME/.ssh"
chmod 700 "$DEPLOY_HOME/.ssh"
touch "$DEPLOY_HOME/.ssh/authorized_keys"
chmod 600 "$DEPLOY_HOME/.ssh/authorized_keys"
chown -R "$DEPLOY_USER:$DEPLOY_USER" "$DEPLOY_HOME/.ssh"

echo ""
echo "✅ Deploy user setup complete!"
echo ""
echo "📋 Next steps:"
echo "1. Generate SSH key on your local machine:"
echo "   ssh-keygen -t ed25519 -C \"github-actions-deploy\" -f ~/.ssh/vritti-deploy -N \"\""
echo ""
echo "2. Add the public key to the deploy user:"
echo "   cat ~/.ssh/vritti-deploy.pub | ssh root@<server-ip> 'cat >> /home/$DEPLOY_USER/.ssh/authorized_keys'"
echo ""
echo "3. Add the private key to GitHub Secrets as SERVER_VM_SSH_KEY:"
echo "   cat ~/.ssh/vritti-deploy"
echo ""
echo "4. Copy docker-compose.yml and .env to $VRITTI_DIR:"
echo "   scp docker-compose.yml .env deploy@<server-ip>:$VRITTI_DIR/"
echo ""
echo "5. Pre-login to GHCR on the server:"
echo "   ssh deploy@<server-ip> 'docker login ghcr.io -u YOUR_GITHUB_USER'"
