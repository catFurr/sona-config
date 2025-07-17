#!/bin/bash

set -e

usage() {
    echo "Usage: $0 <username>"
    echo "This script must be run as root to set up a new user and install Docker"
    exit 1
}

if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run as root"
    usage
fi

if [ $# -eq 0 ]; then
    echo "Error: Username not provided"
    usage
fi

USERNAME="$1"

apt update && apt upgrade -y

adduser "$USERNAME"
usermod -aG sudo "$USERNAME"

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

# cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup
# sed -i 's/#PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
# sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
# sed -i 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config
# systemctl restart sshd

apt install -y apt-transport-https ca-certificates curl software-properties-common
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt update
apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl start docker
systemctl enable docker
usermod -aG docker "$USERNAME"

curl -fsSL https://deb.nodesource.com/setup_lts.x | bash -
apt-get install -y nodejs

apt install -y git python3 python3-pip htop tree curl wget unzip

ufw allow ssh
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable

apt update && apt upgrade -y
apt autoremove -y
apt autoclean

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
