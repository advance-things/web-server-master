#!/bin/bash

# Get domain name from command line argument or prompt
if [ -z "$1" ]; then
  read -p "Enter domain name: " domain
else
  domain=$1
fi

# Install Nginx and Certbot
if command -v apt-get >/dev/null 2>&1; then
  sudo apt-get update
  sudo apt-get install -y nginx certbot python3-certbot-nginx
elif command -v dnf >/dev/null 2>&1; then
  sudo dnf install -y nginx certbot python3-certbot-nginx
elif command -v yum >/dev/null 2>&1; then
  sudo yum install -y nginx certbot python3-certbot-nginx
else
  echo "Unsupported package manager. Install Nginx and Certbot manually."
  exit 1
fi

# Create NGINX server block
cat > /etc/nginx/sites-available/$domain << EOF
server {
  listen 80;
  listen [::]:80;
  server_name $domain www.$domain;

  root /servers/frontend/$domain;
  index index.html index.htm;

  # Security Headers
  add_header X-Content-Type-Options nosniff;
  add_header X-Frame-Options DENY;
  add_header X-XSS-Protection "1; mode=block";
  add_header Referrer-Policy "strict-origin-when-cross-origin";
  add_header Permissions-Policy "geolocation=(), microphone=()";
  add_header Content-Security-Policy "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; object-src 'none'; base-uri 'self';";

  # Browser Caching
  location ~* \.(jpg|jpeg|png|gif|ico|css|js|woff2?|ttf|svg)$ {
    expires 30d;
    add_header Cache-Control "public, immutable";
  }

  location / {
    try_files \$uri \$uri/ =404;
  }
}
EOF

# Create default HTML page if not exists
if [ ! -f /servers/frontend/$domain/index.html ]; then
  mkdir -p /servers/frontend/$domain
  cat > /servers/frontend/$domain/index.html << EOF
<html>
<head>
  <title>Welcome to $domain!</title>
</head>
<body>
  <h1>Success! The $domain server block is working!</h1>
</body>
</html>
EOF
fi

# Enable the site
if [ ! -f /etc/nginx/sites-enabled/$domain ]; then
  sudo ln -s /etc/nginx/sites-available/$domain /etc/nginx/sites-enabled/
fi

# Test and reload NGINX
sudo nginx -t && sudo systemctl reload nginx

# Obtain SSL certificate
if [ -z "$2" ]; then
  sudo certbot --nginx -d $domain -d www.$domain
else
  sudo certbot --nginx --register-unsafely-without-email -d $domain -d www.$domain
fi

# Cron job to auto-renew SSL (runs every 12 hours, logs quietly)
(crontab -l 2>/dev/null | grep -v "certbot renew --quiet" ; echo "0 */12 * * * certbot renew --quiet --post-hook 'systemctl reload nginx'") | crontab -

# Enable gzip compression if not already
sudo sed -i 's/#gzip /gzip /g' /etc/nginx/nginx.conf
sudo sed -i 's/#gzip_/gzip_/g' /etc/nginx/nginx.conf

# Clear and restart NGINX
sudo rm -rf /var/cache/nginx/*
sudo systemctl restart nginx

echo "✅ NGINX setup complete for $domain with performance & security enhancements."
