CREATE TABLE profiles (
    profile_id TEXT PRIMARY KEY NOT NULL,
    grade INTEGER NOT NULL CHECK (grade IN (3, 4, 5)),
    created_at TEXT NOT NULL,
    last_activity_at TEXT NOT NULL
);

CREATE TABLE devices (
    device_id TEXT PRIMARY KEY NOT NULL,
    profile_id TEXT NOT NULL REFERENCES profiles(profile_id) ON DELETE CASCADE,
    created_at TEXT NOT NULL,
    last_seen_at TEXT NOT NULL
);

CREATE TABLE pairing_codes (
    pairing_id TEXT PRIMARY KEY NOT NULL,
    profile_id TEXT NOT NULL REFERENCES profiles(profile_id) ON DELETE CASCADE,
    code_hash TEXT NOT NULL UNIQUE,
    created_at TEXT NOT NULL,
    expires_at TEXT NOT NULL,
    consumed_at TEXT,
    attempts INTEGER NOT NULL DEFAULT 0 CHECK (attempts >= 0)
);

CREATE TABLE history_entries (
    entry_id TEXT PRIMARY KEY NOT NULL,
    profile_id TEXT NOT NULL REFERENCES profiles(profile_id) ON DELETE CASCADE,
    expression TEXT NOT NULL,
    result TEXT NOT NULL,
    recorded_at TEXT NOT NULL,
    topic_tag TEXT NOT NULL,
    expires_at TEXT NOT NULL
);

CREATE INDEX history_entries_profile_recorded
    ON history_entries(profile_id, recorded_at);
