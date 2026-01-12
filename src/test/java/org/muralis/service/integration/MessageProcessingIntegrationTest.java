package org.muralis.service.integration;

import com.fasterxml.jackson.databind.ObjectMapper;
import io.awspring.cloud.sqs.config.SqsBootstrapConfiguration;
import io.awspring.cloud.sqs.config.SqsMessageListenerContainerFactory;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.muralis.service.repository.DirectMessageRepository;
import org.muralis.service.testcontainers.PostgresContainerInitializer;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Import;
import org.springframework.context.annotation.Primary;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;
import software.amazon.awssdk.auth.credentials.AwsBasicCredentials;
import software.amazon.awssdk.auth.credentials.StaticCredentialsProvider;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.PutObjectRequest;
import software.amazon.awssdk.services.sqs.SqsAsyncClient;
import software.amazon.awssdk.services.sqs.model.CreateQueueRequest;
import software.amazon.awssdk.services.sqs.model.GetQueueAttributesRequest;
import software.amazon.awssdk.services.sqs.model.QueueAttributeName;
import software.amazon.awssdk.services.sqs.model.SendMessageRequest;

import java.time.Duration;
import java.util.Collections;
import java.util.HashMap;
import java.util.Map;
import java.util.UUID;

import static java.util.concurrent.TimeUnit.SECONDS;
import static org.awaitility.Awaitility.await;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.testcontainers.containers.localstack.LocalStackContainer.Service.S3;

@SpringBootTest(
        webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
        properties = "spring.profiles.active=test"
)
@Testcontainers(disabledWithoutDocker = true)
class MessageProcessingIntegrationTest extends BaseSqsIntegrationTest {

    @Import(SqsBootstrapConfiguration.class)
    @TestConfiguration
    static class TestConfig {
        @Bean
        @Primary
        public SqsAsyncClient testSqsAsyncClient() {
            return BaseSqsIntegrationTest.createAsyncClient();
        }

        @Bean
        @Primary
        public S3Client testS3Client() {
            return S3Client.builder()
                    .endpointOverride(localstack.getEndpointOverride(S3))
                    .credentialsProvider(StaticCredentialsProvider.create(
                            AwsBasicCredentials.create(
                                    localstack.getAccessKey(),
                                    localstack.getSecretKey())))
                    .region(Region.of(localstack.getRegion()))
                    .build();
        }

        @Bean
        public SqsMessageListenerContainerFactory<Object> defaultSqsListenerContainerFactory() {
            return SqsMessageListenerContainerFactory.builder()
                    .sqsAsyncClientSupplier(BaseSqsIntegrationTest::createAsyncClient)
                    .configure(options -> options
                            .maxDelayBetweenPolls(Duration.ofSeconds(5))
                            .queueAttributeNames(Collections.singletonList(QueueAttributeName.QUEUE_ARN))
                            .pollTimeout(Duration.ofSeconds(5)))
                    .build();
        }
    }

    @Container
    static PostgreSQLContainer<?> postgres = PostgresContainerInitializer.createContainer();

    @Autowired
    private DirectMessageRepository directMessageRepository;

    @Autowired
    private JdbcTemplate jdbcTemplate;

    @Autowired
    private SqsAsyncClient sqsAsyncClient;

    @Autowired
    private S3Client s3Client;

    private static String directMessageQueueUrl;
    private static String s3EventQueueUrl;
    private static String bucketName;

    @DynamicPropertySource
    static void configureProperties(DynamicPropertyRegistry registry) {
        // Initialize AWS clients and create queues/buckets BEFORE Spring starts
        SqsAsyncClient sqsAsyncClient = createAsyncClient();

        S3Client s3Client = S3Client.builder()
                .endpointOverride(localstack.getEndpointOverride(S3))
                .credentialsProvider(StaticCredentialsProvider.create(
                        AwsBasicCredentials.create(
                                localstack.getAccessKey(),
                                localstack.getSecretKey())))
                .region(Region.of(localstack.getRegion()))
                .build();

        // Create queues
        try {
            directMessageQueueUrl = sqsAsyncClient.createQueue(
                    CreateQueueRequest.builder()
                            .queueName("direct-message-queue")
                            .build()
            ).get().queueUrl();

            s3EventQueueUrl = sqsAsyncClient.createQueue(
                    CreateQueueRequest.builder()
                            .queueName("s3-event-queue")
                            .build()
            ).get().queueUrl();

            sqsAsyncClient.createQueue(
                    CreateQueueRequest.builder()
                            .queueName("direct-message-queue-dlq")
                            .build()
            ).get();
        } catch (Exception e) {
            throw new RuntimeException("Failed to create queues", e);
        }

        // Create S3 bucket
        bucketName = "test-bucket";
        s3Client.createBucket(b -> b.bucket(bucketName));

        // Database properties
        registry.add("spring.datasource.url", () -> postgres.getJdbcUrl() + "?currentSchema=tmschema");
        registry.add("spring.datasource.username", postgres::getUsername);
        registry.add("spring.datasource.password", postgres::getPassword);
        // Set search_path on each connection for consistent schema resolution
        registry.add("spring.datasource.hikari.connection-init-sql", () -> "SET search_path TO tmschema");
        registry.add("spring.flyway.url", postgres::getJdbcUrl);
        registry.add("spring.flyway.user", postgres::getUsername);
        registry.add("spring.flyway.password", postgres::getPassword);

        // Queue names
        registry.add("app.direct-message-queue", () -> "direct-message-queue");
        registry.add("app.s3-event-queue", () -> "s3-event-queue");
        registry.add("app.direct-message-dlq",
                () -> "direct-message-queue-dlq");
    }

    @BeforeEach
    void setUp() {
        // Clean database before each test
        // Use schema-qualified table names to ensure correct schema is used
        jdbcTemplate.execute("DELETE FROM tmschema.s3_file_uploads");
        jdbcTemplate.execute("DELETE FROM tmschema.direct_messages");
    }

    @Test
    void testDirectMessageProcessing() throws Exception {
        // Given: A message with city and country
        String messageId = UUID.randomUUID().toString();
        Map<String, Object> message = new HashMap<>();
        message.put("city", "London");
        message.put("country", "UK");
        message.put("messageId", messageId);

        ObjectMapper mapper = new ObjectMapper();
        String messageBody = mapper.writeValueAsString(message);

        // When: Message is sent to SQS
        sqsAsyncClient.sendMessage(SendMessageRequest.builder()
                .queueUrl(directMessageQueueUrl)
                .messageBody(messageBody)
                .build()).join();

        // Then: Message should be processed and saved to database
        await().atMost(15, SECONDS)
                .pollInterval(2, SECONDS)
                .untilAsserted(() -> {
                    boolean exists = directMessageRepository
                            .existsByMessageId(messageId);
                    assertTrue(exists,
                            "Message should be saved to database");
                });

        // Verify queue is empty (message was acknowledged)
        await().atMost(10, SECONDS)
                .untilAsserted(() -> {
                    var response = sqsAsyncClient.getQueueAttributes(
                            GetQueueAttributesRequest.builder()
                                    .queueUrl(directMessageQueueUrl)
                                    .attributeNames(QueueAttributeName
                                            .APPROXIMATE_NUMBER_OF_MESSAGES)
                                    .build()).join();
                    int messageCount = Integer.parseInt(
                            response.attributes()
                                    .get(QueueAttributeName
                                            .APPROXIMATE_NUMBER_OF_MESSAGES));
                    assertEquals(0, messageCount,
                            "Queue should be empty after processing");
                });
    }

    @Test
    void testIdempotencyCheck() throws Exception {
        // Given: A message that will be sent twice
        String messageId = UUID.randomUUID().toString();
        Map<String, Object> message = new HashMap<>();
        message.put("city", "Paris");
        message.put("country", "France");
        message.put("messageId", messageId);

        ObjectMapper mapper = new ObjectMapper();
        String messageBody = mapper.writeValueAsString(message);

        // When: Same message is sent twice
        sqsAsyncClient.sendMessage(SendMessageRequest.builder()
                .queueUrl(directMessageQueueUrl)
                .messageBody(messageBody)
                .build()).join();

        sqsAsyncClient.sendMessage(SendMessageRequest.builder()
                .queueUrl(directMessageQueueUrl)
                .messageBody(messageBody)
                .build()).join();

        // Then: Only one record should exist in database
        await().atMost(15, SECONDS)
                .pollInterval(2, SECONDS)
                .untilAsserted(() -> {
                    Integer count = jdbcTemplate.queryForObject(
                            "SELECT COUNT(*) FROM tmschema.direct_messages "
                                    + "WHERE message_id = ?",
                            Integer.class, messageId);
                    assertEquals(1, count,
                            "Only one record should exist (idempotency)");
                });
    }

    @Test
    void testS3EventProcessing() throws Exception {
        // Given: A file uploaded to S3
        String objectKey = "test-file-" + UUID.randomUUID() + ".txt";
        String fileContent = "Test file content for integration test";

        s3Client.putObject(
                PutObjectRequest.builder()
                        .bucket(bucketName)
                        .key(objectKey)
                        .build(),
                software.amazon.awssdk.core.sync.RequestBody
                        .fromString(fileContent));

        // When: S3 event notification is sent to SQS
        Map<String, Object> s3Event = createS3Event(bucketName, objectKey);
        ObjectMapper mapper = new ObjectMapper();
        String eventBody = mapper.writeValueAsString(s3Event);

        sqsAsyncClient.sendMessage(SendMessageRequest.builder()
                .queueUrl(s3EventQueueUrl)
                .messageBody(eventBody)
                .build()).join();

        // Then: File should be processed and saved to database
        await().atMost(15, SECONDS)
                .pollInterval(2, SECONDS)
                .untilAsserted(() -> {
                    Integer count = jdbcTemplate.queryForObject(
                            "SELECT COUNT(*) FROM tmschema.s3_file_uploads "
                                    + "WHERE object_key = ?",
                            Integer.class, objectKey);
                    assertTrue(count > 0,
                            "S3 file should be saved to database");
                });

        // Verify content was stored
        String storedContent = jdbcTemplate.queryForObject(
                "SELECT content FROM tmschema.s3_file_uploads "
                        + "WHERE object_key = ?",
                String.class, objectKey);
        assertEquals(fileContent, storedContent,
                "File content should match");
    }

    private Map<String, Object> createS3Event(String bucket, String key) {
        Map<String, Object> event = new HashMap<>();
        Map<String, Object> record = new HashMap<>();
        Map<String, Object> s3 = new HashMap<>();
        Map<String, Object> bucketInfo = new HashMap<>();
        Map<String, Object> objectInfo = new HashMap<>();

        bucketInfo.put("name", bucket);
        objectInfo.put("key", key);

        s3.put("bucket", bucketInfo);
        s3.put("object", objectInfo);
        record.put("s3", s3);

        event.put("Records", java.util.List.of(record));
        return event;
    }
}
