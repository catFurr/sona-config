
# Backend configuration for Sonacove Meets

This repository contains all the setup configuration for the different services used to enable the meeting platform.

All the servers use Ubuntu. Our servers are:
- Staging server: VPS on Hostinger for development and testing.
- Main server: VPS on Hostinger with production prosody and keycloak.
- Main videobridge: Linode cloud VM running the JVB.

## Infrastructure Management

We use **Ansible** for idempotent, declarative infrastructure management. This provides:
- Automated server provisioning and updates
- Centralized configuration management via Ansible Vault
- Graceful error handling and rollback capabilities
- Easy scaling to multiple servers

### Quick Start with Ansible (Recommended)

```bash
# 1. Set up vault password
echo "your_vault_password" > ansible/.vault_pass
chmod 600 ansible/.vault_pass

# 2. Configure environment variables
ansible-vault edit ansible/inventory/staging/group_vars/all/vault.yml

# 3. Update inventory with your server details
vim ansible/inventory/staging/hosts.yml

# 4. Provision new server
cd ansible
ansible-playbook -i inventory/staging playbooks/site.yml --tags provision

# 5. Update existing server
ansible-playbook -i inventory/staging playbooks/site.yml --tags update
```

For detailed Ansible documentation, see [ansible/README.md](ansible/README.md).

## Legacy Manual Setup (Deprecated)

> **Note**: The manual setup below is deprecated in favor of Ansible. Use it only for development or if Ansible is not available.

### Prerequisites

1. Install Docker
2. Install NGINX
```bash
sudo apt update && sudo apt install nginx
```
3. Install certbot
```bash
sudo apt install certbot 
```
4. Install Bun
```bash
curl -fsSL https://bun.sh/install | bash
```

### Manual Quick Start

```bash
cp example.env .env
vi .env
# Edit with real values

# Setup NGINX and SSL and start all services
bun install --frozen-lockfile
bun setup/nginx-compiler
bun setup/install

# Start videobridge seperately
docker compose -f videobridge/compose.jvb.yml --env-file .env up -d
```

> **Migration**: If you're currently using the manual setup, consider migrating to Ansible for better maintainability and reliability.
