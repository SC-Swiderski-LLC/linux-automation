#!/bin/bash

# Bitwarden Installation Script for Ubuntu 24.02
# This script automates the installation of Bitwarden self-hosted on Ubuntu
# Based on the official Bitwarden Linux Standard Deployment guide

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}" >&2
}

warning() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

info() {
    echo -e "${BLUE}[INFO] $1${NC}"
}

# Check if running as root
check_root() {
    if [[ $EUID -eq 0 ]]; then
        error "This script should not be run as root for security reasons."
        error "Please run as a regular user with sudo privileges."
        exit 1
    fi
}

# Check Ubuntu version
check_ubuntu_version() {
    log "Checking Ubuntu version..."
    if ! grep -q "Ubuntu 24.02\|Ubuntu 24.04" /etc/os-release; then
        warning "This script is designed for Ubuntu 24.02/24.04. Current version:"
        cat /etc/os-release | grep PRETTY_NAME
        read -p "Do you want to continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

# Update system
update_system() {
    log "Updating system packages..."
    sudo apt update && sudo apt upgrade -y
    sudo apt install -y curl wget apt-transport-https ca-certificates gnupg lsb-release
}

# Install Docker and Docker Compose using Ubuntu packages
install_docker() {
    log "Installing Docker and Docker Compose from Ubuntu packages..."
    
    # Remove any old Docker installations
    sudo apt remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
    
    # Add Docker's official GPG key
    log "Adding Docker repository GPG key..."
    sudo apt-get update
    sudo apt-get install -y ca-certificates curl gnupg
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg
    
    # Set up the Docker repository
    log "Setting up Docker repository..."
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Install Docker Engine, CLI, containerd, and Docker Compose Plugin
    log "Installing Docker Engine and Docker Compose Plugin..."
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    # Verify Docker installation
    if ! sudo docker --version; then
        error "Docker installation failed"
        exit 1
    fi
    log "Docker Engine installed successfully"
      # Verify Docker Compose plugin installation
    log "Verifying Docker Compose plugin..."
    
    # Check for docker compose plugin first (should be installed with docker-compose-plugin)
    if sudo docker compose version &>/dev/null; then
        log "Docker Compose plugin is installed and working"
    else
        warning "Docker Compose plugin might not be installed or not working properly"
        
        # Try to fix it by installing explicitly
        log "Installing Docker Compose plugin explicitly..."
        sudo apt update
        sudo apt install -y docker-compose-plugin
        
        # Check again
        if ! sudo docker compose version &>/dev/null; then
            warning "Docker Compose plugin still not working, installing standalone docker-compose"
            sudo apt install -y docker-compose
            
            # Create plugin symlink if standalone is working
            if command -v docker-compose &>/dev/null; then
                log "Setting up Docker Compose plugin symlink..."
                sudo mkdir -p /usr/lib/docker/cli-plugins
                sudo ln -sf "$(which docker-compose)" /usr/lib/docker/cli-plugins/docker-compose
            else
                error "Failed to install Docker Compose. Cannot continue with installation."
                exit 1
            fi
        fi
    fi
    
    log "Docker Compose installation verified"
}

# Create Bitwarden user and directories
setup_bitwarden_user() {
    log "Setting up Bitwarden user and directories..."
    
    # Create bitwarden user if it doesn't exist
    if ! id "bitwarden" &>/dev/null; then
        sudo adduser --disabled-password --gecos "" bitwarden
        log "Created bitwarden user"
    else
        log "Bitwarden user already exists"
    fi
    
    # Set password for bitwarden user
    echo "Please set a strong password for the bitwarden user:"
    sudo passwd bitwarden
    
    # Create docker group if it doesn't exist
    sudo groupadd docker 2>/dev/null || true
    
    # Add bitwarden user to docker group
    sudo usermod -aG docker bitwarden
    
    # Create bitwarden directory
    sudo mkdir -p /opt/bitwarden
    sudo chmod -R 700 /opt/bitwarden
    sudo chown -R bitwarden:bitwarden /opt/bitwarden
    
    # Fix permissions for Docker socket - this is the most reliable method
    # to ensure the bitwarden user has immediate access to Docker
    if [ -e /var/run/docker.sock ]; then
        log "Setting Docker socket permissions for immediate access..."
        sudo chmod 666 /var/run/docker.sock
    fi
    
    # Also set the correct group ownership for the Docker socket
    if [ -e /var/run/docker.sock ]; then
        sudo chgrp docker /var/run/docker.sock || true
    fi
    
    # Verify bitwarden user can run Docker
    log "Verifying Docker access for bitwarden user..."
    if sudo -u bitwarden docker info &>/dev/null; then
        log "Bitwarden user has access to Docker"
    else
        warning "Bitwarden user does not have proper Docker access"
        
        # Try multiple approaches to fix Docker access
        log "Attempting to fix Docker permissions..."
        
        # Double-check docker group exists and bitwarden user is in it
        if ! getent group docker > /dev/null; then
            log "Docker group doesn't exist, creating it..."
            sudo groupadd docker
        fi
        
        sudo usermod -aG docker bitwarden
        
        # Set socket permissions explicitly (again)
        if [ -e /var/run/docker.sock ]; then
            sudo chmod 666 /var/run/docker.sock
        fi
        
        # Update group membership without requiring logout
        if command -v newgrp &> /dev/null; then
            log "Updating group membership with newgrp..."
            sudo -u bitwarden bash -c "newgrp docker" || true
        fi
        
        # Final verification
        if sudo -u bitwarden docker info &>/dev/null; then
            log "Docker access fixed successfully"
        else
            warning "Could not ensure Docker access for bitwarden user"
            warning "Installation may face permission issues"
        fi
    fi
    
    log "Bitwarden user and directories configured"
}

# Configure firewall
configure_firewall() {
    log "Configuring firewall..."
    
    # Check if ufw is installed
    if command -v ufw &> /dev/null; then
        sudo ufw allow 22/tcp    # SSH
        sudo ufw allow 80/tcp    # HTTP
        sudo ufw allow 443/tcp   # HTTPS
        
        # Enable firewall if not already enabled
        sudo ufw --force enable
        sudo ufw status
        log "Firewall configured to allow ports 22, 80, and 443"
    else
        warning "UFW firewall not found. Please manually configure firewall to allow ports 80 and 443"
    fi
}

# Collect installation information
collect_installation_info() {
    log "Collecting installation information..."
    
    echo
    info "Please provide the following information for your Bitwarden installation:"
    echo
    
    # Domain name
    read -p "Enter your domain name (e.g., bitwarden.example.com): " DOMAIN_NAME
    if [[ -z "$DOMAIN_NAME" ]]; then
        error "Domain name is required"
        exit 1
    fi
    
    # Let's Encrypt
    read -p "Use Let's Encrypt for SSL certificate? (y/n): " -n 1 -r USE_LETSENCRYPT
    echo
    if [[ $USE_LETSENCRYPT =~ ^[Yy]$ ]]; then
        read -p "Enter email for Let's Encrypt notifications: " LETSENCRYPT_EMAIL
        if [[ -z "$LETSENCRYPT_EMAIL" ]]; then
            error "Email is required for Let's Encrypt"
            exit 1
        fi
    fi
    
    # Installation ID and Key
    echo
    info "You need to get your Installation ID and Key from https://bitwarden.com/host"
    info "Use a valid email address to retrieve these values."
    echo
    read -p "Enter your Installation ID: " INSTALL_ID
    if [[ -z "$INSTALL_ID" ]]; then
        error "Installation ID is required"
        exit 1
    fi
    
    read -p "Enter your Installation Key: " INSTALL_KEY
    if [[ -z "$INSTALL_KEY" ]]; then
        error "Installation Key is required"
        exit 1
    fi
    
    # Region
    read -p "Enter your region (US/EU): " -n 2 -r REGION
    echo
    if [[ ! $REGION =~ ^(US|EU)$ ]]; then
        REGION="US"
        warning "Invalid region, defaulting to US"
    fi
    
    log "Installation information collected"
}

# Install Bitwarden as bitwarden user
install_bitwarden() {
    log "Installing Bitwarden..."
    
    # Install expect if not present (needs to be done with sudo privileges)
    if ! command -v expect &> /dev/null; then
        log "Installing expect package..."
        sudo apt install -y expect
    fi
    
    # Verify Docker and Docker Compose are available to bitwarden user
    log "Verifying Docker and Docker Compose availability for bitwarden user..."
    
    # Check Docker access
    if ! sudo -u bitwarden docker ps &>/dev/null; then
        error "Docker is not accessible to the bitwarden user!"
        error "This must be fixed before proceeding with installation."
        
        # Fix Docker socket permissions
        log "Fixing Docker socket permissions..."
        if [ -e /var/run/docker.sock ]; then
            sudo chmod 666 /var/run/docker.sock
            sudo chgrp docker /var/run/docker.sock 2>/dev/null || true
        fi
        
        # Check again after fixing
        if ! sudo -u bitwarden docker ps &>/dev/null; then
            error "Still cannot access Docker. Installation cannot proceed."
            error "You may need to restart the system or Docker service."
            exit 1
        fi
    fi
    
    # Find Docker Compose path for bitwarden user
    DOCKER_COMPOSE_PATH=""
    if sudo -u bitwarden command -v docker-compose &>/dev/null; then
        DOCKER_COMPOSE_PATH=$(sudo -u bitwarden which docker-compose)
        log "Bitwarden user has access to Docker Compose binary: ${DOCKER_COMPOSE_PATH}"
    elif sudo -u bitwarden docker compose version &>/dev/null; then
        log "Bitwarden user has access to Docker Compose plugin"
    else
        warning "Docker Compose is not accessible to bitwarden user!"
        log "Fixing Docker Compose access..."
        
        # Ensure Docker Compose binary is executable by all users
        if [ -f "/usr/local/bin/docker-compose" ]; then
            sudo chmod +x /usr/local/bin/docker-compose
            DOCKER_COMPOSE_PATH="/usr/local/bin/docker-compose"
        elif [ -f "/usr/bin/docker-compose" ]; then
            sudo chmod +x /usr/bin/docker-compose
            DOCKER_COMPOSE_PATH="/usr/bin/docker-compose"
        fi
        
        # Set up plugin symlinks if needed
        if [ -n "$DOCKER_COMPOSE_PATH" ]; then
            log "Setting up Docker Compose plugin symlinks..."
            sudo mkdir -p /usr/lib/docker/cli-plugins
            sudo ln -sf "${DOCKER_COMPOSE_PATH}" /usr/lib/docker/cli-plugins/docker-compose
        fi
    fi
    
    # Create installation script for bitwarden user
    cat > /tmp/bitwarden_install.sh << EOF
#!/bin/bash
set -e

cd /opt/bitwarden

# Download Bitwarden installation script
curl -Lso bitwarden.sh "https://func.bitwarden.com/api/dl/?app=self-host&platform=linux"
chmod 700 bitwarden.sh

# Create expect script for automated installation
cat > install_expect.sh << 'EOL'
#!/usr/bin/expect -f
set timeout 1800
log_file install_log.txt

proc check_progress {} {
    puts "Installation in progress... (this may take several minutes)"
}

# Make sure we have the most up-to-date installation script
puts "Downloading the latest Bitwarden installation script..."
spawn curl -L https://func.bitwarden.com/api/dl/?app=self-host&platform=linux -o bitwarden.sh
expect eof
system chmod 700 bitwarden.sh

puts "Starting Bitwarden installation..."
spawn ./bitwarden.sh install

# Set a 30-minute timeout for the whole process
set timeout 1800

# Handle potential docker warning
expect {
    "Unable to find image" {
        puts "Docker is pulling required images..."
        exp_continue
    }
    "Enter the domain name for your Bitwarden instance" {
        # Continue with normal flow
    }
    timeout {
        puts "Timeout waiting for domain name prompt"
        exit 1
    }
}

# Domain name prompt
send "${DOMAIN_NAME}\r"

expect {
    "Do you want to use Let's Encrypt to generate a free SSL certificate? (y/n)" {}
    "Do you want to use Let's Encrypt to generate a free SSL certificate?" {}
    timeout {
        puts "Timeout waiting for Let's Encrypt prompt"
        exit 1
    }
}
send "${USE_LETSENCRYPT}\r"

if {"${USE_LETSENCRYPT}" == "y"} {
    expect {
        "Enter your email address (Let's Encrypt)" {}
        timeout {
            puts "Timeout waiting for email prompt"
            exit 1
        }
    }
    send "${LETSENCRYPT_EMAIL}\r"
}

expect {
    "Enter your installation id" {}
    timeout {
        puts "Timeout waiting for installation ID prompt"
        exit 1
    }
}
send "${INSTALL_ID}\r"

expect {
    "Enter your installation key" {}
    timeout {
        puts "Timeout waiting for installation key prompt"
        exit 1
    }
}
send "${INSTALL_KEY}\r"

expect {
    "Enter your region (US/EU)" {}
    timeout {
        puts "Timeout waiting for region prompt"
        exit 1
    }
}
send "${REGION}\r"

if {"${USE_LETSENCRYPT}" != "y"} {
    expect {
        "Do you have a SSL certificate to use? (y/n)" {}
        timeout {
            puts "Timeout waiting for certificate prompt"
            exit 1
        }
    }
    send "n\r"
    
    expect {
        "Do you want to generate a self-signed SSL certificate? (y/n)" {}
        timeout {
            puts "Timeout waiting for self-signed certificate prompt"
            exit 1
        }
    }
    send "y\r"
}

# Print more detailed progress messages
set timeout 90
set progress_count 0

while {1} {
    expect {
        -re "Pulling from bitwarden|Pulling" {
            puts "Installation progress: Pulling Docker images..."
            exp_continue
        }
        "Starting Bitwarden" {
            puts "Installation progress: Starting Bitwarden..."
            exp_continue
        }
        "Installing Docker" {
            puts "Installation progress: Installing Docker..."
            exp_continue
        }
        "Restarting" {
            puts "Installation progress: Restarting services..."
            exp_continue
        }
        "Generating" {
            puts "Installation progress: Generating certificates..."
            exp_continue
        }
        "Downloading" {
            puts "Installation progress: Downloading components..."
            exp_continue
        }
        "Installing" {
            puts "Installation progress: Installing components..."
            exp_continue
        }
        "Configured" {
            puts "Installation progress: Configuration complete..."
            exp_continue
        }
        "Installation complete" {
            puts "Installation complete!"
            break
        }
        "Error:" {
            puts "ERROR DETECTED during installation!"
            exp_continue
        }
        "ERROR:" {
            puts "ERROR DETECTED during installation!"
            exp_continue
        }
        "Failed:" {
            puts "FAILURE DETECTED during installation!"
            exp_continue
        }
        timeout {
            incr progress_count
            puts "Installation in progress... Please wait [count: $progress_count]"
            exp_continue
        }
        eof {
            puts "Installation process ended"
            break
        }
    }
}

# Additional checks to ensure installation completed
puts "Verifying installation files..."
if {![file exists "/opt/bitwarden/bwdata/docker/docker-compose.yml"]} {
    puts "WARNING: docker-compose.yml not found - installation may have failed"
}
EOL
EOL

chmod +x install_expect.sh

# Run the installation
./install_expect.sh

# Clean up
rm install_expect.sh
EOF

    # Make the script executable and run as bitwarden user
    chmod +x /tmp/bitwarden_install.sh
    
    # Export variables for the bitwarden user script
    export DOMAIN_NAME USE_LETSENCRYPT LETSENCRYPT_EMAIL INSTALL_ID INSTALL_KEY REGION      # Switch to bitwarden user and run installation
    log "Starting Bitwarden installation - this may take 10-20 minutes..."
    log "The script will show progress updates every minute"
    
    # Create necessary directories to avoid permission issues
    sudo mkdir -p /opt/bitwarden/bwdata/docker
    sudo chown -R bitwarden:bitwarden /opt/bitwarden
    
    # Make sure the current Docker settings are applied
    if [ -e /var/run/docker.sock ]; then
        sudo chmod 666 /var/run/docker.sock
    fi
    
    # Run as bitwarden user with explicit environment settings
    sudo -u bitwarden -E bash /tmp/bitwarden_install.sh
    
    # If the installation fails, try running with root Docker permissions as fallback
    if [ ! -f "/opt/bitwarden/bwdata/docker/docker-compose.yml" ]; then
        warning "Installation as bitwarden user failed! Trying with root Docker permissions..."
        sudo -E bash -c "cd /opt/bitwarden && curl -Lso bitwarden.sh https://func.bitwarden.com/api/dl/?app=self-host&platform=linux && chmod 700 bitwarden.sh"
        sudo -E bash -c "cd /opt/bitwarden && ./bitwarden.sh install"
        sudo chown -R bitwarden:bitwarden /opt/bitwarden
    fi
      # Check if installation was successful
    if [ ! -f "/opt/bitwarden/bwdata/docker/docker-compose.yml" ]; then
        error "Installation failed - docker-compose.yml not found"
        
        # Check for installation log
        if [ -f "/opt/bitwarden/install_log.txt" ]; then
            log "Check installation log: /opt/bitwarden/install_log.txt"
            
            # Display last 20 lines of log for debugging
            echo "--- Last 20 lines of install log ---"
            tail -n 20 /opt/bitwarden/install_log.txt
            echo "-----------------------------------"
        fi
        
        # Check if Docker is working for the bitwarden user
        echo "--- Checking Docker status ---"
        sudo -u bitwarden docker info || { 
            error "Docker is not accessible to the bitwarden user"
            error "This is likely the cause of the installation failure"
            info "Try running: sudo chmod 666 /var/run/docker.sock"
        }
        
        # Check if Docker Compose is installed
        echo "--- Checking Docker Compose status ---"
        if ! sudo -u bitwarden docker compose version; then
            error "Docker Compose is not available to the bitwarden user"
            error "This is likely the cause of the installation failure"
        fi
        
        exit 1
    fi
    
    # Verify docker-compose.yml has content
    if [ ! -s "/opt/bitwarden/bwdata/docker/docker-compose.yml" ]; then
        warning "docker-compose.yml exists but is empty - installation may be incomplete"
    fi
    
    # Clean up
    rm /tmp/bitwarden_install.sh
    
    log "Bitwarden installation completed successfully"
}

# Configure environment variables
configure_environment() {
    log "Configuring environment variables..."
    
    # Check if environment file exists
    if [ ! -f "/opt/bitwarden/bwdata/env/global.override.env" ]; then
        error "Environment file not found! SMTP configuration will be skipped."
        return 1
    fi
    
    echo
    info "You need to configure SMTP settings for email functionality."
    echo "You can skip this now and configure it later by editing /opt/bitwarden/bwdata/env/global.override.env"
    echo
    
    read -p "Configure SMTP settings now? (y/n): " -n 1 -r CONFIGURE_SMTP
    echo
    
    if [[ $CONFIGURE_SMTP =~ ^[Yy]$ ]]; then
        read -p "SMTP Host: " SMTP_HOST
        read -p "SMTP Port: " SMTP_PORT
        read -p "SMTP SSL (true/false): " SMTP_SSL
        read -p "SMTP Username: " SMTP_USERNAME
        read -s -p "SMTP Password: " SMTP_PASSWORD
        echo
        read -p "Admin email address (optional): " ADMIN_EMAIL
        
        # Update environment file as bitwarden user
        sudo -u bitwarden bash << EOF
cd /opt/bitwarden
# Make a backup if the file exists
if [ -f "bwdata/env/global.override.env" ]; then
    cp bwdata/env/global.override.env bwdata/env/global.override.env.backup
fi

# Update SMTP settings
sed -i "s|globalSettings__mail__smtp__host=.*|globalSettings__mail__smtp__host=${SMTP_HOST}|" bwdata/env/global.override.env
sed -i "s|globalSettings__mail__smtp__port=.*|globalSettings__mail__smtp__port=${SMTP_PORT}|" bwdata/env/global.override.env
sed -i "s|globalSettings__mail__smtp__ssl=.*|globalSettings__mail__smtp__ssl=${SMTP_SSL}|" bwdata/env/global.override.env
sed -i "s|globalSettings__mail__smtp__username=.*|globalSettings__mail__smtp__username=${SMTP_USERNAME}|" bwdata/env/global.override.env
sed -i "s|globalSettings__mail__smtp__password=.*|globalSettings__mail__smtp__password=${SMTP_PASSWORD}|" bwdata/env/global.override.env

if [[ -n "${ADMIN_EMAIL}" ]]; then
    sed -i "s|adminSettings__admins=.*|adminSettings__admins=${ADMIN_EMAIL}|" bwdata/env/global.override.env
fi
EOF
        
        log "SMTP configuration completed"
    fi
}

# Start Bitwarden
start_bitwarden() {
    log "Starting Bitwarden..."
    
    # Check if bitwarden.sh exists
    if [ ! -f "/opt/bitwarden/bitwarden.sh" ]; then
        error "bitwarden.sh not found! Cannot start Bitwarden."
        return 1
    fi
    
    # Check if docker-compose files exist
    if [ ! -f "/opt/bitwarden/bwdata/docker/docker-compose.yml" ]; then
        error "docker-compose.yml not found! Bitwarden installation may be incomplete."
        error "Try running the installation script again."
        return 1
    fi
    
    # Start Bitwarden as the bitwarden user
    log "Running bitwarden.sh start command..."
    sudo -u bitwarden bash -c "cd /opt/bitwarden && ./bitwarden.sh start" || {
        error "Failed to start Bitwarden with bitwarden.sh"
        
        # Try alternative start method
        warning "Trying alternative start method with docker compose..."
        sudo -u bitwarden bash -c "cd /opt/bitwarden/bwdata/docker && docker compose up -d"
    }
    
    # Give containers time to start
    log "Waiting for containers to start (30 seconds)..."
    sleep 30
    
    # Verify that containers are running
    if sudo docker ps | grep -q bitwarden; then
        log "Bitwarden started successfully"
    else
        error "Bitwarden containers are not running. Installation may have failed."
        
        # Check for Docker errors
        log "Checking for Docker errors..."
        sudo docker ps -a | grep -i bitwarden
        
        # Check Docker Compose logs
        if [ -f "/opt/bitwarden/bwdata/docker/docker-compose.yml" ]; then
            log "Checking Docker Compose logs..."
            sudo -u bitwarden bash -c "cd /opt/bitwarden/bwdata/docker && docker compose logs --tail=50"
        fi
        
        return 1
    fi
}

# Verify installation
verify_installation() {
    log "Verifying installation..."
    
    sleep 15  # Wait for containers to start
    
    local containers_running=false
    
    # Check if Bitwarden containers are running
    if sudo docker ps | grep -q bitwarden; then
        containers_running=true
        log "Bitwarden containers are running"
    else
        error "Bitwarden containers are not running!"
        log "Trying to start Bitwarden services again..."
        
        # Try to start services again
        sudo -u bitwarden bash -c "cd /opt/bitwarden && ./bitwarden.sh restart" || {
            # Fallback to docker compose
            log "Trying direct Docker Compose command..."
            sudo -u bitwarden bash -c "cd /opt/bitwarden/bwdata/docker && docker compose up -d"
            sleep 20
            
            # Check if containers are running after second attempt
            if sudo docker ps | grep -q bitwarden; then
                containers_running=true
                log "Bitwarden containers started successfully on second attempt"
            else
                error "CRITICAL: Failed to start Bitwarden containers"
                log "Showing Docker Compose logs for debugging:"
                sudo -u bitwarden bash -c "cd /opt/bitwarden/bwdata/docker && docker compose logs --tail 50"
            fi
        }
    fi
    
    echo
    info "Checking Docker containers:"
    sudo docker ps | grep bitwarden || true
    
    # Verify web access
    if [[ "$containers_running" == "true" ]]; then
        log "Testing local connection to Bitwarden server..."
        if command -v curl &> /dev/null; then
            # Disable exit on error temporarily to prevent the curl command from stopping the script
            set +e
            curl -k -s -o /dev/null -w "Connection test: %{http_code}\n" https://localhost
            HTTP_STATUS=$?
            set -e
            
            if [[ $HTTP_STATUS -eq 0 ]]; then
                log "Bitwarden web server is responding locally"
            else
                warning "Bitwarden web server is not responding locally"
                warning "It may take several more minutes to fully initialize"
            fi
        fi
    fi
    
    echo
    info "Bitwarden should now be accessible at: https://${DOMAIN_NAME}"
    info "You can register a new account and start using Bitwarden!"
    echo
    info "Important next steps:"
    info "1. Test the installation by visiting your domain in a web browser"
    info "2. Register a new account (you'll need SMTP configured for email verification)"
    info "3. Set up regular backups of your /opt/bitwarden/bwdata directory"
    info "4. Keep your system updated with regular updates"
    echo
    info "Useful commands (run as bitwarden user from /opt/bitwarden):"
    info "  sudo -u bitwarden ./bitwarden.sh start    - Start Bitwarden"
    info "  sudo -u bitwarden ./bitwarden.sh stop     - Stop Bitwarden"
    info "  sudo -u bitwarden ./bitwarden.sh restart  - Restart Bitwarden"
    info "  sudo -u bitwarden ./bitwarden.sh update   - Update Bitwarden"
    
    # Check if all required files exist
    echo
    log "Verifying installation files..."
    local missing_files=false
    
    for file in "/opt/bitwarden/bitwarden.sh" \
                "/opt/bitwarden/bwdata/docker/docker-compose.yml" \
                "/opt/bitwarden/bwdata/env/global.override.env"; do
        if [[ ! -f "$file" ]]; then
            error "Missing file: $file"
            missing_files=true
        else
            info "✓ File exists: $file"
        fi
    done
    
    if [[ "$missing_files" == "true" ]]; then
        warning "Some required files are missing. Installation may be incomplete."
    else
        log "All required files are present"
    fi
    echo
}

# Check installation status and provide recovery options
check_installation_status() {
    # Temporarily disable exit on error
    set +e
    
    log "Checking current installation status..."
    
    # Check if bitwarden user exists
    if id "bitwarden" &>/dev/null; then
        info "✓ Bitwarden user exists"
    else
        info "✗ Bitwarden user not found"
    fi
    
    # Check if bitwarden directory exists
    if [[ -d "/opt/bitwarden" ]]; then
        info "✓ Bitwarden directory exists"
        
        # Check if bitwarden.sh script exists
        if [[ -f "/opt/bitwarden/bitwarden.sh" ]]; then
            info "✓ Bitwarden installation script found"
            
            # Check if bwdata directory exists (indicates successful installation)
            if [[ -d "/opt/bitwarden/bwdata" ]]; then
                info "✓ Bitwarden data directory exists - installation appears complete"
                
                # Check if containers are running
                if sudo docker ps | grep -q bitwarden; then
                    info "✓ Bitwarden containers are running"
                    info "Bitwarden appears to be fully installed and running"
                    return 0
                else
                    warning "⚠ Bitwarden containers not running"
                    info "You can try starting Bitwarden with: sudo -u bitwarden /opt/bitwarden/bitwarden.sh start"
                    return 1
                fi
            else
                warning "⚠ Bitwarden data directory not found - installation incomplete"
                return 2
            fi
        else
            warning "⚠ Bitwarden installation script not found"
            return 3
        fi    else
        info "✗ Bitwarden directory not found"
        return 4
    fi
    
    # Re-enable exit on error
    set -e
}

# Check Docker Compose availability
check_docker_compose() {
    log "Checking for Docker Compose..."
    
    local docker_compose_available=false
    
    # Check for docker compose plugin (preferred method)
    if docker compose version &> /dev/null; then
        log "Docker Compose plugin is available"
        docker_compose_available=true
    fi
    
    # Check for standalone docker-compose binary as fallback
    if command -v docker-compose &> /dev/null; then
        log "Docker Compose standalone binary is available"
        docker_compose_available=true
    fi
    
    if [[ "$docker_compose_available" != "true" ]]; then
        warning "Docker Compose is not available! Installing from packages..."
        
        # First install docker-compose-plugin (the modern way)
        log "Installing Docker Compose plugin..."
        sudo apt update
        sudo apt install -y docker-compose-plugin
        
        # Check if plugin installation worked
        if ! docker compose version &> /dev/null; then
            warning "Docker Compose plugin installation failed, trying standalone package..."
            sudo apt install -y docker-compose
        fi
        
        # Final verification
        if docker compose version &> /dev/null || docker-compose --version &> /dev/null; then
            log "Docker Compose successfully installed"
        else
            error "Failed to install Docker Compose. This is required for Bitwarden installation."
            error "Please try installing Docker and Docker Compose manually following Docker's official documentation."
            exit 1
        fi
    fi
    
    # If plugin is not available but standalone is, create plugin symlink
    if ! docker compose version &> /dev/null && command -v docker-compose &> /dev/null; then
        log "Setting up Docker Compose plugin symlink from standalone binary..."
        sudo mkdir -p /usr/lib/docker/cli-plugins
        sudo ln -sf "$(which docker-compose)" /usr/lib/docker/cli-plugins/docker-compose
        
        # Verify plugin functionality
        if docker compose version &> /dev/null; then
            log "Docker Compose plugin symlink created successfully"
        fi
    fi
}

# Recovery function for partial installations
recover_installation() {
    log "Attempting to recover from partial installation..."
    
    local status_code=$1
    
    case $status_code in
        1)  # Containers not running
            log "Attempting to start Bitwarden..."
            # Check Docker and Docker Compose first
            check_docker_compose
            
            # Try using bitwarden.sh first
            if [ -f "/opt/bitwarden/bitwarden.sh" ]; then
                log "Using bitwarden.sh to start services..."
                sudo -u bitwarden bash -c "cd /opt/bitwarden && ./bitwarden.sh start"
            elif [ -f "/opt/bitwarden/bwdata/docker/docker-compose.yml" ]; then
                # Fallback to docker compose directly
                log "Using docker compose directly..."
                sudo -u bitwarden bash -c "cd /opt/bitwarden/bwdata/docker && docker compose up -d"
            else
                error "Cannot start Bitwarden - missing required files"
                return 1
            fi
            
            # Verify that containers started
            sleep 15
            if sudo docker ps | grep -q bitwarden; then
                log "Bitwarden containers started successfully"
            else
                error "Failed to start Bitwarden containers"
                return 1
            fi
            ;;
            
        2)  # Installation incomplete
            log "Resuming Bitwarden installation..."
            
            # Check Docker and Docker Compose first
            check_docker_compose
            
            # Try to resume installation
            collect_installation_info
            install_bitwarden
            configure_environment
            start_bitwarden
            verify_installation
            ;;
            
        3|4)  # Missing files/directories
            warning "Installation appears to be corrupted. Recommend clean reinstall."
            read -p "Do you want to clean up and start fresh? (y/n): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                cleanup_installation
                main
            fi
            ;;
    esac
}

# Cleanup function
cleanup_installation() {
    log "Cleaning up partial installation..."
    
    # Stop any running containers
    if sudo docker ps | grep -q bitwarden; then
        log "Stopping Bitwarden containers..."
        sudo -u bitwarden bash -c "cd /opt/bitwarden && ./bitwarden.sh stop" 2>/dev/null || true
    fi
    
    # Remove bitwarden directory
    if [[ -d "/opt/bitwarden" ]]; then
        log "Removing Bitwarden directory..."
        sudo rm -rf /opt/bitwarden
    fi
    
    # Note: We keep the bitwarden user for security reasons
    log "Cleanup completed. Bitwarden user preserved for security."
}

# Main installation function
main() {
    log "Starting Bitwarden installation on Ubuntu 24.02..."
    
    check_root
    
    # Check if there's a partial installation
    check_installation_status
    status=$?
    
    if [[ $status -eq 0 ]]; then
        info "Bitwarden is already installed and running!"
        info "Access it at: https://$(sudo -u bitwarden cat /opt/bitwarden/bwdata/config.yml | grep url: | cut -d' ' -f2 2>/dev/null || echo 'your-domain')"
        exit 0
    elif [[ $status -eq 1 ]]; then
        read -p "Bitwarden is installed but not running. Try to start it? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            recover_installation $status
            exit 0
        fi
    elif [[ $status -eq 2 || $status -eq 3 ]]; then
        read -p "Partial installation detected. Continue with recovery? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            recover_installation $status
            exit 0
        else
            read -p "Start clean installation instead? (y/n): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                cleanup_installation
            else
                exit 1
            fi
        fi
    elif [[ $status -eq 4 ]]; then
        info "No existing Bitwarden installation found. Proceeding with fresh install."
    fi
    
    # Define a trap to handle Ctrl+C and other signals gracefully
    trap cleanup_on_exit INT TERM
    
    # Proceed with fresh installation
    check_ubuntu_version
    update_system
    install_docker
    check_docker_compose  # Add explicit check for Docker Compose
    setup_bitwarden_user
    configure_firewall
      # Verify Docker is accessible to bitwarden user before proceeding
    log "Verifying Docker access for bitwarden user..."
    if ! sudo -u bitwarden docker ps &>/dev/null; then
        warning "The bitwarden user cannot access Docker"
        warning "This must be fixed before proceeding"
        
        # Fix Docker socket permissions
        log "Setting Docker socket permissions..."
        if [ -e /var/run/docker.sock ]; then
            sudo chmod 666 /var/run/docker.sock
            sudo chgrp docker /var/run/docker.sock 2>/dev/null || true
            
            # Restart Docker service to apply permission changes
            log "Restarting Docker service to apply permission changes..."
            sudo systemctl restart docker.service || true
            sleep 5
            
            # Verify again
            if ! sudo -u bitwarden docker ps &>/dev/null; then
                error "Still cannot access Docker. Trying one more approach..."
                
                # Try adding current user to the Docker group and use sudo to run as bitwarden
                sudo usermod -aG docker $USER
                
                # Create a new shell with updated group membership
                if ! sudo -g docker -u bitwarden docker ps &>/dev/null; then
                    error "Docker permission issues persist. This might require a system restart."
                    error "You may need to log out and log back in, or restart the system."
                    error "After restarting, run this script again."
                    exit 1
                else
                    log "Found a workaround for Docker access"
                fi
            fi
        else
            error "Docker socket not found. Is Docker properly installed?"
            exit 1
        fi
    fi
    
    # Also verify Docker Compose is accessible
    if ! sudo -u bitwarden docker compose version &>/dev/null && ! sudo -u bitwarden command -v docker-compose &>/dev/null; then
        warning "Docker Compose not accessible to bitwarden user."
        log "Setting up Docker Compose access..."
        
        # Find Docker Compose binary location
        DOCKER_COMPOSE_PATH=""
        if command -v docker-compose &>/dev/null; then
            DOCKER_COMPOSE_PATH=$(which docker-compose)
        elif [ -f "/usr/local/bin/docker-compose" ]; then
            DOCKER_COMPOSE_PATH="/usr/local/bin/docker-compose"
        elif [ -f "/usr/bin/docker-compose" ]; then
            DOCKER_COMPOSE_PATH="/usr/bin/docker-compose"
        fi
        
        if [ -n "$DOCKER_COMPOSE_PATH" ]; then
            log "Setting up Docker Compose symlinks and permissions..."
            sudo chmod 755 "$DOCKER_COMPOSE_PATH"
            sudo mkdir -p /usr/lib/docker/cli-plugins
            sudo ln -sf "$DOCKER_COMPOSE_PATH" /usr/lib/docker/cli-plugins/docker-compose
        else
            warning "Could not locate Docker Compose binary. Plugin access may not work."
        fi
    fi
    
    collect_installation_info
    install_bitwarden
    configure_environment
    start_bitwarden
    verify_installation
    
    # Remove the trap
    trap - INT TERM
    
    log "Bitwarden installation completed successfully!"
}

# Function to handle clean exit when interrupted
cleanup_on_exit() {
    echo
    error "Installation interrupted by user!"
    warning "The installation may be in an incomplete state."
    warning "You can run this script again to resume or clean up the installation."
    exit 1
}

# Run main function
main "$@"