#!/bin/bash
# Setup Nginx on Server VM
# Run this script on the Server VM as root or with sudo

set -e

VRITTI_DIR="/opt/vritti"
NGINX_CONF_DIR="/etc/nginx"

echo "🔧 Setting up Nginx..."

# Install Nginx if not present
if ! command -v nginx &> /dev/null; then
    echo "Installing Nginx..."
    apt-get update
    apt-get install -y nginx
fi

# Create required directories
echo "Creating directories..."
mkdir -p "$VRITTI_DIR"/{www,ssl}
mkdir -p /var/www/letsencrypt/.well-known/acme-challenge
mkdir -p /var/log/nginx

# Create default index.html
if [ ! -f "$VRITTI_DIR/www/index.html" ]; then
    echo "Creating placeholder index.html..."
    cat > "$VRITTI_DIR/www/index.html" <<'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Vritti - Coming Soon</title>
    <style>
        body { font-family: system-ui, sans-serif; display: flex; justify-content: center; align-items: center; height: 100vh; margin: 0; background: #f5f5f5; }
        .container { text-align: center; }
        h1 { color: #333; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Vritti</h1>
        <p>Application deployment in progress...</p>
    </div>
</body>
</html>
EOF
fi

# Set permissions
echo "Setting permissions..."
chown -R www-data:www-data "$VRITTI_DIR/www"
chmod -R 755 "$VRITTI_DIR/www"

# Enable the site (assuming config file exists)
if [ -f "$NGINX_CONF_DIR/sites-available/cloud.vrittiai.com.conf" ]; then
    echo "Enabling site configuration..."
    ln -sf "$NGINX_CONF_DIR/sites-available/cloud.vrittiai.com.conf" "$NGINX_CONF_DIR/sites-enabled/"

    # Remove default site
    rm -f "$NGINX_CONF_DIR/sites-enabled/default"
fi

# Test and reload Nginx
echo "Testing Nginx configuration..."
nginx -t

echo "Reloading Nginx..."
systemctl reload nginx

echo ""
echo "✅ Nginx setup complete!"
echo ""
echo "📋 Next steps:"
echo "1. Copy the nginx config to the server:"
echo "   scp nginx/sites-available/cloud.vrittiai.com.conf root@<server-ip>:$NGINX_CONF_DIR/sites-available/"
echo ""
echo "2. Setup SSL certificates (using Let's Encrypt):"
echo "   apt-get install certbot python3-certbot-nginx"
echo "   certbot --nginx -d cloud.vrittiai.com"
echo ""
echo "3. Or copy existing SSL certificates to:"
echo "   $VRITTI_DIR/ssl/cloud.vrittiai.com.crt"
echo "   $VRITTI_DIR/ssl/cloud.vrittiai.com.key"
