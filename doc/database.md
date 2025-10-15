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