package org.muralis.service.model;

import lombok.Builder;
import lombok.Data;

import java.time.LocalDateTime;

@Data
@Builder
public class DlqFallback {
    private Long id;
    private String messageBody;
    private String errorReason;
    private String originalException;
    private Integer retryCount;
    private LocalDateTime createdAt;
    private LocalDateTime processedAt;
    private Boolean processed;
}
