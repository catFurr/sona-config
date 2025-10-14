# Sonacove Infrastructure with Ansible

This directory contains Ansible playbooks and roles for managing Sonacove Meets infrastructure. The setup provides idempotent, declarative infrastructure management with centralized configuration via Ansible Vault.

## Prerequisites

### Local Machine Requirements

1. **Ansible**: Install Ansible 2.9+ with required collections
   ```bash
   pip install ansible
   ansible-galaxy collection install community.crypto community.docker
   ```

2. **SSH Access**: Ensure you have SSH key access to target servers

3. **Vault Password**: Create a `.vault_pass` file with your vault password (or use `--ask-vault-pass`)

### Server Requirements

- Ubuntu 20.04+ (tested on Ubuntu 22.04)
- Root or sudo access
- Internet connectivity for package installation

## Quick Start

### 1. Set up Vault Password

Create a vault password file:
```bash
echo "your_vault_password" > .vault_pass
chmod 600 .vault_pass
```

### 2. Configure Environment Variables

Edit the vault files for your environment:
```bash
# For staging
ansible-vault edit inventory/staging/group_vars/all/vault.yml

# For production  
ansible-vault edit inventory/production/group_vars/all/vault.yml
```

### 3. Update Inventory

Edit the inventory files to match your servers:
```bash
# Edit staging inventory
vim inventory/staging/hosts.yml

# Edit production inventory
vim inventory/production/hosts.yml
```

### 4. Run Playbooks

**Provision a new server:**
```bash
ansible-playbook -i inventory/staging playbooks/site.yml --tags provision
```

**Update existing server:**
```bash
ansible-playbook -i inventory/staging playbooks/site.yml --tags update
```

## Directory Structure

```
ansible/
├── playbooks/                 # Main playbooks
│   ├── site.yml              # Orchestration playbook
│   ├── provision.yml         # New server setup
│   └── update.yml            # Update existing servers
├── roles/                    # Ansible roles
│   ├── common/               # Base system setup
│   ├── docker/               # Docker installation
│   ├── bun/                  # Bun runtime
│   ├── nginx/                # Nginx configuration
│   ├── certbot/              # SSL certificates
│   ├── sonacove-config/      # Config compilation
│   └── sonacove-services/    # Docker Compose services
├── inventory/                # Environment inventories
│   ├── staging/
│   │   ├── hosts.yml
│   │   └── group_vars/all/vault.yml
│   └── production/
│       ├── hosts.yml
│       └── group_vars/all/vault.yml
└── ansible.cfg               # Ansible configuration
```

## Roles Overview

### common
- Installs base packages (curl, git, build-essential, etc.)
- Configures firewall (ufw) with required ports
- Sets up TCP keepalive tuning
- Creates sonacove user and SSH keys
- Configures timezone and hostname

### docker
- Installs Docker Engine and Docker Compose
- Configures Docker daemon with log rotation
- Sets up Docker service and user groups
- Verifies installation

### bun
- Installs Bun runtime for config compilation
- Sets up PATH environment variables
- Creates system-wide symlinks

### nginx
- Installs and configures Nginx
- Sets up SSL directories and webroot for Certbot
- Configures log rotation
- Creates base nginx.conf with security headers

### certbot
- Installs Certbot with webroot plugin
- Generates SSL certificates for all domains
- Creates symbolic links to standard SSL locations
- Sets up automatic renewal
- Generates DH parameters

### sonacove-config
- Deploys sona-config repository files
- Installs Bun dependencies
- Compiles nginx configurations using nginx-compiler.ts
- Deploys compiled configs to /etc/nginx/conf.d/

### sonacove-services
- Deploys Docker Compose files and configurations
- Templates .env file from vault variables
- Starts Docker Compose services
- Verifies service health

## Environment Variables

All configuration is stored in encrypted vault files. Key variables include:

### Required Variables
- `vault_xmpp_domain`: Main XMPP domain (e.g., "staj.sonacove.com")
- `vault_kc_hostname`: Keycloak hostname
- `vault_kc_db_password`: PostgreSQL password
- `vault_jicofo_auth_password`: Jicofo authentication password
- `vault_jvb_auth_password`: JVB authentication password

### Optional Variables
- `vault_posthog_domain`: PostHog proxy domain
- `vault_cf_*`: Cloudflare configuration
- `vault_jvb_*`: JVB-specific settings

## Common Operations

### Provision New Server
```bash
ansible-playbook -i inventory/staging playbooks/provision.yml
```

### Update Existing Server
```bash
ansible-playbook -i inventory/staging playbooks/update.yml
```

### Run Specific Role
```bash
ansible-playbook -i inventory/staging playbooks/provision.yml --tags nginx
```

### Dry Run (Check Mode)
```bash
ansible-playbook -i inventory/staging playbooks/provision.yml --check
```

### Verbose Output
```bash
ansible-playbook -i inventory/staging playbooks/provision.yml -vvv
```

### Certificate Renewal
```bash
ansible-playbook -i inventory/staging playbooks/update.yml --tags certbot
```

## Vault Management

### Edit Vault Files
```bash
# Staging
ansible-vault edit inventory/staging/group_vars/all/vault.yml

# Production
ansible-vault edit inventory/production/group_vars/all/vault.yml
```

### Change Vault Password
```bash
ansible-vault rekey inventory/staging/group_vars/all/vault.yml
```

### View Vault Contents
```bash
ansible-vault view inventory/staging/group_vars/all/vault.yml
```

## Troubleshooting

### Common Issues

1. **SSH Connection Failed**
   - Verify SSH key is in `~/.ssh/authorized_keys` on target server
   - Check firewall allows SSH (port 22)
   - Ensure correct username in inventory

2. **Certificate Generation Failed**
   - Verify domain DNS points to server
   - Check nginx is running and accessible on port 80
   - Ensure webroot directory exists and is writable

3. **Docker Services Won't Start**
   - Check Docker daemon is running: `systemctl status docker`
   - Verify user is in docker group
   - Check Docker Compose file syntax

4. **Nginx Configuration Errors**
   - Test nginx config: `nginx -t`
   - Check compiled configs in `/etc/nginx/conf.d/`
   - Verify SSL certificates exist and are readable

### Debug Commands

```bash
# Check Ansible connectivity
ansible -i inventory/staging all -m ping

# Test specific role
ansible-playbook -i inventory/staging playbooks/provision.yml --tags nginx --check

# Verbose output for debugging
ansible-playbook -i inventory/staging playbooks/provision.yml -vvv

# Check service status on server
ansible -i inventory/staging all -m systemd -a "name=nginx state=started"
```

### Log Files

- Ansible logs: Check terminal output or use `-vvv` for verbose logging
- Nginx logs: `/var/log/nginx/access.log` and `/var/log/nginx/error.log`
- Docker logs: `docker logs <container_name>`
- System logs: `journalctl -u nginx`, `journalctl -u docker`

## Security Considerations

1. **Vault Password**: Store `.vault_pass` securely and never commit to git
2. **SSH Keys**: Use strong SSH keys and consider key rotation
3. **Firewall**: Only open required ports (22, 80, 443, 5222, 5432, 8443, 10000/udp)
4. **SSL Certificates**: Let's Encrypt certificates auto-renew every 60 days
5. **User Permissions**: Services run with minimal required privileges

## Adding New Environments

1. Create new inventory directory:
   ```bash
   mkdir -p inventory/new-env/group_vars/all
   ```

2. Copy and modify inventory files:
   ```bash
   cp inventory/staging/hosts.yml inventory/new-env/hosts.yml
   cp inventory/staging/group_vars/all/vault.yml inventory/new-env/group_vars/all/vault.yml
   ```

3. Edit the new vault file:
   ```bash
   ansible-vault edit inventory/new-env/group_vars/all/vault.yml
   ```

4. Update hosts.yml with correct server details

5. Run playbooks:
   ```bash
   ansible-playbook -i inventory/new-env playbooks/provision.yml
   ```

## Migration from Bun Scripts

The Ansible setup replaces the previous Bun-based installation scripts:

- `setup/install.ts` → Ansible roles (certbot, nginx, sonacove-services)
- `setup/nginx-compiler.ts` → sonacove-config role
- Manual `.env` management → Ansible Vault

### Benefits of Ansible Approach

1. **Idempotency**: Run multiple times safely
2. **Declarative**: Describe desired state, not steps
3. **Error Handling**: Built-in retry and failure handling
4. **Scalability**: Manage multiple servers easily
5. **Auditability**: Clear change tracking
6. **Testing**: Dry-run and check modes
7. **Modularity**: Reusable roles for different components

## Future Enhancements

- Kubernetes migration for JVB (using `kubernetes.core` collection)
- CI/CD integration with GitHub Actions
- Automated testing infrastructure with Selenium Grid
- Monitoring and alerting setup
- Backup and disaster recovery procedures
