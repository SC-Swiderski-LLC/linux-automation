# Bitwarden Self-Hosted Installation Script

This script automates the complete installation of Bitwarden self-hosted on Ubuntu 24.02/24.04 servers, following the official Bitwarden Linux Standard Deployment guide.

## Overview

The `install-bitwarden.sh` script provides a fully automated installation process that handles:
- System preparation and updates
- Docker installation and configuration
- Security setup with dedicated user account
- Firewall configuration
- Bitwarden installation and configuration
- SSL certificate setup (Let's Encrypt or self-signed)
- SMTP configuration for email functionality

## System Requirements

### Minimum Requirements
- **OS**: Ubuntu 24.02/24.04 (script may work on other versions with confirmation)
- **Processor**: x64, 1.4GHz
- **Memory**: 2GB RAM
- **Storage**: 12GB available space
- **Network**: Ports 80 and 443 accessible

### Recommended Requirements
- **Processor**: x64, 2GHz dual corev
- **Memory**: 4GB RAM
- **Storage**: 25GB available space

### Prerequisites
- Fresh Ubuntu server with sudo privileges
- Domain name with DNS records pointing to your server's IP address
- Installation ID and Key from [https://bitwarden.com/host](https://bitwarden.com/host)
- Email address for Let's Encrypt (if using SSL certificates)
- SMTP server details (optional, can be configured later)

## Azure VM Setup

If running on Azure, ensure your VM has:

### Network Security Group Rules
Allow inbound traffic on:
- **Port 22** (SSH)
- **Port 80** (HTTP)
- **Port 443** (HTTPS)

### VM Configuration
- **Size**: Standard_B2s or larger (2 vCPUs, 4GB RAM recommended)
- **Disk**: Premium SSD with at least 25GB
- **Public IP**: Static public IP address
- **DNS**: Configure your domain's A record to point to the VM's public IP

## Installation

### Step 1: Download the Script

```bash
# Download from your GitHub repository
wget https://raw.githubusercontent.com/SC-Swiderski-LLC/linux-automation/install/bitwarden/install-bitwarden.sh

# Make it executable
chmod +x install-bitwarden.sh
```

### Step 2: Prepare Required Information

Before running the script, gather the following information:

1. **Domain Name**: Your fully qualified domain name (e.g., `bitwarden.yourdomain.com`)
2. **Installation Credentials**: Get your Installation ID and Key from [https://bitwarden.com/host](https://bitwarden.com/host)
3. **Email Address**: For Let's Encrypt SSL certificate notifications
4. **SMTP Settings** (optional):
   - SMTP Host (e.g., `smtp.gmail.com`)
   - SMTP Port (e.g., `587` for TLS, `465` for SSL)
   - SMTP SSL setting (`true` or `false`)
   - SMTP Username and Password
   - Admin email address

### Step 3: Run the Installation

```bash
./install-bitwarden.sh
```

## Interactive Prompts

The script will prompt you for the following information:

### System Configuration
1. **Ubuntu Version Confirmation** (if not 24.02/24.04)
2. **Bitwarden User Password** - Set a strong password for the dedicated bitwarden user

### Bitwarden Configuration
3. **Domain Name** - Your domain pointing to this server
4. **SSL Certificate Choice** - Use Let's Encrypt? (y/n)
5. **Let's Encrypt Email** - For certificate expiration notifications (if using Let's Encrypt)
6. **Installation ID** - From bitwarden.com/host
7. **Installation Key** - From bitwarden.com/host
8. **Region** - US or EU

### Email Configuration (Optional)
9. **Configure SMTP** - Set up email now? (y/n)
10. **SMTP Details** - Host, port, SSL, username, password, admin email (if configuring)

## What the Script Does

### 1. System Preparation
- Validates Ubuntu version and user permissions
- Updates system packages
- Installs required dependencies (curl, wget, ca-certificates, etc.)

### 2. Docker Installation
- Removes any existing Docker installations
- Installs Docker using the official installation script
- Verifies Docker installation

### 3. Security Setup
- Creates a dedicated `bitwarden` user for security isolation
- Configures proper directory permissions (`/opt/bitwarden`)
- Adds bitwarden user to docker group
- Configures UFW firewall rules

### 4. Bitwarden Installation
- Downloads the official Bitwarden installation script
- Uses automated expect script to handle interactive installation
- Configures SSL certificates (Let's Encrypt or self-signed)
- Sets up all required Bitwarden components

### 5. Configuration
- Optionally configures SMTP settings for email functionality
- Sets up environment variables
- Creates backup of configuration files

### 6. Service Startup
- Starts all Bitwarden Docker containers
- Verifies installation success
- Provides status information and next steps

## Post-Installation

### Accessing Bitwarden
After successful installation, Bitwarden will be accessible at:
```
https://your-domain.com
```

### First Steps
1. **Test the Installation**: Visit your domain in a web browser
2. **Register an Account**: Create your first user account (requires SMTP for verification)
3. **Configure Admin Access**: If you set an admin email, access the admin portal
4. **Set Up Backups**: Implement regular backups of `/opt/bitwarden/bwdata`

### Useful Commands

All commands should be run from `/opt/bitwarden` as the bitwarden user:

```bash
# Start Bitwarden
sudo -u bitwarden ./bitwarden.sh start

# Stop Bitwarden
sudo -u bitwarden ./bitwarden.sh stop

# Restart Bitwarden
sudo -u bitwarden ./bitwarden.sh restart

# Update Bitwarden
sudo -u bitwarden ./bitwarden.sh update

# View container status
sudo docker ps

# View logs
sudo -u bitwarden ./bitwarden.sh compresslogs
```

### Configuration Files

Important configuration files:
- **Main Config**: `/opt/bitwarden/bwdata/config.yml`
- **Environment Variables**: `/opt/bitwarden/bwdata/env/global.override.env`
- **SSL Certificates**: `/opt/bitwarden/bwdata/ssl/`

## SMTP Configuration

If you skipped SMTP configuration during installation, you can configure it later:

1. Edit the environment file:
   ```bash
   sudo -u bitwarden nano /opt/bitwarden/bwdata/env/global.override.env
   ```

2. Update these settings:
   ```
   globalSettings__mail__smtp__host=your-smtp-host
   globalSettings__mail__smtp__port=587
   globalSettings__mail__smtp__ssl=true
   globalSettings__mail__smtp__username=your-username
   globalSettings__mail__smtp__password=your-password
   adminSettings__admins=admin@yourdomain.com
   ```

3. Restart Bitwarden:
   ```bash
   sudo -u bitwarden ./bitwarden.sh restart
   ```

## Troubleshooting

### Common Issues

1. **Domain Not Accessible**
   - Verify DNS records point to your server's IP
   - Check firewall rules (ports 80, 443)
   - Ensure Azure NSG rules allow traffic

2. **SSL Certificate Issues**
   - Verify domain resolves correctly
   - Check Let's Encrypt rate limits
   - Consider using self-signed certificates for testing

3. **Email Not Working**
   - Verify SMTP settings in environment file
   - Check SMTP server allows connections from your IP
   - Test SMTP credentials separately

4. **Container Issues**
   - Check container status: `sudo docker ps`
   - View logs: `sudo docker logs <container-name>`
   - Restart services: `sudo -u bitwarden ./bitwarden.sh restart`

### Log Files

Check these locations for troubleshooting:
- Bitwarden logs: `/opt/bitwarden/bwdata/logs/`
- Docker logs: `sudo docker logs <container-name>`
- System logs: `sudo journalctl -u docker`

## Security Considerations

### Best Practices
- **Regular Updates**: Keep the system and Bitwarden updated
- **Backups**: Implement automated backups of the `/opt/bitwarden/bwdata` directory
- **Monitoring**: Monitor system resources and container health
- **Firewall**: Ensure only necessary ports are open
- **SSH**: Disable root SSH access and use key-based authentication

### Backup Strategy
```bash
# Create backup script
sudo -u bitwarden tar -czf /backup/bitwarden-$(date +%Y%m%d).tar.gz -C /opt/bitwarden bwdata

# Automate with cron
0 2 * * * sudo -u bitwarden tar -czf /backup/bitwarden-$(date +\%Y\%m\%d).tar.gz -C /opt/bitwarden bwdata
```

## Support

### Official Resources
- [Bitwarden Self-Hosting Documentation](https://bitwarden.com/help/install-on-premise-linux/)
- [Bitwarden Community Forums](https://community.bitwarden.com/)
- [Bitwarden GitHub Repository](https://github.com/bitwarden)

### Script Issues
For issues specific to this installation script, check:
- Ensure all prerequisites are met
- Verify system meets minimum requirements
- Check the troubleshooting section above
- Review script output for error messages

## License

This script is provided as-is for educational and deployment purposes. Bitwarden is licensed under the Bitwarden License Agreement.
