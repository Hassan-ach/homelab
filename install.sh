#!/bin/bash

# Author: Hassan-ach
# GitHub: https://github.com/Hassan-ach/homelab

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Functions for colored output
info()    { echo -e "${GREEN}[INFO]${NC} $1"; }
warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
debug()   { echo -e "${BLUE}[DEBUG]${NC} $1"; }

# Banner
echo -e "${GREEN}"
echo "=============================================="
echo "    Homelab Docker Compose Setup Script"
echo "=============================================="
echo -e "${NC}"

# Verify script is run with sudo
if [ "$(id -u)" -ne 0 ]; then
    error "This script must be run with sudo privileges."
fi

# Get the real user (not root when using sudo)
REAL_USER="${SUDO_USER:-$(logname 2>/dev/null || echo 'unknown')}"
if [ "$REAL_USER" = "unknown" ]; then
    error "Cannot determine the real user. Please run with sudo from a regular user account."
fi

REAL_USER_HOME=$(eval echo "~$REAL_USER")
info "Real user: $REAL_USER"
info "Real user home: $REAL_USER_HOME"

# Check if we're on Ubuntu/Debian
if ! command -v apt-get >/dev/null 2>&1; then
    error "This script requires Ubuntu or Debian (apt-get not found)."
fi

# Check if .env file exists
if [ ! -f ".env" ]; then
    error ".env file not found in current directory. Please copy .env.example to .env and configure it first."
fi

# Load environment variables
info "Loading environment variables from .env file..."
set -a
# shellcheck source=/dev/null
source .env
set +a

# Validate required environment variables
required_vars=("COMMUNE_DIR" "PUID" "PGID" "TZ" "URL" "DUCKDNSTOKEN" "EMAIL" "ADMIN_NAME" "ADMIN_PASSWORD" "DB_ROOT_PASSWORD" "DB_NC_PASSWORD" "REDIS_PASSWORD")

for var in "${required_vars[@]}"; do
    if [ -z "${!var}" ]; then
        error "Required environment variable $var is not set in .env file."
    fi
done

info "Environment variables validated successfully."

# Validate docker-compose file exists
if [ ! -f "docker-compose.yml" ]; then
    error "docker-compose.yml not found in current directory."
fi

# Update system packages
info "Updating system packages..."
apt-get update && apt-get upgrade -y

# Install required packages
info "Installing required packages..."
apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    ufw \
    htop \
    tree

# Install Docker if not present
if ! command -v docker >/dev/null 2>&1; then
    info "Installing Docker..."

    # Remove old Docker installations
    apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true

    # Add Docker's official GPG key
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc

    # Add Docker repository
    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
        $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
        tee /etc/apt/sources.list.d/docker.list > /dev/null

    # Update package index and install Docker
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    # Add user to docker group
    usermod -aG docker "$REAL_USER"

    # Start and enable Docker service
    systemctl start docker
    systemctl enable docker

    info "Docker installed successfully."
else
    info "Docker is already installed."

    # Ensure user is in docker group
    if ! groups "$REAL_USER" | grep -q docker; then
        usermod -aG docker "$REAL_USER"
        info "Added $REAL_USER to docker group."
    fi
fi

# Verify Docker Compose is available
if ! docker compose version >/dev/null 2>&1; then
    error "Docker Compose is not available. Please check your Docker installation."
fi

info "Docker Compose version: $(docker compose version --short)"

# Setup directory structure
info "Creating directory structure at $COMMUNE_DIR..."

# Remove trailing slash if present
COMMUNE_DIR=${COMMUNE_DIR%/}

# Create directories with proper structure
directories=(
    "${COMMUNE_DIR}/nextcloud/config"
    "${COMMUNE_DIR}/nextcloud/data"
    "${COMMUNE_DIR}/nextcloud/logs"
    "${COMMUNE_DIR}/jellyfin/config"
    "${COMMUNE_DIR}/jellyfin/cache"
    "${COMMUNE_DIR}/jellyfin/logs"
    "${COMMUNE_DIR}/mysql/data"
    "${COMMUNE_DIR}/mysql/config"
    "${COMMUNE_DIR}/mysql/logs"
    "${COMMUNE_DIR}/redis/data"
    "${COMMUNE_DIR}/redis/logs"
    "${COMMUNE_DIR}/swag/config"
    "${COMMUNE_DIR}/swag/logs"
)

for dir in "${directories[@]}"; do
    mkdir -p "$dir"
    debug "Created directory: $dir"
done

# Set proper ownership
info "Setting proper ownership for directories..."
chown -R "$PUID:$PGID" "$COMMUNE_DIR"

# Set proper permissions
info "Setting proper permissions..."
find "$COMMUNE_DIR" -type d -exec chmod 755 {} \;
find "$COMMUNE_DIR" -type f -exec chmod 644 {} \;

# Configure UFW firewall
if command -v ufw >/dev/null 2>&1; then
    info "Configuring UFW firewall..."

    # Allow SSH (important!)
    ufw allow 22/tcp

    # Allow HTTP and HTTPS
    ufw allow 80/tcp
    ufw allow 443/tcp

    # Allow Jellyfin direct access (fallback)
    ufw allow 8099/tcp

    # Enable firewall (only if not already enabled)
    if ! ufw status | grep -q "Status: active"; then
        warning "Enabling UFW firewall. Make sure you can still access SSH!"
        ufw --force enable
    fi

    info "Firewall rules configured."
else
    warning "UFW not found. Please configure firewall manually."
fi

# Validate Docker Compose file
info "Validating Docker Compose configuration..."
if ! docker compose config >/dev/null 2>&1; then
    error "Docker Compose configuration is invalid. Please check your docker-compose.yml and .env files."
fi

# Start services
info "Starting Docker Compose stack..."
docker compose up -d

# Wait for services to start
info "Waiting for services to initialize..."
sleep 10

# Show service status
info "Service status:"
docker compose ps

# Show useful information
echo
info "✅ Installation completed successfully!"
echo
echo -e "${GREEN}📋 Quick Reference:${NC}"
echo -e "  • Nextcloud:     https://${URL}/nextcloud"
echo -e "  • Jellyfin:      https://${URL}/jellyfin"
echo -e "  • Jellyfin (direct): http://$(hostname -I | awk '{print $1}'):8099"
echo
echo -e "${YELLOW}⚠️  Important Notes:${NC}"
echo -e "  • Log out and back in for Docker group changes to take effect"
echo -e "  • Configure SWAG and Nextcloud as described in the README"
echo -e "  • Your data is stored in: $COMMUNE_DIR"
echo -e "  • UFW firewall has been configured and enabled"
echo
echo -e "${BLUE}📖 Next Steps:${NC}"
echo -e "  1. Configure SWAG DNS settings"
echo -e "  2. Set up Nextcloud reverse proxy configuration"
echo -e "  3. Complete Nextcloud and Jellyfin initial setup"
echo -e "  4. Configure port forwarding on your router for WAN access"
echo
echo -e "${GREEN}🎉 Happy self-hosting!${NC}"
