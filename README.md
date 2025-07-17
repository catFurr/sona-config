# Quick Start
```bash
cp example.env .env
vi .env
# Edit with real values

# JVB
docker compose -f videobridge/compose.jvb.yml --env-file .env up -d
```

**For Keycloak and Prosody services:**
```bash
# Start traefik first
docker run --rm -v traefik_acme_storage:/data alpine sh -c "touch /data/acme.json && chmod 600 /data/acme.json"
docker compose -f compose.proxy.yml --env-file .env up -d

# Keycloak
docker compose -f keycloak-scripts/compose.yml --env-file .env up -d

# Prosody + Jicofo
docker compose -f config/compose.yml --env-file .env up -d
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
