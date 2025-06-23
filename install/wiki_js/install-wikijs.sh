#!/bin/bash
# Wiki.js Complete Installation Script for Ubuntu 18.04/20.04/22.04 LTS
# This script installs Wiki.js with all dependencies including Docker, PostgreSQL, and security configuration
set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
if [[ $EUID -eq 0 ]]; then
   error "This script should not be run as root. Please run as a regular user with sudo privileges."
   exit 1
fi

# Check if sudo is available
if ! command -v sudo &> /dev/null; then
    error "sudo is required but not installed. Please install sudo first."
    exit 1
fi

log "Starting Wiki.js installation on Ubuntu..."
log "This script will install Docker, PostgreSQL, and Wiki.js with all dependencies"

# Variables
INSTALL_DIR="/etc/wiki"
DB_SECRET_FILE="$INSTALL_DIR/.db-secret"
SERVER_IP=$(hostname -I | awk '{print $1}')

# Function to check Ubuntu version
check_ubuntu_version() {
    log "Checking Ubuntu version..."
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        if [[ "$ID" == "ubuntu" ]]; then
            case "$VERSION_ID" in
                "18.04"|"20.04"|"22.04"|"24.04")
                    success "Ubuntu $VERSION_ID detected - compatible version"
                    ;;
                *)
                    warning "Ubuntu $VERSION_ID detected - this script is tested on 18.04/20.04/22.04/24.04"
                    read -p "Continue anyway? (y/N): " -n 1 -r
                    echo
                    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                        exit 1
                    fi
                    ;;
            esac
        else
            error "This script is designed for Ubuntu. Detected: $ID"
            exit 1
        fi
    else
        error "Cannot detect OS version"
        exit 1
    fi
}

# Function to update the system
update_system() {
    log "Updating system packages..."
    
    # Fetch latest updates
    sudo apt -qqy update
    
    # Install all updates automatically with non-interactive mode
    sudo DEBIAN_FRONTEND=noninteractive apt-get -qqy -o Dpkg::Options::='--force-confdef' -o Dpkg::Options::='--force-confold' dist-upgrade
    
    success "System updated successfully"
}

# Function to install Docker
install_docker() {
    log "Installing Docker..."
    
    # Check if Docker is already installed
    if command -v docker &> /dev/null; then
        warning "Docker is already installed"
        docker --version
        return 0
    fi
    
    # Install dependencies to install Docker
    sudo apt -qqy -o Dpkg::Options::='--force-confdef' -o Dpkg::Options::='--force-confold' install \
        ca-certificates \
        curl \
        gnupg \
        lsb-release
    
    # Register Docker package registry
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Refresh package updates and install Docker
    sudo apt -qqy update
    sudo apt -qqy -o Dpkg::Options::='--force-confdef' -o Dpkg::Options::='--force-confold' install \
        docker-ce \
        docker-ce-cli \
        containerd.io \
        docker-compose-plugin
    
    # Add current user to docker group
    sudo usermod -aG docker $USER
    
    success "Docker installed successfully"
}

# Function to setup Wiki.js containers
setup_wikijs_containers() {
    log "Setting up Wiki.js containers..."
    
    # Create installation directory for Wiki.js
    sudo mkdir -p $INSTALL_DIR
    sudo chown $USER:$USER $INSTALL_DIR
    
    # Generate DB secret
    log "Generating database secret..."
    openssl rand -base64 32 > $DB_SECRET_FILE
    success "Database secret generated"
    
    # Create internal docker network
    log "Creating Docker network..."
    if ! docker network ls | grep -q wikinet; then
        docker network create wikinet
        success "Docker network 'wikinet' created"
    else
        warning "Docker network 'wikinet' already exists"
    fi
    
    # Create data volume for PostgreSQL
    log "Creating PostgreSQL data volume..."
    if ! docker volume ls | grep -q pgdata; then
        docker volume create pgdata
        success "PostgreSQL data volume created"
    else
        warning "PostgreSQL data volume already exists"
    fi
    
    # Remove existing containers if they exist
    for container in db wiki wiki-update-companion; do
        if docker ps -a --format 'table {{.Names}}' | grep -q "^$container$"; then
            log "Removing existing container: $container"
            docker stop $container 2>/dev/null || true
            docker rm $container 2>/dev/null || true
        fi
    done
    
    # Create PostgreSQL container
    log "Creating PostgreSQL container..."
    docker create \
        --name=db \
        -e POSTGRES_DB=wiki \
        -e POSTGRES_USER=wiki \
        -e POSTGRES_PASSWORD_FILE=/etc/wiki/.db-secret \
        -v /etc/wiki/.db-secret:/etc/wiki/.db-secret:ro \
        -v pgdata:/var/lib/postgresql/data \
        --restart=unless-stopped \
        -h db \
        --network=wikinet \
        postgres:17
    
    # Create Wiki.js container
    log "Creating Wiki.js container..."
    docker create \
        --name=wiki \
        -e DB_TYPE=postgres \
        -e DB_HOST=db \
        -e DB_PORT=5432 \
        -e DB_PASS_FILE=/etc/wiki/.db-secret \
        -v /etc/wiki/.db-secret:/etc/wiki/.db-secret:ro \
        -e DB_USER=wiki \
        -e DB_NAME=wiki \
        -e UPGRADE_COMPANION=1 \
        --restart=unless-stopped \
        -h wiki \
        --network=wikinet \
        -p 80:3000 \
        -p 443:3443 \
        ghcr.io/requarks/wiki:2
    
    # Create Wiki.js Update Companion container
    log "Creating Wiki.js Update Companion container..."
    docker create \
        --name=wiki-update-companion \
        -v /var/run/docker.sock:/var/run/docker.sock:ro \
        --restart=unless-stopped \
        -h wiki-update-companion \
        --network=wikinet \
        ghcr.io/requarks/wiki-update-companion:latest
    
    success "Wiki.js containers created successfully"
}

# Function to setup firewall
setup_firewall() {
    log "Configuring UFW firewall..."
    
    # Install UFW if not present
    if ! command -v ufw &> /dev/null; then
        sudo apt -qqy install ufw
    fi
    
    # Allow SSH, HTTP, and HTTPS
    sudo ufw allow ssh
    sudo ufw allow http
    sudo ufw allow https
    
    # Enable firewall
    sudo ufw --force enable
    
    success "Firewall configured and enabled"
}

# Function to start containers
start_containers() {
    log "Starting containers..."
    
    # Start database first
    log "Starting PostgreSQL container..."
    docker start db
    sleep 5  # Give DB time to initialize
    
    # Start Wiki.js
    log "Starting Wiki.js container..."
    docker start wiki
    
    # Start update companion
    log "Starting Wiki.js Update Companion..."
    docker start wiki-update-companion
    
    success "All containers started successfully"
}

# Function to wait for services to be ready
wait_for_services() {
    log "Waiting for services to be ready..."
    
    # Wait for Wiki.js to be responsive
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if curl -s -o /dev/null -w "%{http_code}" http://localhost | grep -q "200\|302\|301"; then
            success "Wiki.js is ready!"
            break
        fi
        
        log "Attempt $attempt/$max_attempts - waiting for Wiki.js to start..."
        sleep 10
        ((attempt++))
    done
    
    if [ $attempt -gt $max_attempts ]; then
        warning "Wiki.js may still be starting. Please wait a few more minutes and check manually."
    fi
}

# Function to display final information
display_final_info() {
    echo
    echo "=============================================="
    success "Wiki.js Installation Complete!"
    echo "=============================================="
    echo
    echo -e "${BLUE}Installation Details:${NC}"
    echo "• Docker: $(docker --version | cut -d' ' -f3 | tr -d ',')"
    echo "• PostgreSQL 17: Running in container"
    echo "• Wiki.js 2.x: Running in container"
    echo "• Update Companion: Running in container"
    echo "• UFW Firewall: Enabled (SSH, HTTP, HTTPS allowed)"
    echo
    echo -e "${BLUE}Access Information:${NC}"
    echo "• Wiki.js URL: http://$SERVER_IP/"
    echo "• Installation Directory: $INSTALL_DIR"
    echo "• Database Secret: $DB_SECRET_FILE"
    echo
    echo -e "${BLUE}Container Status:${NC}"
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" --filter "name=db" --filter "name=wiki" --filter "name=wiki-update-companion"
    echo
    echo -e "${BLUE}Next Steps:${NC}"
    echo "1. Open your web browser and navigate to: http://$SERVER_IP/"
    echo "2. Complete the on-screen setup wizard"
    echo "3. Create your administrator account"
    echo "4. Configure your wiki settings"
    echo
    echo -e "${YELLOW}Optional - HTTPS with Let's Encrypt:${NC}"
    echo "• First complete the setup wizard"
    echo "• Create an A record pointing your domain to $SERVER_IP"
    echo "• Follow the Let's Encrypt section in the Wiki.js documentation"
    echo
    echo -e "${BLUE}Useful Commands:${NC}"
    echo "• Check container logs: docker logs wiki"
    echo "• Restart containers: docker restart db wiki wiki-update-companion"
    echo "• Stop containers: docker stop db wiki wiki-update-companion"
    echo "• Update Wiki.js: Use the admin interface or restart the update companion"
    echo
    echo -e "${GREEN}Installation completed successfully!${NC}"
    echo "=============================================="
}

# Main execution
main() {
    log "Wiki.js Installation Script Started"
    
    check_ubuntu_version
    update_system
    install_docker
    setup_wikijs_containers
    setup_firewall
    start_containers
    wait_for_services
    display_final_info
    
    # Note about Docker group membership
    if groups $USER | grep -q docker; then
        log "User is already in docker group"
    else
        warning "You may need to log out and back in for Docker group membership to take effect"
        warning "Or run: newgrp docker"
    fi
}

# Run main function
main
