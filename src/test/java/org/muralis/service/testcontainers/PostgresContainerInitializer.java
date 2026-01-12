package org.muralis.service.testcontainers;

import org.testcontainers.containers.PostgreSQLContainer;

/**
 * Utility class to initialize PostgreSQL container for tests.
 * 
 * For integration tests, we use a simplified setup:
 * - Single postgres user with full permissions (superuser)
 * - Schema tmschema created at container startup via init script
 * 
 * This differs from production where we have RBAC with multiple users.
 * The production db_setup.sql is tested via the actual AWS deployment.
 */
public class PostgresContainerInitializer {

    /**
     * Creates a PostgreSQL container configured for testing.
     * Uses postgres superuser for simplicity - all permissions available.
     * The tmschema is created at startup so Flyway migrations can use it.
     */
    public static PostgreSQLContainer<?> createContainer() {
        return new PostgreSQLContainer<>("postgres:16-alpine")
                .withDatabaseName("event_db")
                .withUsername("postgres")
                .withPassword("password")
                .withInitScript("init-test-schema.sql");
    }
}
