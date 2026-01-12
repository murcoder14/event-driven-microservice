package org.muralis.service.listener;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import io.awspring.cloud.sqs.annotation.SqsListener;
import io.awspring.cloud.sqs.listener.acknowledgement.Acknowledgement;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.muralis.service.exception.DatabaseException;
import org.muralis.service.exception.IrrecoverableApiException;
import org.muralis.service.exception.RecoverableApiException;
import org.muralis.service.service.DirectMessageService;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.messaging.handler.annotation.Header;
import org.springframework.stereotype.Service;
import software.amazon.awssdk.services.sqs.SqsAsyncClient;
import software.amazon.awssdk.services.sqs.model.SendMessageRequest;

@Slf4j
@Service
@RequiredArgsConstructor
public class DirectMessageListener {

    private final DirectMessageService messageService;
    private final ObjectMapper objectMapper;
    private final SqsAsyncClient sqsAsyncClient;
    
    @Value("${app.direct-message-dlq}")
    private String dlqUrl;
    
    @Value("${app.max-retry-count:3}")
    private int maxRetryCount;

    @SqsListener(value = "${app.direct-message-queue}", acknowledgementMode = "MANUAL")
    public void onMessage(String messageBody, 
                         Acknowledgement acknowledgement,
                         @Header("Sqs_Msa_ApproximateReceiveCount") String receiveCount) {
        log.info("Received SQS message (receiveCount={}): {}", receiveCount, messageBody);

        try {
            JsonNode json = objectMapper.readTree(messageBody);
            String city = json.get("city").asText();
            String country = json.get("country").asText();
            String messageId = json.get("messageId").asText();
            
            log.info("Parsed attributes - city: {}, country: {}, messageId: {}", city, country, messageId);
            
            // Process message (includes weather API call and DB save)
            messageService.processMessage(city, country, messageId);
            
            // Success - acknowledge the message
            acknowledgement.acknowledge();
            log.info("Message processed successfully and acknowledged");
            
        } catch (IrrecoverableApiException e) {
            // Irrecoverable error - send directly to DLQ
            log.error("Irrecoverable error processing message, sending to DLQ: {}", e.getMessage());
            sendToDLQ(messageBody, e.getMessage());
            acknowledgement.acknowledge(); // Acknowledge to prevent reprocessing
            
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
    
    private void sendToDLQ(String messageBody, String errorReason) {
        try {
            sqsAsyncClient.sendMessage(SendMessageRequest.builder()
                    .queueUrl(dlqUrl)
                    .messageBody(messageBody)
                    .messageGroupId("irrecoverable-errors")
                    .messageDeduplicationId(String.valueOf(System.currentTimeMillis()))
                    .build()).join();
            log.info("Message sent to DLQ: {}", dlqUrl);
        } catch (Exception e) {
            log.error("Failed to send message to DLQ", e);
        }
    }
}
