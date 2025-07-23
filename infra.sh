#!/bin/bash

set -e

usage() {
    echo "Usage: $0 <username> <password>"
    echo "This script must be run as root to set up a new user and install Docker"
    echo "Example: $0 john mypassword123"
    exit 1
}

if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run as root"
    usage
fi

if [ $# -lt 2 ]; then
    echo "Error: Username and password must be provided"
    usage
fi

USERNAME="$1"
PASSWORD="$2"

# Make apt completely non-interactive
export DEBIAN_FRONTEND=noninteractive
export DEBCONF_NONINTERACTIVE_SEEN=true

echo "Updating and upgrading system packages..."
apt update && apt upgrade -y

echo "Creating user $USERNAME..."
# Create user with password non-interactively
useradd -m -s /bin/bash "$USERNAME"
echo "$USERNAME:$PASSWORD" | chpasswd
usermod -aG sudo "$USERNAME"

# Configure SSH for the new user
sudo -u "$USERNAME" bash << EOF
set -e
cd /home/$USERNAME
mkdir -p .ssh
chmod 700 .ssh
touch .ssh/authorized_keys
chmod 600 .ssh/authorized_keys
EOF

# Copy SSH keys from root if they exist
if [ -f /root/.ssh/authorized_keys ]; then
    cp /root/.ssh/authorized_keys /home/$USERNAME/.ssh/authorized_keys
    chown $USERNAME:$USERNAME /home/$USERNAME/.ssh/authorized_keys
    chmod 600 /home/$USERNAME/.ssh/authorized_keys
fi

echo "Installing Docker..."
# Install Docker non-interactively
apt install -y apt-transport-https ca-certificates curl software-properties-common gnupg lsb-release
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt update
apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl start docker
systemctl enable docker
usermod -aG docker "$USERNAME"

echo "Installing Node.js..."
# Install Node.js non-interactively
curl -fsSL https://deb.nodesource.com/setup_lts.x | bash -
apt-get install -y nodejs

echo "Installing additional packages..."
# Install additional packages non-interactively
apt install -y git python3 python3-pip htop tree curl wget unzip

echo "Configuring firewall..."
# Configure firewall non-interactively - with proper error handling
# First, kill any existing ufw processes and reset if needed
pkill -f ufw || true
sleep 2
ufw --force reset || true
sleep 2

# Add firewall rules
ufw allow ssh
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow 10000/udp
ufw allow 9090/tcp
ufw allow 5222/tcp

# Enable firewall non-interactively
echo "y" | ufw enable

echo "Final system updates..."
# Final updates non-interactively
apt update && apt upgrade -y
apt autoremove -y
apt autoclean

echo "Cloning sona-config repository..."
# Clone the repository as the new user
sudo -u "$USERNAME" bash << EOF
set -e
cd /home/$USERNAME
git clone https://github.com/catFurr/sona-config.git
cd sona-config
cp example.env .env
EOF

echo ""
echo "=== VERIFICATION ==="

# Check if user was created
if id "$USERNAME" &>/dev/null; then
    echo "✓ User $USERNAME created successfully"
else
    echo "✗ User $USERNAME creation failed"
    exit 1
fi

# Check if SSH keys were copied
if [ -s /home/$USERNAME/.ssh/authorized_keys ]; then
    echo "✓ SSH keys copied to $USERNAME"
else
    echo "✗ SSH keys not found or empty"
    exit 1
fi

# Check if Docker is installed and running
if docker --version &>/dev/null && systemctl is-active docker &>/dev/null; then
    echo "✓ Docker installed and running"
else
    echo "✗ Docker installation or service failed"
    exit 1
fi

# Check if Node.js is installed
if node --version &>/dev/null && npm --version &>/dev/null; then
    echo "✓ Node.js and npm installed"
else
    echo "✗ Node.js installation failed"
    exit 1
fi

# Check if Python is installed
if python3 --version &>/dev/null && pip3 --version &>/dev/null; then
    echo "✓ Python3 and pip3 installed"
else
    echo "✗ Python3 installation failed"
    exit 1
fi

# Check if repository was cloned
if [ -d "/home/$USERNAME/sona-config" ]; then
    echo "✓ sona-config repository cloned successfully"
else
    echo "✗ Repository cloning failed"
    exit 1
fi

# Check if .env file was created
if [ -f "/home/$USERNAME/sona-config/.env" ]; then
    echo "✓ .env file created successfully"
else
    echo "✗ .env file creation failed"
    exit 1
fi

# Check if firewall is active
if ufw status | grep -q "Status: active"; then
    echo "✓ Firewall is active and configured"
else
    echo "⚠ Firewall may not be properly configured"
fi

echo ""
echo "=== SETUP COMPLETE ==="
echo "User: $USERNAME"
echo "Repository location: /home/$USERNAME/sona-config"
echo "Environment file: /home/$USERNAME/sona-config/.env"
echo ""
echo "Next steps:"
echo "1. SSH into the server as $USERNAME"
echo "2. Navigate to /home/$USERNAME/sona-config"
echo "3. Edit the .env file with your configuration"
echo "4. Run your deployment commands"
