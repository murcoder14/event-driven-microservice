-- Set search path to tmschema
SET search_path TO tmschema;

ALTER TABLE direct_messages ADD COLUMN message_id VARCHAR(255) UNIQUE;
CREATE INDEX idx_direct_messages_message_id ON direct_messages(message_id);
