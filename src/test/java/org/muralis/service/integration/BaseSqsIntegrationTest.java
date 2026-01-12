package org.muralis.service.integration;

import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.testcontainers.containers.localstack.LocalStackContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;
import org.testcontainers.utility.DockerImageName;
import software.amazon.awssdk.auth.credentials.AwsBasicCredentials;
import software.amazon.awssdk.auth.credentials.StaticCredentialsProvider;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.sqs.SqsAsyncClient;

import static org.testcontainers.containers.localstack.LocalStackContainer.Service.S3;
import static org.testcontainers.containers.localstack.LocalStackContainer.Service.SQS;

/**
 * Base class for SQS integration tests with LocalStack.
 * Provides shared TestContainers setup and configuration.
 */
@Testcontainers(disabledWithoutDocker = true)
abstract class BaseSqsIntegrationTest {

    @Container
    protected static LocalStackContainer localstack = new LocalStackContainer(
            DockerImageName.parse("localstack/localstack:4.0"))
            .withServices(SQS, S3);

    @DynamicPropertySource
    static void configureAwsProperties(DynamicPropertyRegistry registry) {
        // AWS properties
        registry.add("spring.cloud.aws.region.static",
                () -> localstack.getRegion());
        registry.add("spring.cloud.aws.credentials.access-key",
                () -> localstack.getAccessKey());
        registry.add("spring.cloud.aws.credentials.secret-key",
                () -> localstack.getSecretKey());
        registry.add("spring.cloud.aws.sqs.endpoint",
                () -> localstack.getEndpointOverride(SQS).toString());
        registry.add("spring.cloud.aws.s3.endpoint",
                () -> localstack.getEndpointOverride(S3).toString());
    }

    /**
     * Creates an async SQS client configured for LocalStack.
     * Use this in test configurations as a supplier.
     */
    protected static SqsAsyncClient createAsyncClient() {
        return SqsAsyncClient.builder()
                .endpointOverride(localstack.getEndpointOverride(SQS))
                .credentialsProvider(StaticCredentialsProvider.create(
                        AwsBasicCredentials.create(
                                localstack.getAccessKey(),
                                localstack.getSecretKey())))
                .region(Region.of(localstack.getRegion()))
                .build();
    }
}
