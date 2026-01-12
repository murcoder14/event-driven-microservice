-- Set search path to tmschema
SET search_path TO tmschema;

CREATE TABLE IF NOT EXISTS direct_messages (
    id SERIAL PRIMARY KEY,
    city VARCHAR(255) NOT NULL,
    country VARCHAR(255) NOT NULL,
    received_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS s3_file_uploads (
    id SERIAL PRIMARY KEY,
    bucket_name VARCHAR(255) NOT NULL,
    object_key VARCHAR(512) NOT NULL,
    content TEXT,
    processed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
