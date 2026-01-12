package org.muralis.service.listener;

import org.muralis.service.model.S3FileUpload;
import org.muralis.service.repository.S3FileUploadRepository;
import io.awspring.cloud.s3.S3Template;
import io.awspring.cloud.sqs.annotation.SqsListener;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

import java.nio.charset.StandardCharsets;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;
import software.amazon.awssdk.services.s3.model.S3Exception;
import software.amazon.awssdk.services.s3.model.NoSuchBucketException;
import software.amazon.awssdk.services.s3.model.NoSuchKeyException;

@Slf4j
@Service
@RequiredArgsConstructor
public class S3EventListener {

    private final S3Template s3Template;
    private final S3FileUploadRepository repository;

    @SqsListener("${app.s3-event-queue}")
    @SuppressWarnings("unchecked")
    public void onS3Event(Map<String, Object> event) {
        log.info("Received S3 event: {}", event);

        // Simple extraction logic - S3 events delivered to SQS have a specific JSON
        // structure
        // This is a simplified version assuming the SQS message is the S3 event record
        try {
            // Parse the standard AWS S3 Event Notification structure:
            // Records[] -> s3 -> bucket -> name
            // Records[] -> s3 -> object -> key
            List<Map<String, Object>> records = (List<Map<String, Object>>) event.get("Records");
            if (records == null || records.isEmpty()) {
                log.warn("Received SQS message that is not an S3 Event Notification: {}", event);
                return;
            }

            Map<String, Object> s3 = (Map<String, Object>) records.getFirst().get("s3");
            Map<String, Object> bucket = (Map<String, Object>) s3.get("bucket");
            Map<String, Object> object = (Map<String, Object>) s3.get("object");

            String bucketName = (String) bucket.get("name");
            String objectKey = (String) object.get("key");

            log.info("Processing S3 Event for Bucket: {}, Key: {}", bucketName, objectKey);

            String content = s3Template.download(bucketName, objectKey).getContentAsString(StandardCharsets.UTF_8);

            S3FileUpload upload = S3FileUpload.builder()
                    .bucketName(bucketName)
                    .objectKey(objectKey)
                    .content(content)
                    .processedAt(LocalDateTime.now())
                    .build();

            repository.save(upload);
            log.info("Successfully processed S3 file: {}/{}", bucketName, objectKey);

        } catch (NoSuchBucketException | NoSuchKeyException e) {
            log.warn("Skipping stale S3 event: The bucket or file no longer exists. "
                    + "This is expected if you recently recreated your infrastructure.");
        } catch (S3Exception e) {
            log.error("AWS S3 Service error: {}", e.getMessage());
        } catch (Exception e) {
            log.error("Unexpected error processing S3 event", e);
        }
    }
}
