ALTER TABLE devices
    ADD COLUMN auth_token_hash TEXT;

CREATE UNIQUE INDEX devices_auth_token_hash
    ON devices(auth_token_hash);
