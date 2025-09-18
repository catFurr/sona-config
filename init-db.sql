-- Database initialization script for PostgreSQL
-- This script creates the necessary users and permissions for Keycloak and Cloud Functions
-- This script is idempotent and can be run multiple times safely

-- Create the 'cf' user for cloud functions if it doesn't exist
-- This user can read from all schemas but only write to the sonacove schema
-- The CF_PASSWORD variable should be set when calling this script

-- Create or update the 'cf' user for cloud functions
-- Handle existing user gracefully
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'cf') THEN
        CREATE USER cf WITH PASSWORD :'CF_PASSWORD';
    ELSE
        -- Update password if user exists
        ALTER USER cf WITH PASSWORD :'CF_PASSWORD';
    END IF;
END
$$;

-- Grant connect permission to the database
GRANT CONNECT ON DATABASE keycloak TO cf;

-- Grant schema creation privileges on the database
GRANT CREATE ON DATABASE keycloak TO cf;

-- Grant usage on the public schema (for reading Keycloak tables)
GRANT USAGE ON SCHEMA public TO cf;

-- Grant select permissions on all existing tables in public schema (for Keycloak tables)
GRANT SELECT ON ALL TABLES IN SCHEMA public TO cf;

-- Grant select permissions on all future tables in public schema
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO cf;

-- Grant select permissions on sequences in public schema (needed for reading)
GRANT SELECT ON ALL SEQUENCES IN SCHEMA public TO cf;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON SEQUENCES TO cf;

-- Create the sonacove schema for our application tables
CREATE SCHEMA IF NOT EXISTS sonacove;

-- Grant all permissions on sonacove schema to cf user
GRANT ALL PRIVILEGES ON SCHEMA sonacove TO cf;

-- Grant all permissions on all tables in sonacove schema to cf user
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA sonacove TO cf;

-- Grant all permissions on all future tables in sonacove schema to cf user
ALTER DEFAULT PRIVILEGES IN SCHEMA sonacove GRANT ALL PRIVILEGES ON TABLES TO cf;

-- Grant usage on all sequences in sonacove schema to cf user
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA sonacove TO cf;

-- Grant all privileges on all future sequences in sonacove schema to cf user
ALTER DEFAULT PRIVILEGES IN SCHEMA sonacove GRANT ALL PRIVILEGES ON SEQUENCES TO cf;

-- Ensure the keycloak user has full permissions on the public schema (default behavior)
-- This is already handled by PostgreSQL defaults, but we make it explicit
GRANT ALL PRIVILEGES ON SCHEMA public TO keycloak;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO keycloak;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO keycloak;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL PRIVILEGES ON TABLES TO keycloak;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL PRIVILEGES ON SEQUENCES TO keycloak;

-- Allow keycloak user to also read from sonacove schema (useful for joins/queries)
GRANT USAGE ON SCHEMA sonacove TO keycloak;
GRANT SELECT ON ALL TABLES IN SCHEMA sonacove TO keycloak;
ALTER DEFAULT PRIVILEGES IN SCHEMA sonacove GRANT SELECT ON TABLES TO keycloak;

-- Create a drizzle schema for migration tracking
CREATE SCHEMA IF NOT EXISTS drizzle;

-- Grant permissions on drizzle schema to cf user (for migrations)
GRANT ALL PRIVILEGES ON SCHEMA drizzle TO cf;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA drizzle TO cf;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA drizzle TO cf;
ALTER DEFAULT PRIVILEGES IN SCHEMA drizzle GRANT ALL PRIVILEGES ON TABLES TO cf;
ALTER DEFAULT PRIVILEGES IN SCHEMA drizzle GRANT ALL PRIVILEGES ON SEQUENCES TO cf;
