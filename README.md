# Quick Start

```bash
cp example.env .env
vi .env
# Edit with real values


# Start traefik and proxy infrastructure first
docker compose -f compose.proxy.yml --env-file .env up -d

# Start PostgreSQL and Drizzle Gateway
docker compose -f compose.postgres.yml --env-file .env up -d

# Wait for database to be ready
sleep 30

# Allow otel to get metrics from prosody
docker network inspect proxy-network | grep "subnet" -i
vi .env
# PROSODY_TRUSTED_PROXIES_CIDR <-- Update this value.

# Keycloak (depends on PostgreSQL)
docker compose -f keycloak-scripts/compose.yml --env-file .env up -d

# Prosody + Jicofo
docker compose -f config/compose.yml --env-file .env up -d

# JVB
docker compose -f videobridge/compose.jvb.yml --env-file .env up -d
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

# 2. Setup new server with config files, start Postgres and proxy first
docker compose -f compose.proxy.yml --env-file .env up -d
docker compose -f compose.postgres.yml --env-file .env up -d

# 3. Wait for Postgres to be ready, then restore
sleep 30
docker exec -i postgres psql -U keycloak -d keycloak < keycloak_backup.sql

# OR for volume restore:
# docker compose -f compose.postgres.yml --env-file .env down
# docker run --rm -v postgres_data:/data -v $(pwd):/backup alpine tar xzf /backup/postgres_data_backup.tar.gz -C /data

# 4. Start all remaining services in order
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

# Database Access for Cloud Functions

- **Direct access**: `staj.sonacove.com:5432` (SSL/TLS encrypted)
- **Management interface**: `https://staj.sonacove.com:4983` (Drizzle Gateway web UI)

### Cloud Function Connection

```javascript
import { drizzle } from "drizzle-orm/postgres-js";
import postgres from "postgres";

const client = postgres({
  host: "staj.sonacove.com",
  port: 5432,
  database: "keycloak",
  username: "keycloak",
  password: process.env.KC_DB_PASSWORD,
  ssl: { rejectUnauthorized: false }, // Traefik handles SSL termination
});

const db = drizzle(client);
```

## Drizzle Gateway Setup (Management Interface)

1. Access Drizzle Gateway web interface:

```bash
# Navigate to https://staj.sonacove.com:4983
# Use master password from DRIZZLE_MASTERPASS env var
```

2. Configure PostgreSQL connection in Drizzle Gateway:

   - **Host**: `postgres` (internal Docker network name)
   - **Port**: `5432`
   - **User**: `keycloak`
   - **Password**: Your `KC_DB_PASSWORD` value
   - **Database**: `keycloak`
   - **SSL**: Disable (internal network communication)


## Backup the database

```bash
docker exec postgres pg_dumpall -U keycloak > backup_$(date +%Y%m%d_%H%M%S).sql
```