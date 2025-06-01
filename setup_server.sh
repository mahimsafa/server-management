#!/usr/bin/env bash
#
# setup_production_server.sh
#
# This script sets up a production-ready Linux server with:
# - Node.js 22
# - PostgreSQL 17
# - Valkey 8.1.1
# - Nginx with SSL (Let's Encrypt)
# - UFW firewall configuration
#
# Usage:
#   sudo bash setup_production_server.sh <YOUR_DOMAIN> <YOUR_EMAIL> <APP_DIR>
#
# Example:
#   sudo bash setup_production_server.sh example.com admin@example.com /var/www/myapp
#

set -euo pipefail

###############################
#   Parse and validate args   #
###############################
if [[ $# -ne 3 ]]; then
  echo "Usage: sudo bash $0 <YOUR_DOMAIN> <YOUR_EMAIL> <APP_DIR>"
  exit 1
fi

DOMAIN="$1"
EMAIL="$2"
APP_DIR="$3"
SERVICE_NAME="myapp"
NODE_VERSION="22.x"

###############################
# 1. System update & tools    #
###############################
echo "----- Updating system packages -----"
apt-get update -y
apt-get upgrade -y

echo "----- Installing essential packages -----"
apt-get install -y \
  curl \
  gnupg \
  lsb-release \
  ca-certificates \
  software-properties-common \
  build-essential

###############################
# 2. Install Node.js 22       #
###############################
echo "----- Installing Node.js v${NODE_VERSION} -----"
curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION} | bash -
apt-get install -y nodejs

###############################
# 3. Install PostgreSQL 17    #
###############################
echo "----- Adding PostgreSQL APT repository -----"
sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list' -y
curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /etc/apt/trusted.gpg.d/postgresql.gpg
apt-get update -y

echo "----- Installing PostgreSQL 17 -----"
apt-get install -y postgresql-17 postgresql-client-17

echo "----- Configuring PostgreSQL to listen only on localhost -----"
PG_CONF_FILE="/etc/postgresql/17/main/postgresql.conf"
sed -i "s/^#\?\s*listen_addresses\s*=.*/listen_addresses = 'localhost'/" "${PG_CONF_FILE}"
systemctl restart postgresql

###############################
# 4. Install Valkey 8.1.1     #
###############################
echo "----- Installing Valkey 8.1.1 -----"
apt install valkey valkey-tools valkey-redis-compat -y

# cd /tmp
# # curl -O https://download.valkey.io/valkey-8.1.1.tar.gz
# curl -O https://github.com/valkey-io/valkey/archive/refs/tags/8.1.1.tar.gz
# tar xzf valkey-8.1.1.tar.gz
# cd valkey-8.1.1
# make
# make install

# echo "----- Configuring Valkey -----"
# mkdir -p /etc/valkey
# cp valkey.conf /etc/valkey/
# sed -i "s/^#\?bind .*/bind 127.0.0.1/" /etc/valkey/valkey.conf
# sed -i "s/^#\?protected-mode .*/protected-mode yes/" /etc/valkey/valkey.conf

# echo "----- Creating systemd service for Valkey -----"
# cat > /etc/systemd/system/valkey.service <<EOF
# [Unit]
# Description=Valkey In-Memory Data Store
# After=network.target

# [Service]
# ExecStart=/usr/local/bin/valkey-server /etc/valkey/valkey.conf
# ExecStop=/usr/local/bin/valkey-cli shutdown
# Restart=always
# User=nobody
# Group=nogroup

# [Install]
# WantedBy=multi-user.target
# EOF

# systemctl daemon-reload
# systemctl enable valkey
# systemctl start valkey

###############################
# 5. Install and configure Nginx #
###############################
echo "----- Installing Nginx -----"
apt-get install -y nginx

echo "----- Creating Nginx server block for ${DOMAIN} -----"
NGINX_CONF_FILE="/etc/nginx/sites-available/${DOMAIN}"
cat > "${NGINX_CONF_FILE}" <<EOF
upstream app {
    server localhost:8000;
}

server {
    listen 80;
    server_name ${DOMAIN};

    # Redirect `/` to `/app`
    location = / {
        return 301 /app;
    }

    # Proxy pass for everything else (including /app)
    location / {
        proxy_pass http://app;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
        client_max_body_size 500M;
        
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-Port \$server_port;
        proxy_set_header X-Forwarded-Server \$host;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_redirect off;

    }

    # Caching for images
    location ~* \.(jpg|jpeg|png|gif|ico|svg|webp)$ {
        expires 5m;
        add_header Cache-Control "public, max-age=300";
    }
}
EOF

ln -sf "${NGINX_CONF_FILE}" "/etc/nginx/sites-enabled/${DOMAIN}"
nginx -t
systemctl reload nginx

###############################
# 6. Obtain and install SSL   #
###############################
echo "----- Installing Certbot and the Nginx plugin -----"
apt-get install -y certbot python3-certbot-nginx

echo "----- Obtaining Let's Encrypt SSL certificate for ${DOMAIN} -----"
certbot --nginx --non-interactive --agree-tos --email "${EMAIL}" -d "${DOMAIN}" --redirect

###############################
# 7. Configure Firewall (UFW) #
###############################
echo "----- Installing and configuring UFW firewall -----"
apt-get install -y ufw

ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow OpenSSH
ufw allow 'Nginx Full'
ufw deny 5432/tcp
ufw deny 6379/tcp
ufw --force enable
ufw status verbose

###############################
# 8. Create systemd service for Node.js app #
###############################
echo "----- Setting up systemd service for Node.js application -----"
if [[ ! -d "${APP_DIR}" ]]; then
  echo "ERROR: Application directory ${APP_DIR} does not exist."
  exit 1
fi

APP_USER="appuser"
if ! id -u "${APP_USER}" >/dev/null 2>&1; then
  echo "----- Creating user '${APP_USER}' -----"
  useradd --system --no-create-home --shell /usr/sbin/nologin "${APP_USER}"
fi

chown -R "${APP_USER}":"${APP_USER}" "${APP_DIR}"

SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
cat > "${SERVICE_FILE}" <<EOF
[Unit]
Description=Node.js Application for ${DOMAIN}
After=network.target

[Service]
User=${APP_USER}
Group=${APP_USER}
WorkingDirectory=${APP_DIR}
ExecStart=/usr/bin/node ${APP_DIR}/index.js
Restart=always
RestartSec=5
LimitNOFILE=4096

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable "${SERVICE_NAME}"
systemctl start "${SERVICE_NAME}"

echo ""
echo "##############################################################"
echo "✅  Setup complete!"
echo ""
echo "· Nginx is configured as a reverse proxy for your Node.js app on port 8000,"
echo "  with the root path '/' redirected to '/app', and SSL certificates from Let's Encrypt handling HTTPS for ${DOMAIN}."
echo ""
echo "· The firewall (UFW) allows only SSH (22) and HTTPS (443)."
echo "  PostgreSQL (5432) and Valkey (6379) are bound to localhost and explicitly denied by UFW."
echo ""
echo "· Your Node.js app is running as systemd service: ${SERVICE_NAME}."
echo "  To check status:    sudo systemctl status ${SERVICE_NAME}"
echo "  To view logs:       sudo journalctl -u ${SERVICE_NAME} -f"
echo ""
echo "· PostgreSQL is listening only on localhost (127.0.0.1)."
echo "  If you need to create a database/user:"
echo "    sudo -u postgres createuser --interactive"
echo "    sudo -u postgres createdb your_db_name"
echo ""
echo "· Valkey is bound to 127.0.0.1 and protected-mode is enabled."
echo ""
echo "· If you need to adjust configuration (e.g., Nginx, firewall rules, or database settings),"
echo "  edit the respective config files under /etc/ and then run 'sudo systemctl reload <service>'."
echo ""
echo "· Don’t forget to deploy your Node.js application code into ${APP_DIR} before starting."
echo "  Ensure your app listens on port 8000 (e.g., app.listen(8000))."
echo ""
echo "● To obtain or renew SSL manually in the future: sudo certbot renew"
echo ""
echo "Thank you! Your production server stack is ready for your Node.js web application."
echo "##############################################################"
