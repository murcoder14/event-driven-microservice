package org.muralis.service.config;

import org.junit.jupiter.api.Test;
import org.muralis.service.testcontainers.PostgresContainerInitializer;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Primary;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.web.client.RestClient;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;
import software.amazon.awssdk.services.sqs.SqsClient;

import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.mockito.Mockito.mock;

@SpringBootTest(properties = "spring.cloud.aws.sqs.listener.auto-startup=false")
@ActiveProfiles("test")
@Testcontainers
class RestClientConfigTest {

    @TestConfiguration
    static class TestConfig {
        @Bean
        @Primary
        public SqsClient sqsClient() {
            // Mock for this simple test - integration tests use real LocalStack
            return mock(SqsClient.class);
        }
    }

    @Container
    static PostgreSQLContainer<?> postgres = PostgresContainerInitializer.createContainer();

    @DynamicPropertySource
    static void configureProperties(DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url", () -> postgres.getJdbcUrl() + "?currentSchema=tmschema");
        registry.add("spring.datasource.username", postgres::getUsername);
        registry.add("spring.datasource.password", postgres::getPassword);
        registry.add("spring.datasource.hikari.connection-init-sql", () -> "SET search_path TO tmschema");
        registry.add("spring.flyway.url", postgres::getJdbcUrl);
        registry.add("spring.flyway.user", postgres::getUsername);
        registry.add("spring.flyway.password", postgres::getPassword);
    }

    @Autowired
    private RestClient restClient;

    @Test
    void testRestClientBeanIsCreated() {
        assertNotNull(restClient,
                "RestClient bean should be created successfully");
    }
}
