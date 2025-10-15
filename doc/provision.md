

ssh root@meet.sonacove.com

# Create ansible user
sudo useradd -m -s /bin/bash ansible
sudo usermod -aG sudo,docker ansible

# Set password and unlock account
sudo passwd ansible
# Enter password (e.g., "sonacove123")
# This is the same password set in the ansible vault
sudo usermod -U ansible


# Create SSH directory
sudo mkdir -p /home/ansible/.ssh
sudo chown ansible:ansible /home/ansible/.ssh
sudo chmod 700 /home/ansible/.ssh

# Copy your ansible public key
sudo cp /home/ibrahim/.ssh/ansible.pub /home/ansible/.ssh/authorized_keys
sudo chown ansible:ansible /home/ansible/.ssh/authorized_keys
sudo chmod 600 /home/ansible/.ssh/authorized_keys

