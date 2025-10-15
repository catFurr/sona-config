
# Backend configuration for Sonacove Meets

This repository contains all the setup configuration for the different services used to enable the meeting platform.

All the servers use Ubuntu. Our servers are:
- Staging server: VPS on Hostinger for development and testing.
- Main server: VPS on Hostinger with production prosody and keycloak.
- Main videobridge: Linode cloud VM running the JVB.


# Prerequisites

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


# Quick Start

```bash
cp example.env .env
vi .env
# Edit with real values

# Setup NGINX and SSL and start all services
bun install --frozen-lockfile
bun setup/install

# Start videobridge seperately
docker compose -f videobridge/compose.jvb.yml --env-file .env up -d
```
