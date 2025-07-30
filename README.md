# Quick Start
```bash
cp example.env .env
vi .env
# Edit with real values


# Start traefik first
docker compose -f compose.proxy.yml --env-file .env up -d

# Allow otel to get metrics from prosody
docker network inspect proxy-network | grep "subnet" -i
vi .env
# PROSODY_TRUSTED_PROXIES_CIDR <-- Update this value.

# Keycloak
docker compose -f keycloak-scripts/compose.yml --env-file .env up -d

# Prosody + Jicofo
docker compose -f config/compose.yml --env-file .env up -d

# JVB
docker compose -f videobridge/compose.jvb.yml --env-file .env up -d
```


# Infra Provisioning

**Install Digital Ocean CLI tool:**
```bash
# macOS
brew install doctl

# Linux
curl -OL https://github.com/digitalocean/doctl/releases/latest/download/doctl-<version>-linux-amd64.tar.gz
tar xf doctl-<version>-linux-amd64.tar.gz
sudo mv doctl /usr/local/bin

# Windows (PowerShell)
Invoke-WebRequest -Uri https://github.com/digitalocean/doctl/releases/latest/download/doctl-<version>-windows-amd64.zip -OutFile doctl.zip
Expand-Archive doctl.zip

doctl auth init
# Follow prompts to enter your DigitalOcean API token
```

**Create a new droplet:**
```bash
# Upload your public key (replace with your actual key path and name)
doctl compute ssh-key import my-laptop-key --public-key-file ~/.ssh/id_rsa.pub

# Verify the key was uploaded
doctl compute ssh-key list

# List available images and sizes
doctl compute image list --public | grep ubuntu
doctl compute size list
doctl compute region list

# Create droplet with your SSH key
doctl compute droplet create my-dev-server \
  --image ubuntu-24-04-x64 \
  --size s-2vcpu-4gb \
  --region blr1 \
  --ssh-keys $(doctl compute ssh-key list --format ID --no-header) \
  --wait

# Get the droplet's IP address
doctl compute droplet list --format Name,PublicIPv4

# Replace YOUR_DROPLET_IP with the actual IP
ssh root@YOUR_DROPLET_IP -i path/to/keyfile
```

# Migration Guide

To migrate from old server to new server:

```bash
# === ON OLD SERVER ===
# 1. Create database backup
docker exec postgres pg_dump -U keycloak -d keycloak > keycloak_backup.sql

# 2. Export Docker volume (if you prefer volume backup)
docker run --rm -v postgres_data:/data -v $(pwd):/backup alpine tar czf /backup/postgres_data_backup.tar.gz -C /data .

# 3. Download backup files to your local machine
scp root@OLD_SERVER_IP:~/keycloak_backup.sql ./
# OR: scp root@OLD_SERVER_IP:~/postgres_data_backup.tar.gz ./

# 4. Verify backup files exist and have content
ls -lh keycloak_backup.sql postgres_data_backup.tar.gz
echo "PostgreSQL dump size: $(wc -l < keycloak_backup.sql) lines"
echo "Volume backup size: $(du -h postgres_data_backup.tar.gz | cut -f1)"

# === ON NEW SERVER ===
# 1. Upload backup file
scp ./keycloak_backup.sql root@NEW_SERVER_IP:~/
# OR: scp ./postgres_data_backup.tar.gz root@NEW_SERVER_IP:~/

# 2. Setup new server with config files, start only Postgres first
docker compose -f keycloak-scripts/compose.yml --env-file .env up -d postgres

# 3. Wait for Postgres to be ready, then restore
sleep 30
docker exec -i postgres psql -U keycloak -d keycloak < keycloak_backup.sql

# OR for volume restore:
# docker compose -f keycloak-scripts/compose.yml --env-file .env down
# docker run --rm -v postgres_data:/data -v $(pwd):/backup alpine tar xzf /backup/postgres_data_backup.tar.gz -C /data

# 4. Start all remaining services in order
docker compose -f compose.proxy.yml --env-file .env up -d
docker compose -f keycloak-scripts/compose.yml --env-file .env up -d
docker compose -f config/compose.yml --env-file .env up -d  
docker compose -f videobridge/compose.jvb.yml --env-file .env up -d
```

## Verification
After migration, verify everything works:
```bash
# Check all containers are healthy
docker ps --format "table {{.Names}}\t{{.Status}}"

# Verify user data exists in Keycloak database
docker exec postgres psql -U keycloak -d keycloak -c "SELECT count(*) FROM user_entity WHERE realm_id = (SELECT id FROM realm WHERE name = 'jitsi');"

# Check logs for any errors
docker logs prosody --tail 20
docker logs keycloak --tail 20
```
