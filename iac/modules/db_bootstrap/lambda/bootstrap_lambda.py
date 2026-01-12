import json
import os
import pg8000.native
import boto3

def get_secret(secret_arn):
    client = boto3.client('secretsmanager')
    response = client.get_secret_value(SecretId=secret_arn)
    return response['SecretString']

def handler(event, context):
    print("🚀 Starting Elite Database Bootstrapping...")
    
    # 1. Configuration from environment
    db_host = os.environ['DB_HOST']
    db_name = os.environ['DB_NAME']
    master_secret_arn = os.environ['MASTER_SECRET_ARN']
    tmpower_secret_arn = os.environ['TMPOWER_SECRET_ARN']
    tmapp_secret_arn = os.environ['TMAPP_SECRET_ARN']
    
    # 2. Fetch Secrets
    try:
        master_password = get_secret(master_secret_arn)
        tmpower_password = get_secret(tmpower_secret_arn)
        tmapp_password = get_secret(tmapp_secret_arn)
        print("✔️ Successfully fetched secrets.")
    except Exception as e:
        print(f"❌ Error fetching secrets: {e}")
        raise e

    # 3. Connect as Master
    try:
        con = pg8000.native.Connection(
            user="postgres", 
            host=db_host, 
            database=db_name, 
            password=master_password,
            timeout=10
        )
        print("✔️ Connected to RDS as Master.")
    except Exception as e:
        print(f"❌ Error connecting to database: {e}")
        raise e

    # 4. Execute RBAC Setup
    sql_commands = [
        "CREATE SCHEMA IF NOT EXISTS tmschema;",
        
        # Groups
        "DO $$ BEGIN IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'migration_grp') THEN CREATE ROLE migration_grp NOLOGIN; END IF; END $$;",
        "DO $$ BEGIN IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'application_grp') THEN CREATE ROLE application_grp NOLOGIN; END IF; END $$;",
        "DO $$ BEGIN IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'developer_grp') THEN CREATE ROLE developer_grp NOLOGIN; END IF; END $$;",
        
        # Permissions
        "GRANT ALL ON SCHEMA tmschema TO migration_grp;",
        "GRANT USAGE ON SCHEMA tmschema TO application_grp;",
        "GRANT USAGE ON SCHEMA tmschema TO developer_grp;",
        
        # Users
        f"DO $$ BEGIN IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'tmpower') THEN CREATE USER tmpower WITH PASSWORD '{tmpower_password}'; ELSE ALTER USER tmpower WITH PASSWORD '{tmpower_password}'; END IF; END $$;",
        f"DO $$ BEGIN IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'tmapp') THEN CREATE USER tmapp WITH PASSWORD '{tmapp_password}'; ELSE ALTER USER tmapp WITH PASSWORD '{tmapp_password}'; END IF; END $$;",
        
        # Role Membership
        "GRANT migration_grp TO tmpower;",
        "GRANT application_grp TO tmapp;",
        "GRANT tmpower, tmapp TO postgres;",

        # Set search_path for users
        "ALTER USER tmpower SET search_path TO tmschema, public;",
        "ALTER USER tmapp SET search_path TO tmschema, public;",
        
        # Ensure groups have permissions on future tables created by master
        "ALTER DEFAULT PRIVILEGES IN SCHEMA tmschema GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO application_grp;",
        "ALTER DEFAULT PRIVILEGES IN SCHEMA tmschema GRANT USAGE, SELECT ON SEQUENCES TO application_grp;",
        "ALTER DEFAULT PRIVILEGES IN SCHEMA tmschema GRANT SELECT ON TABLES TO developer_grp;",

        # Ensure groups have permissions on future tables created by tmpower (Flyway)
        "ALTER DEFAULT PRIVILEGES FOR ROLE tmpower IN SCHEMA tmschema GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO application_grp;",
        "ALTER DEFAULT PRIVILEGES FOR ROLE tmpower IN SCHEMA tmschema GRANT USAGE, SELECT ON SEQUENCES TO application_grp;",
        "ALTER DEFAULT PRIVILEGES FOR ROLE tmpower IN SCHEMA tmschema GRANT SELECT ON TABLES TO developer_grp;",

        # Grant permissions on existing tables
        "GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA tmschema TO application_grp;",
        "GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA tmschema TO application_grp;",
        "GRANT SELECT ON ALL TABLES IN SCHEMA tmschema TO developer_grp;",
        
        # Security Hardening
        "REVOKE ALL ON SCHEMA public FROM PUBLIC;",
        "GRANT CONNECT ON DATABASE event_db TO tmpower, tmapp;"
    ]

    try:
        for cmd in sql_commands:
            con.run(cmd)
        print("✔️ RBAC setup completed successfully.")
    except Exception as e:
        print(f"❌ Error executing SQL: {e}")
        raise e
    finally:
        con.close()

    return {
        'statusCode': 200,
        'body': json.dumps('Database bootstrapped successfully!')
    }
