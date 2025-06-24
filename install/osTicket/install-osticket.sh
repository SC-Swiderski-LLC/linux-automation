#!/bin/bash

set -e

# Variables
DB_NAME="osticket"
DB_USER="osticketuser"
DB_PASS=$(openssl rand -base64 20)
DOMAIN="help.scswiderski.net"
ADMIN_EMAIL="it@scswiderski.com"
APACHE_CONF="/etc/apache2/sites-available/osticket.conf"
# Use official osTicket repository and latest release
OSTICKET_REPO="https://github.com/osTicket/osTicket.git"
OSTICKET_VERSION="v1.18.2"  # Latest stable release

WEB_ROOT="/var/www/html/osticket"

# Update and install dependencies
sudo apt update && sudo apt upgrade -y
sudo apt install -y software-properties-common apt-transport-https ca-certificates curl wget unzip apache2 mariadb-server mariadb-client php8.3 php8.3-cli php8.3-common php8.3-mysql php8.3-imap php8.3-gd php8.3-intl php8.3-mbstring php8.3-xml php8.3-curl php8.3-zip php8.3-apcu php8.3-opcache libapache2-mod-php8.3 openssl certbot python3-certbot-apache

# Secure MariaDB and create DB/user
sudo systemctl start mariadb
sudo systemctl enable mariadb

sudo mysql -e "CREATE DATABASE ${DB_NAME} CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
sudo mysql -e "CREATE USER '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';"
sudo mysql -e "GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';"
sudo mysql -e "FLUSH PRIVILEGES;"

# Output DB credentials to a file (securely)
echo -e "DB: ${DB_NAME}\nUser: ${DB_USER}\nPass: ${DB_PASS}" | sudo tee /root/osticket-db-credentials.txt
sudo chmod 600 /root/osticket-db-credentials.txt


# Remove any existing folder before cloning (optional guardrail)
sudo rm -rf "${WEB_ROOT}"

# Create web root directory with proper permissions
sudo mkdir -p "${WEB_ROOT}"
sudo chown $(whoami):$(whoami) "${WEB_ROOT}"

# Clone official osTicket repository
git clone --branch "${OSTICKET_VERSION}" "${OSTICKET_REPO}" "${WEB_ROOT}"

cd "${WEB_ROOT}"

# No need to set up custom remotes for official repo

# No need to modify .gitignore for official release

# Copy config file and set permissions
sudo cp "${WEB_ROOT}/include/ost-sampleconfig.php" "${WEB_ROOT}/include/ost-config.php"
sudo chown -R www-data:www-data "${WEB_ROOT}"
sudo chmod -R 755 "${WEB_ROOT}"
sudo chmod 666 "${WEB_ROOT}/include/ost-config.php"

# Configure PHP
sudo sed -i 's/^upload_max_filesize.*/upload_max_filesize = 50M/' /etc/php/8.3/apache2/php.ini
sudo sed -i 's/^post_max_size.*/post_max_size = 50M/' /etc/php/8.3/apache2/php.ini
sudo sed -i 's/^max_execution_time.*/max_execution_time = 300/' /etc/php/8.3/apache2/php.ini
sudo sed -i 's/^max_input_time.*/max_input_time = 300/' /etc/php/8.3/apache2/php.ini
sudo sed -i 's/^memory_limit.*/memory_limit = 256M/' /etc/php/8.3/apache2/php.ini
sudo sed -i 's|^;date.timezone.*|date.timezone = America/Chicago|' /etc/php/8.3/apache2/php.ini

sudo systemctl restart apache2

# Create Apache vhost
sudo bash -c "cat > ${APACHE_CONF}" <<EOF
<VirtualHost *:80>
    ServerAdmin ${ADMIN_EMAIL}
    DocumentRoot ${WEB_ROOT}
    ServerName ${DOMAIN}

    <Directory ${WEB_ROOT}>
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/osticket_error.log
    CustomLog \${APACHE_LOG_DIR}/osticket_access.log combined
</VirtualHost>
EOF

# Enable site and modules
sudo a2ensite osticket.conf
sudo a2enmod rewrite ssl
sudo a2dissite 000-default.conf
sudo systemctl restart apache2

# Generate Let's Encrypt SSL certificate
echo "Generating Let's Encrypt SSL certificate for ${DOMAIN}..."
# Remove any existing certificates for this domain
sudo certbot delete --cert-name ${DOMAIN} --non-interactive 2>/dev/null || true
# Generate new certificate
sudo certbot --apache -d ${DOMAIN} --non-interactive --agree-tos --email ${ADMIN_EMAIL} --redirect

# Set up automatic certificate renewal
sudo systemctl enable certbot.timer
sudo systemctl start certbot.timer

# Output details
echo "--------------------------------------------------"
echo "osTicket install script complete!"
echo "Access the web installer at: https://${DOMAIN}/"
echo "Database Name:     ${DB_NAME}"
echo "Database User:     ${DB_USER}"
echo "Database Password: ${DB_PASS}"
echo "Document Root:     ${WEB_ROOT}"
echo "SSL:               Let's Encrypt certificate installed"
echo "Certificate Auto-renewal: Enabled (via systemd timer)"
echo "Next steps:"
echo "1. Complete the web installer in your browser."
echo "2. Remove the setup directory and secure config file after install:"
echo "   sudo rm -rf ${WEB_ROOT}/setup"
echo "   sudo chmod 644 ${WEB_ROOT}/include/ost-config.php"
echo "--------------------------------------------------"