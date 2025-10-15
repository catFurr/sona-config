
### SSL Certificate Setup

**With Ansible (Recommended):**
SSL certificates are automatically managed by the `certbot` role using Let's Encrypt with the webroot plugin. This avoids port conflicts and provides automatic renewal.

**Manual Setup (Legacy):**
Generate SSL certificates for your domains:

```bash
# Create certificate directory
sudo mkdir -p /etc/ssl/certs /etc/ssl/private

# Generate self-signed certificates (for testing)
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/ssl/private/{{YOUR_DOMAIN}}.key \
  -out /etc/ssl/certs/{{YOUR_DOMAIN}}.crt \
  -subj "/CN={{YOUR_DOMAIN}}"

# Generate DH parameters (optional but recommended)
sudo openssl dhparam -out /etc/ssl/certs/dhparam.pem 4096
```

### Automatic Certificate Renewal

Certbot automatically sets up renewal. To check the scheduled task:

```bash
# Check systemd timers
sudo systemctl list-timers | grep certbot

# Or check crontab
sudo crontab -l | grep certbot
```

### Alternative: Self-Signed Certificates (Testing Only)

For testing environments, you can generate self-signed certificates:

```bash
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/ssl/private/staj.sonacove.com.key \
  -out /etc/ssl/certs/staj.sonacove.com.crt \
  -subj "/CN=staj.sonacove.com"
```

### Certificate for PostHog Proxy (e.sonacove.com)

The PostHog proxy is served on `e.sonacove.com` (configured via `POSTHOG_DOMAIN`). Ensure a valid certificate and key exist at:
- `/etc/ssl/certs/e.sonacove.com.crt`
- `/etc/ssl/private/e.sonacove.com.key`

For testing, generate a self-signed cert (replace paths if needed):

```bash
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/ssl/private/e.sonacove.com.key \
  -out /etc/ssl/certs/e.sonacove.com.crt \
  -subj "/CN=e.sonacove.com"
```

In production, use your ACME/Certbot flow to issue and renew the certificate for `e.sonacove.com`. The Nginx template `proxy/posthog.conf` references these paths directly.