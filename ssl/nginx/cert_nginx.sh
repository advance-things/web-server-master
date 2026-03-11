#!/usr/bin/env bash

set -e

domain=""
use_www=false

# -----------------------------
# Parse arguments
# -----------------------------
for arg in "$@"; do
  case $arg in
    --www)
      use_www=true
      ;;
    *)
      domain=$arg
      ;;
  esac
done

if [ -z "$domain" ]; then
  read -p "Enter domain name: " domain
fi

webroot="/var/www/$domain"
nginx_available="/etc/nginx/conf.d/$domain.conf"

echo "Deploying: $domain"

# -----------------------------
# Install packages
# -----------------------------
install_pkgs() {

if command -v apt-get >/dev/null 2>&1; then
  apt-get update
  apt-get install -y nginx certbot python3-certbot-nginx cron

elif command -v dnf >/dev/null 2>&1; then
  dnf install -y nginx certbot python3-certbot-nginx cronie

elif command -v yum >/dev/null 2>&1; then
  yum install -y nginx certbot python3-certbot-nginx cronie
fi

}

install_pkgs

# -----------------------------
# Create web root
# -----------------------------
mkdir -p "$webroot"

if [ ! -f "$webroot/index.html" ]; then
cat > "$webroot/index.html" <<EOF
<html>
<head>
<title>$domain</title>
</head>
<body>
<h1>$domain deployed successfully</h1>
</body>
</html>
EOF
fi

# -----------------------------
# Domain logic
# -----------------------------
server_names="$domain"
cert_domains="-d $domain"

if $use_www; then
  server_names="$domain www.$domain"
  cert_domains="-d $domain -d www.$domain"
fi

# -----------------------------
# NGINX CONFIG
# -----------------------------
cat > "$nginx_available" <<EOF
server {

    listen 80;
    listen [::]:80;

    server_name $server_names;

    root $webroot;
    index index.html;

    # -----------------
    # Security headers
    # -----------------
    add_header X-Frame-Options SAMEORIGIN;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";

    # -----------------
    # Gzip
    # -----------------
    gzip on;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml text/javascript;

    # -----------------
    # HTML (no cache)
    # -----------------
    location ~* \.html$ {
        expires -1;
        add_header Cache-Control "no-store, no-cache, must-revalidate";
    }

    # -----------------
    # JS / CSS
    # -----------------
    location ~* \.(js|css)$ {
        expires 7d;
        add_header Cache-Control "public, immutable";
    }

    # -----------------
    # Images
    # -----------------
    location ~* \.(jpg|jpeg|png|gif|ico|svg|webp|avif)$ {
        expires 30d;
        add_header Cache-Control "public";
    }

    # -----------------
    # Video
    # -----------------
    location ~* \.(mp4|webm|ogg|mov|avi|mkv)$ {
        expires 30d;
        add_header Cache-Control "public";
        add_header Accept-Ranges bytes;
    }

    # -----------------
    # React SPA fallback
    # -----------------
    location / {
        try_files \$uri \$uri/ /index.html;
    }

}
EOF

# -----------------------------
# Test and reload nginx
# -----------------------------
nginx -t
nginx -s reload

# -----------------------------
# Request SSL
# -----------------------------
echo "Requesting SSL..."

certbot --nginx $cert_domains --non-interactive --agree-tos -m admin@$domain || true

# -----------------------------
# Cron for renewal
# -----------------------------
(crontab -l 2>/dev/null | grep -v certbot; echo "0 3 * * * certbot renew --quiet --deploy-hook 'nginx -s reload'") | crontab -

echo ""
echo "----------------------------------"
echo "Deployment completed"
echo "https://$domain"
if $use_www; then
  echo "https://www.$domain"
fi
echo "----------------------------------"
