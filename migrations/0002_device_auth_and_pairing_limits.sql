ALTER TABLE devices ADD COLUMN auth_token_hash TEXT;

CREATE UNIQUE INDEX devices_auth_token_hash
    ON devices(auth_token_hash)
    WHERE auth_token_hash IS NOT NULL;

CREATE TABLE pairing_attempts (
    client_key TEXT PRIMARY KEY NOT NULL,
    window_started_at INTEGER NOT NULL,
    attempts INTEGER NOT NULL CHECK (attempts > 0)
);
