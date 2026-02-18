package org.muralis.service.listener;

import io.awspring.cloud.sqs.annotation.SqsListener;
import io.awspring.cloud.sqs.listener.acknowledgement.Acknowledgement;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.muralis.service.exception.DatabaseException;
import org.muralis.service.exception.IrrecoverableApiException;
import org.muralis.service.exception.RecoverableApiException;
import org.muralis.service.model.DirectMessagePayload;
import org.muralis.service.model.DlqFallback;
import org.muralis.service.repository.DlqFallbackRepository;
import org.muralis.service.service.DirectMessageService;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.messaging.handler.annotation.Header;
import org.springframework.messaging.handler.annotation.Payload;
import org.springframework.retry.annotation.Backoff;
import org.springframework.retry.annotation.Recover;
import org.springframework.retry.annotation.Retryable;
import org.springframework.stereotype.Service;
import software.amazon.awssdk.core.exception.SdkClientException;
import software.amazon.awssdk.services.sqs.SqsAsyncClient;
import software.amazon.awssdk.services.sqs.model.SendMessageRequest;
import software.amazon.awssdk.services.sqs.model.SqsException;

@Slf4j
@Service
@RequiredArgsConstructor
public class DirectMessageListener {

    private final DirectMessageService messageService;
    private final SqsAsyncClient sqsAsyncClient;
    private final DlqFallbackRepository dlqFallbackRepository;
    
    @Value("${app.direct-message-dlq}")
    private String dlqUrl;
    
    @Value("${app.max-retry-count:3}")
    private int maxRetryCount;

    @SqsListener(value = "${app.direct-message-queue}", acknowledgementMode = "MANUAL")
    public void onMessage(@Payload DirectMessagePayload payload, 
                         Acknowledgement acknowledgement,
                         @Header("Sqs_Msa_ApproximateReceiveCount") String receiveCount) {
        log.info("Received SQS message (receiveCount={}): {}", receiveCount, payload);

        try {
            String city = payload.city();
            String country = payload.country();
            String messageId = payload.messageId();
            
            log.info("Parsed attributes - city: {}, country: {}, messageId: {}", city, country, messageId);
            
            // Process message (includes weather API call and DB save)
            messageService.processMessage(city, country, messageId);
            
            // Success - acknowledge the message
            acknowledgement.acknowledge();
            log.info("Message processed successfully and acknowledged");
            
        } catch (IrrecoverableApiException e) {
            // Irrecoverable error - send directly to DLQ
            log.error("Irrecoverable error processing message, sending to DLQ: {}", e.getMessage());
            boolean dlqSuccess = sendToDLQ(payload.toString(), e.getMessage(), e);
            
            if (dlqSuccess) {
                acknowledgement.acknowledge(); // Acknowledge to prevent reprocessing
            } else {
                // DLQ send failed even after retries - don't acknowledge
                // Message will return to main queue for retry
                log.error("Failed to send to DLQ after retries, message will be retried by SQS");
            }
            
        } catch (RecoverableApiException e) {
            // Recoverable API error - don't acknowledge, let SQS retry
            log.warn("Recoverable API error processing message (receiveCount={}): {}", receiveCount, e.getMessage());
            // Do NOT acknowledge - message will be retried by SQS
            // After maxReceiveCount (3), SQS will automatically move to DLQ
            
        } catch (DatabaseException e) {
            // Database error - don't acknowledge, let SQS retry
            // On retry, idempotency check will pass, weather API won't be called again
            log.error("Database error processing message (receiveCount={}): {}", receiveCount, e.getMessage());
            // Do NOT acknowledge - message will be retried by SQS
            // After maxReceiveCount (3), SQS will automatically move to DLQ
            
        } catch (Exception e) {
            // Unexpected error - treat as recoverable
            log.error("Unexpected error processing message (receiveCount={})", receiveCount, e);
            // Do NOT acknowledge - message will be retried by SQS
        }
    }
    
    /**
     * Attempts to send a message to the DLQ with automatic retry on transient failures.
     * Uses Spring Retry with exponential backoff (1s, 2s, 4s).
     * 
     * @param messageBody The message content to send
     * @param errorReason The reason for sending to DLQ
     * @param originalException The original exception that caused the failure
     * @return true if message was successfully sent to DLQ, false otherwise
     */
    @Retryable(
        retryFor = {SqsException.class, SdkClientException.class},
        maxAttempts = 3,
        backoff = @Backoff(delay = 1000, multiplier = 2)
    )
    private boolean sendToDLQ(String messageBody, String errorReason, Exception originalException) {
        try {
            sqsAsyncClient.sendMessage(SendMessageRequest.builder()
                    .queueUrl(dlqUrl)
                    .messageBody(messageBody)
                    .messageGroupId("irrecoverable-errors")
                    .messageDeduplicationId(String.valueOf(System.currentTimeMillis()))
                    .build()).join();
            log.info("Message sent to DLQ: {}", dlqUrl);
            return true;
        } catch (SqsException | SdkClientException e) {
            log.error("Failed to send message to DLQ (will retry): {}", e.getMessage());
            throw e; // Re-throw to trigger Spring Retry
        } catch (Exception e) {
            log.error("Unexpected error sending to DLQ", e);
            return false;
        }
    }
    
    /**
     * Recovery method called after all retry attempts are exhausted.
     * Saves the message to a database fallback table for manual recovery.
     * 
     * @param e The exception that caused all retries to fail
     * @param messageBody The message content
     * @param errorReason The reason for sending to DLQ
     * @param originalException The original exception that caused the failure
     * @return false to indicate DLQ send ultimately failed
     */
    @Recover
    private boolean recoverFromDLQFailure(Exception e, String messageBody, 
                                         String errorReason, Exception originalException) {
        log.error("All DLQ send attempts failed, saving to fallback table: {}", e.getMessage());
        
        try {
            DlqFallback fallback = DlqFallback.builder()
                    .messageBody(messageBody)
                    .errorReason(errorReason)
                    .originalException(originalException != null ? 
                            originalException.getClass().getName() + ": " + originalException.getMessage() : null)
                    .retryCount(0)
                    .build();
            
            dlqFallbackRepository.save(fallback);
            log.info("Message saved to DLQ fallback table successfully");
        } catch (Exception dbException) {
            log.error("CRITICAL: Failed to save to DLQ fallback table. Message may be lost!", dbException);
        }
        
        return false; // Indicate DLQ send failed
    }
}
