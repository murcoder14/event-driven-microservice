package org.muralis.service.listener;

import io.awspring.cloud.s3.S3Template;
import io.awspring.cloud.sqs.annotation.SqsListener;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.muralis.service.model.S3FileUpload;
import org.muralis.service.repository.S3FileUploadRepository;
import org.springframework.stereotype.Service;
import software.amazon.awssdk.services.s3.model.NoSuchBucketException;
import software.amazon.awssdk.services.s3.model.NoSuchKeyException;
import software.amazon.awssdk.services.s3.model.S3Exception;

import java.nio.charset.StandardCharsets;
import java.time.LocalDateTime;

@Slf4j
@Service
@RequiredArgsConstructor
public class S3EventListener {

    private final S3Template s3Template;
    private final S3FileUploadRepository repository;

    @SqsListener("${app.s3-event-queue}")
    public void onS3Event(io.awspring.cloud.s3.S3Event event) {
        log.info("Received S3 event: {}", event);

        try {
            for (io.awspring.cloud.s3.S3Event.S3EventNotificationRecord record : event.getRecords()) {
                String bucketName = record.getS3().getBucket().getName();
                String objectKey = record.getS3().getObject().getKey();

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
            }

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
