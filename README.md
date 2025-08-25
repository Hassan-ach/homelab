# Self-Hosted Cloud Services with Docker Compose

A complete homelab setup for self-hosting Nextcloud and Jellyfin with automated SSL certificates, reverse proxy, and database management.

## Motivation

- Ran out of free Google Drive storage
- Didn't want to pay for more cloud storage
- Learning experience about home-labbing and self-hosting
- Curiosity about containerized applications
- Privacy and control over personal data

## Hardware Specifications

- **Device**: HP Mini PC
- **CPU**: Intel i5 6th Gen
- **RAM**: 8GB
- **Storage**: 256GB SSD + 256GB HDD
- **GPU**: Intel HD 530 iGPU

## Prerequisites

- Ubuntu Server or Desktop (20.04+ recommended)
- Docker & Docker Compose
- Domain name (free option: [DuckDNS](https://www.duckdns.org))
- Router with port forwarding capability (for WAN access)

## Tech Stack Overview

### [SWAG](https://docs.linuxserver.io/images/docker-swag/) (Secure Web Application Gateway)

- **Purpose**: Reverse proxy with automated SSL certificates
- **Features**:
    - Nginx web server and reverse proxy
    - Automated Let's Encrypt SSL certificate generation and renewal
    - Fail2ban for additional security
    - DNS validation support for various providers

### [ Nextcloud ](https://jellyfin.org/docs/)

- **Purpose**: Self-hosted cloud storage and collaboration platform
- **Key Features**:
    - File storage & synchronization across devices
    - Sharing & collaboration tools
    - Rich app ecosystem (calendars, contacts, notes, office suite)
    - Security features (end-to-end encryption, 2FA)
    - Mobile and desktop clients

### [ Jellyfin ](https://jellyfin.org/docs/)

- **Purpose**: Media server for personal content streaming
- **Features**:
    - Stream movies, TV shows, music, and photos
    - Hardware transcoding support
    - Mobile apps and web interface
    - No licensing fees or restrictions

### MariaDB

- **Purpose**: Database backend for Nextcloud
- **Benefits**: MySQL-compatible, reliable, optimized for containerized environments

### Redis

- **Purpose**: Caching layer for improved Nextcloud performance
- **Benefits**: Session storage, file locking, distributed caching

## Directory Layout

When you run `install.sh`, the following structure is created under `${COMMUNE_DIR}`:

```bash
commune/
├─ nextcloud/
│ ├─ config/
│ ├─ data/
│ └─ logs/
├─ jellyfin/
│ ├─ config/
│ ├─ cache/
│ └─ logs/
├─ mysql/
│ ├─ data/
│ ├─ config/
│ └─ logs/
├─ redis/
│ ├─ data/
│ └─ logs/
└─ swag/
  ├─ config/
  └─ logs/

```

## Installation

### 1. Clone the Repository

```bash
git clone https://github.com/Hassan-ach/homelab
cd homelab
```

### 2. Get a Domain Name

If you don't have a domain, get one for free at [DuckDNS](https://www.duckdns.org):

1. Sign in with your preferred account
2. Create a subdomain (e.g., `yourhomelab.duckdns.org`)
3. Note your token for later configuration

### 3. Configure Environment Variables

```bash
cp .env.example .env
nano .env
```

Fill in all required values (see configuration section below).

### 4. Run the Installation Script

```bash
sudo chmod +x install.sh
sudo ./install.sh
```

## Configuration

### Environment Variables (.env file)

**Critical settings to configure:**

1. **Domain Settings**:

    ```bash
    URL=yourdomain.duckdns.org
    DUCKDNSTOKEN=your-duckdns-token
    EMAIL=your.email@example.com
    ```

2. **Security Credentials** (generate strong passwords):

    ```bash
    ADMIN_PASSWORD=your-strong-admin-password
    DB_ROOT_PASSWORD=your-strong-mysql-root-password
    DB_NC_PASSWORD=your-strong-mysql-nc-password
    REDIS_PASSWORD=your-strong-redis-password
    ```

3. **System Settings**:
    ```bash
    PUID=1000  # Run 'id' to get your user ID
    PGID=1000  # Run 'id' to get your group ID
    TZ=Africa/Casablanca  # Your timezone
    ```

### Post-Installation Configuration

**Important: Stop Docker containers before manual configuration:**

```bash
docker compose down
```

#### SWAG Configuration

1. **DNS Configuration** (for DuckDNS):

    ```bash
    # Edit: /opt/commune/swag/config/dns-conf/duckdns.ini
    dns_duckdns_token=your-duckdns-token
    ```

2. **Nginx Reverse Proxy**:
    ```bash
    cd /opt/commune/swag/config/nginx/proxy-confs
    cp nextcloud.subfolder.conf.sample nextcloud.subfolder.conf
    cp jellyfin.subfolder.conf.sample jellyfin.subfolder.conf
    ```

#### Nextcloud Configuration

Edit `/opt/commune/nextcloud/config/www/nextcloud/config/config.php`:

```php
'trusted_domains' => array(
    0 => 'yourdomain.duckdns.org',
    1 => '192.168.x.x',  # Your local IP
),
'trusted_proxies' => array(
    0 => 'swag',
),
'overwritewebroot' => '/nextcloud',
'overwriteprotocol' => 'https',
'memcache.local' => '\\OC\\Memcache\\APCu',
'memcache.distributed' => '\\OC\\Memcache\\Redis',
'memcache.locking' => '\\OC\\Memcache\\Redis',
'redis' => array(
    'host' => 'redis',
    'port' => 6379,
    'timeout' => 0.0,
    'read_timeout' => 1.0,
    'password' => 'your-redis-password',
),
```

**PHP Configuration** - Edit `/opt/commune/nextcloud/config/php/php-local.ini`:

```ini
upload_max_filesize = 10G
post_max_size = 10G
max_execution_time = 3600
memory_limit = 1G
```

#### Jellyfin Configuration

- Access the web interface during first startup
- Complete the Setup Wizard
- Configure media libraries pointing to `/data` (mapped to Nextcloud Media folder)
- Enable hardware transcoding if supported by your hardware

## External Storage Setup

### Mounting USB/External Drives

1. **Manual Mount**:

    ```bash
    sudo mount -o uid=1000,gid=1000 /dev/sdX1 /opt/commune/nextcloud/data/admin/files/External
    ```

2. **Scan Files in Nextcloud**:

    ```bash
    docker exec nextcloud occ files:scan --path="/admin/files/External"
    # Or scan all files:
    docker exec nextcloud occ files:scan --all
    ```

3. **Automatic Mount Service** - Create `/etc/systemd/system/mount-usb.service`:

    ```ini
    [Unit]
    Description=Mount USB drive for Nextcloud
    DefaultDependencies=no
    Before=docker.service
    After=local-fs.target

    [Service]
    Type=oneshot
    ExecStart=/usr/bin/mount -o uid=1000,gid=1000 /dev/sdX1 /opt/commune/nextcloud/data/admin/files/External
    ExecStartPost=/bin/echo "USB mounted successfully"
    RemainAfterExit=yes

    [Install]
    WantedBy=multi-user.target
    ```

    Enable the service:

    ```bash
    sudo systemctl enable mount-usb.service
    sudo systemctl start mount-usb.service
    ```

### Restart Services

```bash
docker compose up -d
```

## Network Access

### Local Access

- **Nextcloud**: `https://yourdomain.duckdns.org/nextcloud`
- **Jellyfin**: `https://yourdomain.duckdns.org/jellyfin`
- **Direct Jellyfin** (if proxy issues): `http://your-local-ip:8099`

### WAN Access Setup

1. **Router Configuration**:

    - Forward port 80 → your server's local IP:80
    - Forward port 443 → your server's local IP:443

2. **Domain DNS**:

    - Configure your domain to point to your public IP
    - For DuckDNS, this updates automatically

3. **Firewall Configuration**:
    ```bash
    sudo ufw allow 80/tcp
    sudo ufw allow 443/tcp
    sudo ufw allow 22/tcp  # Keep SSH access
    sudo ufw enable
    ```

## Maintenance

### Regular Tasks

```bash
# Update containers
docker compose pull
docker compose up -d

# View logs
docker compose logs -f [service-name]

# Backup configuration
sudo tar -czf homelab-backup-$(date +%Y%m%d).tar.gz /opt/commune/

# Nextcloud maintenance
docker exec nextcloud occ maintenance:mode --on
docker exec nextcloud occ upgrade
docker exec nextcloud occ maintenance:mode --off
```

### Monitoring

```bash
# Check service status
docker compose ps

# Check resource usage
docker stats

# Check disk usage
df -h /opt/commune/
```

## Troubleshooting

### Common Issues

1. **Jellyfin mobile app connection issues**:

    - Use direct port access: `http://your-ip:8099`
    - Check firewall settings

2. **Nextcloud file scan not working**:

    - Verify mount permissions
    - Run manual scan: `docker exec nextcloud occ files:scan --all`

3. **SSL certificate issues**:

    - Check SWAG logs: `docker logs swag`
    - Verify domain DNS resolution
    - Check DuckDNS token validity

4. **Database connection errors**:
    - Check MariaDB logs: `docker logs mariadb`
    - Verify database credentials in `.env`

## Security Considerations

1. **Strong Passwords**: Use unique, complex passwords for all services
2. **Regular Updates**: Keep containers and host system updated
3. **Firewall**: Only open necessary ports
4. **SSL Certificates**: Ensure HTTPS is working properly
5. **Backup Strategy**: Regular backups of configuration and data
6. **Network Isolation**: Consider VPN access for enhanced security

## What I Learned

### Technical Skills

- **Docker & Docker Compose**: Container orchestration and networking
- **Reverse Proxy**: Nginx configuration and SSL termination
- **SSL/TLS**: Let's Encrypt certificate automation
- **Linux System Administration**: Service management and security
- **Networking**: Port forwarding, DNS configuration, firewall setup

### Key Concepts

- **Infrastructure as Code**: Reproducible deployments with Docker Compose
- **Security Best Practices**: Defense in depth, principle of least privilege
- **Self-hosting Benefits**: Data privacy, cost savings, learning opportunities
- **System Integration**: How different services work together in a homelab environment

## License

This project is open source and available under the [MIT License](./LICENSE).
