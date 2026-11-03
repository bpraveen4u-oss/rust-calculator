CREATE INDEX history_entries_expiry
    ON history_entries(julianday(expires_at));

CREATE INDEX profiles_activity_expiry
    ON profiles(julianday(last_activity_at));
