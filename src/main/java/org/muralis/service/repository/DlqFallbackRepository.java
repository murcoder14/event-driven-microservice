package org.muralis.service.repository;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.muralis.service.model.DlqFallback;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

import java.time.LocalDateTime;

@Slf4j
@Repository
@RequiredArgsConstructor
public class DlqFallbackRepository {

    private final JdbcTemplate jdbcTemplate;

    public void save(DlqFallback fallback) {
        String sql = "INSERT INTO dlq_fallback (message_body, error_reason, original_exception, "
                + "retry_count, created_at) VALUES (?, ?, ?, ?, ?)";
        
        jdbcTemplate.update(sql, 
                fallback.getMessageBody(),
                fallback.getErrorReason(),
                fallback.getOriginalException(),
                fallback.getRetryCount(),
                LocalDateTime.now());
        
        log.info("Saved message to DLQ fallback table: {}", fallback.getMessageBody());
    }
}
