-- Set search path to tmschema
SET search_path TO tmschema;

CREATE TABLE IF NOT EXISTS dlq_fallback (
    id SERIAL PRIMARY KEY,
    message_body TEXT NOT NULL,
    error_reason TEXT NOT NULL,
    original_exception TEXT,
    retry_count INTEGER DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    processed_at TIMESTAMP,
    processed BOOLEAN DEFAULT FALSE
);

-- Index for querying unprocessed messages
CREATE INDEX idx_dlq_fallback_processed ON dlq_fallback(processed, created_at);
