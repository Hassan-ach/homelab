#!/bin/bash

# Homelab Installation Script
# Exit on any error
set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if script is run with sudo
if [ "$(id -u)" != "0" ]; then
    print_error "This script must be run with sudo."
    exit 1
fi

# Get the real user (not root when using sudo)
REAL_USER=${SUDO_USER:-$USER}
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)

print_status "Running as: $REAL_USER"

# Check OS compatibility
if ! command -v apt-get &> /dev/null; then
    print_error "This script is designed for Ubuntu/Debian systems only."
    exit 1
fi

# Update and install prerequisites
print_status "Updating system and installing prerequisites..."
apt-get update && apt-get upgrade -y
apt-get install -y curl git nano ca-certificates gnupg lsb-release ufw

# Check if Docker is already installed
if command -v docker &> /dev/null; then
    print_warning "Docker is already installed. Skipping Docker installation."
else
    print_status "Installing Docker..."

    # Remove any old Docker installations
    apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true

    # Add Docker's official GPG key
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc

    # Add Docker repository
    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
        $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
        tee /etc/apt/sources.list.d/docker.list > /dev/null

    # Install Docker
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    print_status "Docker installed successfully."
fi

# Add user to docker group
print_status "Adding user $REAL_USER to docker group..."
usermod -aG docker "$REAL_USER"

# Start and enable Docker service
systemctl start docker
systemctl enable docker

# Verify Docker installation
print_status "Verifying Docker installation..."
docker --version
docker compose version

# Check for required files
if [ ! -f "docker-compose.yml" ]; then
    print_error "docker-compose.yml not found in current directory."
    print_error "Please ensure you're running this script from the correct directory."
    exit 1
fi

if [ ! -f ".env.example" ]; then
    print_error ".env.example file not found."
    exit 1
fi

# Check if .env exists, if not help create it
if [ ! -f ".env" ]; then
    print_warning ".env file not found."
    read -p "Would you like to copy .env.example to .env now? (y/n): " CREATE_ENV
    if [ "$CREATE_ENV" = "y" ]; then
        cp .env.example .env
        print_status ".env file created from .env.example"
        print_warning "Please edit .env file with your actual values before continuing."
        print_warning "Pay special attention to passwords, domain, and DuckDNS token."
        nano .env
    else
        print_error "Please create .env file and populate it with your variables."
        exit 1
    fi
fi

# Validate .env file
print_status "Validating .env file..."
source .env

# Check critical variables
MISSING_VARS=()
[ -z "$URL" ] && MISSING_VARS+=("URL")
[ -z "$DUCKDNSTOKEN" ] && MISSING_VARS+=("DUCKDNSTOKEN")
[ -z "$EMAIL" ] && MISSING_VARS+=("EMAIL")
[ -z "$ADMIN_PASSWORD" ] && MISSING_VARS+=("ADMIN_PASSWORD")
[ -z "$DB_ROOT_PASSWORD" ] && MISSING_VARS+=("DB_ROOT_PASSWORD")
[ -z "$DB_NC_PASSWORD" ] && MISSING_VARS+=("DB_NC_PASSWORD")
[ -z "$REDIS_PASSWORD" ] && MISSING_VARS+=("REDIS_PASSWORD")

if [ ${#MISSING_VARS[@]} -gt 0 ]; then
    print_error "Missing required environment variables:"
    printf '%s\n' "${MISSING_VARS[@]}"
    print_error "Please update your .env file and try again."
    exit 1
fi

# Warn about default values
if [ "$ADMIN_PASSWORD" = "your-admin-password" ]; then
    print_warning "You're using a default password. Please update .env with secure passwords."
fi

# Create volume directories
print_status "Creating volume directories..."
COMMUNE_DIR=${COMMUNE_DIR%/}  # Remove trailing slash if present

# Create directories properly
mkdir -p "${COMMUNE_DIR}/nextcloud/"{config,data,logs}
mkdir -p "${COMMUNE_DIR}/jellyfin/"{config,cache,logs}
mkdir -p "${COMMUNE_DIR}/mysql/"{data,config,logs}
mkdir -p "${COMMUNE_DIR}/redis/"{data,logs}
mkdir -p "${COMMUNE_DIR}/swag/"{config,logs}

# Set proper ownership
chown -R "$REAL_USER":"$REAL_USER" "$COMMUNE_DIR"

print_status "Volume directories created and ownership set."

# Configure firewall
print_status "Configuring UFW firewall..."
ufw --force enable
ufw allow 80/tcp
ufw allow 443/tcp
ufw reload

print_status "Firewall configured to allow HTTP (80) and HTTPS (443)."

# Start services
print_status "Starting Docker Compose services..."
sudo -u "$REAL_USER" docker compose up -d

# Wait a moment for services to start
sleep 5

# Check service status
print_status "Checking service status..."
sudo -u "$REAL_USER" docker compose ps

# Provide post-installation information
echo ""
echo "=========================================="
echo "🎉 INSTALLATION COMPLETE! 🎉"
echo "=========================================="
echo ""
print_status "Your services should be accessible at:"
echo "  • Nextcloud: https://nextcloud.$URL"
echo "  • Jellyfin:  https://jellyfin.$URL"
echo ""
print_warning "IMPORTANT NEXT STEPS:"
echo "  1. Wait 2-3 minutes for SSL certificates to be issued"
echo "  2. Configure port forwarding on your router:"
echo "     - Forward port 80 to ${HOSTNAME}:80"
echo "     - Forward port 443 to ${HOSTNAME}:443"
echo "  3. Log out and log back in for Docker group changes to take effect"
echo ""
print_status "USEFUL COMMANDS:"
echo "  • Check service status:    docker compose ps"
echo "  • View all logs:          docker compose logs"
echo "  • View SWAG logs:         docker compose logs swag"
echo "  • Restart services:       docker compose restart"
echo "  • Stop services:          docker compose down"
echo "  • Update services:        docker compose pull && docker compose up -d"
echo ""
print_status "TROUBLESHOOTING:"
echo "  • If services fail to start, check: docker compose logs"
echo "  • For SSL issues, check SWAG logs: docker compose logs swag"
echo "  • Ensure your DuckDNS domain points to your public IP"
echo "  • Verify ports 80/443 are forwarded in your router"
echo ""
echo "=========================================="
