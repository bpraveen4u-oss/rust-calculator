use std::time::Duration;

use sqlx::SqlitePool;

pub async fn expire_cloud_data(pool: &SqlitePool) -> Result<(), sqlx::Error> {
    let mut transaction = pool.begin().await?;
    sqlx::query("DELETE FROM history_entries WHERE julianday(expires_at) <= julianday('now')")
        .execute(&mut *transaction)
        .await?;
    sqlx::query(
        "DELETE FROM profiles \
         WHERE julianday(last_activity_at) <= julianday('now', '-90 days') \
           AND NOT EXISTS ( \
             SELECT 1 FROM history_entries WHERE history_entries.profile_id = profiles.profile_id \
           )",
    )
    .execute(&mut *transaction)
    .await?;
    transaction.commit().await
}

pub fn spawn_retention_worker(pool: SqlitePool) {
    tokio::spawn(async move {
        let mut interval = tokio::time::interval(Duration::from_secs(60));
        loop {
            interval.tick().await;
            if let Err(error) = expire_cloud_data(&pool).await {
                tracing::error!(%error, "cloud retention cleanup failed");
            }
        }
    });
}
