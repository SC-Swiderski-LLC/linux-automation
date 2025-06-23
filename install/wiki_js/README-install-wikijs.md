# Wiki.js Installation Script

This script provides a complete automated installation of Wiki.js on Ubuntu 18.04/20.04/22.04/24.04 LTS systems.

## What's Included

After running this script, you'll have:

- **Docker CE** - Container runtime
- **PostgreSQL 17** - Database (dockerized)
- **Wiki.js 2.x** - Main application (dockerized, accessible via port 80)
- **Wiki.js Update Companion** - Automatic updates (dockerized)
- **UFW Firewall** - Configured for SSH, HTTP, and HTTPS
- **Complete setup** - Ready to use Wiki.js instance

## Prerequisites

- Ubuntu 18.04, 20.04, 22.04, or 24.04 LTS
- Non-root user with sudo privileges
- Internet connection
- At least 2GB RAM and 10GB disk space

## SSH Connection

ssh -i "C:\Users\path-to-key\DocsWiki-vm_key.pem" azureuser@20.80.81.80

## Installation

1. Download the installation script:
   ```bash
   # Option 1: Download directly from GitHub
   wget https://raw.githubusercontent.com/SC-Swiderski-LLC/linux-automation/main/install/wiki_js/install-wikijs.sh
   
   # Option 2: Clone the repository
   git clone https://github.com/SC-Swiderski-LLC/linux-automation.git
   cd linux-automation/install/wiki_js/
   
   # Option 3: Download with curl
   curl -O https://raw.githubusercontent.com/SC-Swiderski-LLC/linux-automation/main/install/wiki_js/install-wikijs.sh
   ```

2. Make the script executable:
   ```bash
   chmod +x install-wikijs.sh
   ```

3. Run the installation script:
   ```bash
   ./install-wikijs.sh
   ```

4. The script will:
   - Check your Ubuntu version
   - Update your system
   - Install Docker and dependencies
   - Create and configure Wiki.js containers
   - Configure the firewall
   - Start all services
   - Display access information

## Access Your Wiki

After installation, access your Wiki.js instance at:
- **HTTP**: `http://your-server-ip/`
- **Setup Wizard**: Follow the on-screen instructions to complete setup

## Post-Installation

### Initial Setup
1. Open your web browser and navigate to your server's IP address
2. Complete the setup wizard
3. Create your administrator account
4. Configure your wiki settings

### HTTPS with Let's Encrypt (Optional)

**Important**: Complete the setup wizard BEFORE enabling HTTPS!

1. Create an A record pointing your domain to your server IP
2. Verify HTTP access works with your domain
3. Stop and remove the wiki container:
   ```bash
   docker stop wiki
   docker rm wiki
   ```

4. Create a new container with SSL configuration:
   ```bash
   docker create --name=wiki \
     -e LETSENCRYPT_DOMAIN=your-domain.com \
     -e LETSENCRYPT_EMAIL=admin@your-domain.com \
     -e SSL_ACTIVE=1 \
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
   ```

5. Start the container:
   ```bash
   docker start wiki
   ```

## Useful Commands

### Container Management
- **View container status**: `docker ps`
- **Check logs**: `docker logs wiki`
- **Restart services**: `docker restart db wiki wiki-update-companion`
- **Stop services**: `docker stop db wiki wiki-update-companion`

### System Information
- **View firewall status**: `sudo ufw status`
- **Check Docker version**: `docker --version`
- **View network**: `docker network ls`
- **View volumes**: `docker volume ls`

### Troubleshooting
- **If Wiki.js won't load**: Wait 5-10 minutes for initialization
- **Check container logs**: `docker logs wiki`
- **Restart containers**: `docker restart db wiki`
- **View system resources**: `docker stats`

## File Locations

- **Installation directory**: `/etc/wiki/`
- **Database secret**: `/etc/wiki/.db-secret`
- **PostgreSQL data**: Docker volume `pgdata`
- **Container network**: `wikinet`

## Updates

Wiki.js includes an automatic update companion. When updates are available:

1. Navigate to Administration Area > System Info
2. Click "Perform Upgrade"
3. Wait for the process to complete

## Backup

To backup your Wiki.js installation:

1. **Database backup**:
   ```bash
   docker exec db pg_dump -U wiki wiki > wiki_backup.sql
   ```

2. **Volume backup**:
   ```bash
   docker run --rm -v pgdata:/data -v $(pwd):/backup ubuntu tar czf /backup/pgdata_backup.tar.gz -C /data .
   ```

## Security Notes

- Change default passwords immediately after setup
- Keep your system updated: `sudo apt update && sudo apt upgrade`
- Monitor container logs regularly
- Use HTTPS in production environments
- Regular backups are recommended

## Support

- **Wiki.js Documentation**: https://docs.requarks.io/
- **Docker Documentation**: https://docs.docker.com/
- **Ubuntu Documentation**: https://help.ubuntu.com/

## License

This installation script is provided as-is. Wiki.js is licensed under the GNU Affero General Public License v3.0.
