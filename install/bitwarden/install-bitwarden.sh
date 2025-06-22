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

# Install Docker
install_docker() {
    log "Installing Docker..."
    
    # Remove any old Docker installations
    sudo apt remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
    
    # Install Docker using the official installation script
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
    rm get-docker.sh
    
    # Verify Docker installation
    sudo docker --version
    log "Docker installed successfully"
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

spawn ./bitwarden.sh install

# Set a 30-minute timeout for the whole process
set timeout 1800

expect "Enter the domain name for your Bitwarden instance:"
send "${DOMAIN_NAME}\r"

expect {
    "Do you want to use Let's Encrypt to generate a free SSL certificate? (y/n):" {}
    timeout {
        puts "Timeout waiting for Let's Encrypt prompt"
        exit 1
    }
}
send "${USE_LETSENCRYPT}\r"

if {"${USE_LETSENCRYPT}" == "y"} {
    expect {
        "Enter your email address (Let's Encrypt):" {}
        timeout {
            puts "Timeout waiting for email prompt"
            exit 1
        }
    }
    send "${LETSENCRYPT_EMAIL}\r"
}

expect {
    "Enter your installation id:" {}
    timeout {
        puts "Timeout waiting for installation ID prompt"
        exit 1
    }
}
send "${INSTALL_ID}\r"

expect {
    "Enter your installation key:" {}
    timeout {
        puts "Timeout waiting for installation key prompt"
        exit 1
    }
}
send "${INSTALL_KEY}\r"

expect {
    "Enter your region (US/EU):" {}
    timeout {
        puts "Timeout waiting for region prompt"
        exit 1
    }
}
send "${REGION}\r"

if {"${USE_LETSENCRYPT}" != "y"} {
    expect {
        "Do you have a SSL certificate to use? (y/n):" {}
        timeout {
            puts "Timeout waiting for certificate prompt"
            exit 1
        }
    }
    send "n\r"
    
    expect {
        "Do you want to generate a self-signed SSL certificate? (y/n):" {}
        timeout {
            puts "Timeout waiting for self-signed certificate prompt"
            exit 1
        }
    }
    send "y\r"
}

# Print a message every 60 seconds to show the script is still running
set timeout 60
while {1} {
    expect {
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
        timeout {
            check_progress
            exp_continue
        }
        eof {
            puts "Installation process ended"
            break
        }
    }
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
    export DOMAIN_NAME USE_LETSENCRYPT LETSENCRYPT_EMAIL INSTALL_ID INSTALL_KEY REGION
      # Switch to bitwarden user and run installation
    log "Starting Bitwarden installation - this may take 10-20 minutes..."
    log "The script will show progress updates every minute"
    sudo -u bitwarden bash /tmp/bitwarden_install.sh
    
    # Check if installation was successful
    if [ ! -f "/opt/bitwarden/bwdata/docker/docker-compose.yml" ]; then
        error "Installation failed - docker-compose.yml not found"
        
        # Check for installation log
        if [ -f "/opt/bitwarden/install_log.txt" ]; then
            log "Check installation log: /opt/bitwarden/install_log.txt"
        fi
        
        exit 1
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
    
    sudo -u bitwarden bash << 'EOF'
cd /opt/bitwarden
./bitwarden.sh start
EOF
    
    # Verify that containers are running
    if sudo docker ps | grep -q bitwarden; then
        log "Bitwarden started successfully"
    else
        error "Bitwarden containers are not running. Installation may have failed."
        return 1
    fi
}

# Verify installation
verify_installation() {
    log "Verifying installation..."
    
    sleep 10  # Wait for containers to start
    
    echo
    info "Checking Docker containers:"
    sudo docker ps
    
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

# Recovery function for partial installations
recover_installation() {
    log "Attempting to recover from partial installation..."
    
    local status_code=$1
    
    case $status_code in
        1)  # Containers not running
            log "Attempting to start Bitwarden..."
            sudo -u bitwarden bash -c "cd /opt/bitwarden && ./bitwarden.sh start"
            ;;
        2)  # Installation incomplete
            log "Resuming Bitwarden installation..."
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
    
    # Proceed with fresh installation
    check_ubuntu_version
    update_system
    install_docker
    setup_bitwarden_user
    configure_firewall
    collect_installation_info
    install_bitwarden
    configure_environment
    start_bitwarden
    verify_installation
    
    log "Bitwarden installation completed successfully!"
}

# Run main function
main "$@"