-- ============================================================================
-- DB SETUP SCRIPT: RBAC Configuration (RDS Production Ready)
-- ============================================================================
-- NOTE: In local development, you can use explicit passwords.
-- In AWS RDS, we use Terraform-generated random passwords stored in Secrets Manager.
--
-- HOW TO GET PASSWORDS FOR AWS:
-- 1. Master:  aws secretsmanager get-secret-value --secret-id $(terraform -chdir=terraform output -raw master_password_secret_arn) --query SecretString --output text
-- 2. Migrator: aws secretsmanager get-secret-value --secret-id $(terraform -chdir=terraform output -raw tmpower_password_secret_arn) --query SecretString --output text
-- 3. App:      aws secretsmanager get-secret-value --secret-id $(terraform -chdir=terraform output -raw tmapp_password_secret_arn) --query SecretString --output text
-- ============================================================================

-- 1. CREATE SCHEMAS
CREATE SCHEMA IF NOT EXISTS tmschema;

-- 2. CREATE GROUP ROLES (Permission Containers)
DO $$ 
BEGIN
  IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'migration_grp') THEN
    CREATE ROLE migration_grp NOLOGIN;
  END IF;
  
  IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'application_grp') THEN
    CREATE ROLE application_grp NOLOGIN;
  END IF;

  IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'developer_grp') THEN
    CREATE ROLE developer_grp NOLOGIN;
  END IF;
END $$;

-- 3. ASSIGN PERMISSIONS TO GROUPS
GRANT ALL ON SCHEMA tmschema TO migration_grp;
GRANT USAGE ON SCHEMA tmschema TO application_grp;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA tmschema TO application_grp;
ALTER DEFAULT PRIVILEGES IN SCHEMA tmschema GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO application_grp;
GRANT USAGE ON SCHEMA tmschema TO developer_grp;
GRANT SELECT ON ALL TABLES IN SCHEMA tmschema TO developer_grp;

-- 4. CREATE USERS (Login Roles)
-- Replace 'PLACEHOLDER' with the passwords fetched from Secrets Manager
DO $$ 
BEGIN
  IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'tmpower') THEN
    CREATE USER tmpower WITH PASSWORD 'PLACEHOLDER';
  ELSE
    ALTER USER tmpower WITH PASSWORD 'PLACEHOLDER';
  END IF;

  IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'tmapp') THEN
    CREATE USER tmapp WITH PASSWORD 'PLACEHOLDER';
  ELSE
    ALTER USER tmapp WITH PASSWORD 'PLACEHOLDER';
  END IF;

  IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'tmdev') THEN
    CREATE USER tmdev WITH PASSWORD 'PLACEHOLDER';
  ELSE
    ALTER USER tmdev WITH PASSWORD 'PLACEHOLDER';
  END IF;
END $$;

-- 5. ASSIGN USERS TO GROUPS
GRANT migration_grp TO tmpower;
GRANT application_grp TO tmapp;
GRANT developer_grp TO tmdev;

-- 6. SECURITY HARDENING
REVOKE ALL ON SCHEMA public FROM PUBLIC;
REVOKE ALL ON DATABASE event_db FROM PUBLIC;
GRANT CONNECT ON DATABASE event_db TO tmpower, tmapp, tmdev;
