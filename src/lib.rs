use axum::{Json, Router, http::StatusCode, routing::get};
use serde::Serialize;
use sqlx::{SqlitePool, migrate::MigrateError};
use thiserror::Error;

pub mod config;
pub mod pairing;
#[cfg(any(test, feature = "sync-legal-approved"))]
mod sync_api;

#[derive(Debug, Error)]
pub enum ServiceError {
    #[error("database operation failed")]
    Database(#[from] sqlx::Error),
    #[error("database migration failed")]
    Migration(#[from] MigrateError),
}

#[derive(Serialize)]
struct Readiness {
    status: &'static str,
}

pub async fn connect_and_migrate(pool: &SqlitePool) -> Result<(), ServiceError> {
    sqlx::migrate!("./migrations").run(pool).await?;
    Ok(())
}

pub fn app(pool: SqlitePool) -> Router {
    let routes = Router::new().route("/health/ready", get(readiness));
    #[cfg(feature = "sync-legal-approved")]
    let routes = routes.merge(sync_api::routes());
    routes.with_state(pool)
}

pub fn app_with_pairing(pool: SqlitePool, config: pairing::PairingConfig) -> Router {
    app(pool.clone()).merge(pairing::router(pool, config))
}

async fn readiness(pool: axum::extract::State<SqlitePool>) -> Result<Json<Readiness>, StatusCode> {
    sqlx::query("SELECT 1")
        .execute(&*pool)
        .await
        .map_err(|_| StatusCode::SERVICE_UNAVAILABLE)?;

    Ok(Json(Readiness { status: "ready" }))
}

#[cfg(test)]
mod sync_api_contract_tests {
    use axum::{Router, body::Body, http::Request};
    use http_body_util::BodyExt;
    use sqlx::sqlite::SqlitePoolOptions;
    use tower::ServiceExt;

    use super::{connect_and_migrate, sync_api};

    async fn submit_sync(
        app: Router,
        profile_id: &str,
        token: &str,
        payload: serde_json::Value,
    ) -> axum::http::Response<Body> {
        app.oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/v1/profiles/{profile_id}/sync"))
                .header("authorization", format!("Bearer {token}"))
                .header("content-type", "application/json")
                .body(Body::from(payload.to_string()))
                .expect("valid request"),
        )
        .await
        .expect("sync endpoint responds")
    }

    #[tokio::test]
    async fn a_paired_device_can_only_access_its_own_profile_sync() {
        let pool = SqlitePoolOptions::new()
            .max_connections(1)
            .connect("sqlite::memory:")
            .await
            .expect("temporary SQLite database");
        connect_and_migrate(&pool).await.expect("migrations apply");
        sqlx::query(
            "INSERT INTO profiles (profile_id, grade, created_at, last_activity_at) VALUES \
             ('profile-a', 4, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'), \
             ('profile-b', 5, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')",
        )
        .execute(&pool)
        .await
        .expect("profiles are persisted");
        let token_hash = sync_api::hash_device_token("device-token");
        sqlx::query(
            "INSERT INTO devices \
             (device_id, profile_id, created_at, last_seen_at, auth_token_hash) \
             VALUES ('device-a', 'profile-a', '2026-01-01T00:00:00Z', \
             '2026-01-01T00:00:00Z', ?)",
        )
        .bind(token_hash)
        .execute(&pool)
        .await
        .expect("paired device is persisted");

        let app = sync_api::routes().with_state(pool);
        let own_profile = app
            .clone()
            .oneshot(
                Request::builder()
                    .uri("/v1/profiles/profile-a/sync")
                    .header("authorization", "Bearer device-token")
                    .body(Body::empty())
                    .expect("valid request"),
            )
            .await
            .expect("sync endpoint responds");
        let unpaired_device = app
            .clone()
            .oneshot(
                Request::builder()
                    .uri("/v1/profiles/profile-a/sync")
                    .body(Body::empty())
                    .expect("valid request"),
            )
            .await
            .expect("sync endpoint responds");
        let other_profile = app
            .oneshot(
                Request::builder()
                    .uri("/v1/profiles/profile-b/sync")
                    .header("authorization", "Bearer device-token")
                    .body(Body::empty())
                    .expect("valid request"),
            )
            .await
            .expect("sync endpoint responds");

        assert_eq!(own_profile.status(), axum::http::StatusCode::OK);
        assert_eq!(
            unpaired_device.status(),
            axum::http::StatusCode::UNAUTHORIZED
        );
        assert_eq!(other_profile.status(), axum::http::StatusCode::FORBIDDEN);
    }

    #[tokio::test]
    async fn sync_api_is_not_mounted_on_the_production_application() {
        let pool = SqlitePoolOptions::new()
            .max_connections(1)
            .connect("sqlite::memory:")
            .await
            .expect("temporary SQLite database");
        connect_and_migrate(&pool).await.expect("migrations apply");

        let response = super::app(pool)
            .oneshot(
                Request::builder()
                    .uri("/v1/profiles/profile-a/sync")
                    .body(Body::empty())
                    .expect("valid request"),
            )
            .await
            .expect("application responds");

        assert_eq!(response.status(), axum::http::StatusCode::NOT_FOUND);
    }

    #[tokio::test]
    async fn sync_rejects_fields_outside_the_profile_and_history_allowlist() {
        let pool = SqlitePoolOptions::new()
            .max_connections(1)
            .connect("sqlite::memory:")
            .await
            .expect("temporary SQLite database");
        connect_and_migrate(&pool).await.expect("migrations apply");
        sqlx::query(
            "INSERT INTO profiles (profile_id, grade, created_at, last_activity_at) \
             VALUES ('profile-a', 4, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')",
        )
        .execute(&pool)
        .await
        .expect("profile is persisted");
        sqlx::query(
            "INSERT INTO devices \
             (device_id, profile_id, created_at, last_seen_at, auth_token_hash) \
             VALUES ('device-a', 'profile-a', '2026-01-01T00:00:00Z', \
             '2026-01-01T00:00:00Z', ?)",
        )
        .bind(sync_api::hash_device_token("device-a-token"))
        .execute(&pool)
        .await
        .expect("paired device is persisted");
        let recorded_at: String =
            sqlx::query_scalar("SELECT strftime('%Y-%m-%dT%H:%M:%fZ', 'now')")
                .fetch_one(&pool)
                .await
                .expect("current timestamp is available");

        let app = sync_api::routes().with_state(pool);
        let response = app
            .clone()
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/v1/profiles/profile-a/sync")
                    .header("content-type", "application/json")
                    .body(Body::from(
                        r#"{"grade":4,"history":[],"email":"learner@example.test"}"#,
                    ))
                    .expect("valid request"),
            )
            .await
            .expect("sync endpoint responds");

        assert_eq!(
            response.status(),
            axum::http::StatusCode::UNPROCESSABLE_ENTITY
        );

        let freeform_expression = submit_sync(
            app.clone(),
            "profile-a",
            "device-a-token",
            serde_json::json!({
                "history": [{
                    "entry_id": "entry-a",
                    "expression": "learner name + 1",
                    "result": "2",
                    "recorded_at": recorded_at.clone(),
                    "topic_tag": "addition"
                }]
            }),
        )
        .await;
        let freeform_topic = submit_sync(
            app,
            "profile-a",
            "device-a-token",
            serde_json::json!({
                "history": [{
                    "entry_id": "entry-b",
                    "expression": "1 + 1",
                    "result": "2",
                    "recorded_at": recorded_at,
                    "topic_tag": "learner@example.test"
                }]
            }),
        )
        .await;
        assert_eq!(
            freeform_expression.status(),
            axum::http::StatusCode::UNPROCESSABLE_ENTITY
        );
        assert_eq!(
            freeform_topic.status(),
            axum::http::StatusCode::UNPROCESSABLE_ENTITY
        );
    }

    #[tokio::test]
    async fn concurrent_history_syncs_merge_and_retries_do_not_replace_entries() {
        let pool = SqlitePoolOptions::new()
            .max_connections(1)
            .connect("sqlite::memory:")
            .await
            .expect("temporary SQLite database");
        connect_and_migrate(&pool).await.expect("migrations apply");
        sqlx::query(
            "INSERT INTO profiles (profile_id, grade, created_at, last_activity_at) \
             VALUES ('profile-a', 3, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')",
        )
        .execute(&pool)
        .await
        .expect("profile is persisted");
        let token_a = sync_api::hash_device_token("device-a-token");
        let token_b = sync_api::hash_device_token("device-b-token");
        sqlx::query(
            "INSERT INTO devices \
             (device_id, profile_id, created_at, last_seen_at, auth_token_hash) VALUES \
             ('device-a', 'profile-a', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z', ?), \
             ('device-b', 'profile-a', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z', ?)",
        )
        .bind(token_a)
        .bind(token_b)
        .execute(&pool)
        .await
        .expect("paired devices are persisted");
        let recorded_at: String =
            sqlx::query_scalar("SELECT strftime('%Y-%m-%dT%H:%M:%fZ', 'now')")
                .fetch_one(&pool)
                .await
                .expect("current timestamp is available");

        let app = sync_api::routes().with_state(pool);
        let (first, second) = tokio::join!(
            submit_sync(
                app.clone(),
                "profile-a",
                "device-a-token",
                serde_json::json!({
                    "grade": 4,
                    "history": [{
                        "entry_id": "entry-a",
                        "expression": "2 × 3",
                        "result": "6",
                        "recorded_at": recorded_at.clone(),
                        "topic_tag": "multiplication"
                    }]
                })
            ),
            submit_sync(
                app.clone(),
                "profile-a",
                "device-b-token",
                serde_json::json!({
                    "history": [{
                        "entry_id": "entry-b",
                        "expression": "7 − 4",
                        "result": "3",
                        "recorded_at": recorded_at.clone(),
                        "topic_tag": "subtraction"
                    }]
                })
            )
        );
        assert_eq!(first.status(), axum::http::StatusCode::OK);
        assert_eq!(second.status(), axum::http::StatusCode::OK);

        let retry = submit_sync(
            app.clone(),
            "profile-a",
            "device-b-token",
            serde_json::json!({
                "history": [{
                    "entry_id": "entry-b",
                    "expression": "9 - 4",
                    "result": "5",
                    "recorded_at": recorded_at,
                    "topic_tag": "subtraction"
                }]
            }),
        )
        .await;
        assert_eq!(retry.status(), axum::http::StatusCode::OK);

        let snapshot = app
            .oneshot(
                Request::builder()
                    .uri("/v1/profiles/profile-a/sync")
                    .header("authorization", "Bearer device-a-token")
                    .body(Body::empty())
                    .expect("valid request"),
            )
            .await
            .expect("sync endpoint responds");
        assert_eq!(snapshot.status(), axum::http::StatusCode::OK);
        let snapshot: serde_json::Value = serde_json::from_slice(
            &snapshot
                .into_body()
                .collect()
                .await
                .expect("snapshot body")
                .to_bytes(),
        )
        .expect("snapshot is JSON");
        assert_eq!(snapshot["grade"], 4);
        assert_eq!(snapshot.as_object().expect("snapshot object").len(), 3);
        assert_eq!(
            snapshot["history"].as_array().expect("history list").len(),
            2
        );
        assert_eq!(
            snapshot["history"][1]
                .as_object()
                .expect("entry object")
                .len(),
            5
        );
        assert_eq!(snapshot["history"][1]["entry_id"], "entry-b");
        assert_eq!(snapshot["history"][1]["expression"], "7 − 4");
    }
}
