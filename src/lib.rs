use axum::{Json, Router, http::StatusCode, routing::get};
use serde::Serialize;
use sqlx::{SqlitePool, migrate::MigrateError};
use thiserror::Error;

pub mod config;
pub mod pairing;
pub mod retention;
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

pub use retention::spawn_retention_worker;

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

    use super::{connect_and_migrate, pairing, sync_api};

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

    async fn create_paired_profile(pool: &sqlx::SqlitePool, token: &str, inactive: bool) {
        sqlx::query(
            "INSERT INTO profiles (profile_id, grade, created_at, last_activity_at) \
             VALUES ('profile-a', 4, strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), \
             CASE WHEN ? THEN \
             strftime('%Y-%m-%dT%H:%M:%fZ', 'now', '-90 days', '-1 second') \
             ELSE strftime('%Y-%m-%dT%H:%M:%fZ', 'now', '-1 day') END)",
        )
        .bind(inactive)
        .execute(pool)
        .await
        .expect("profile is persisted");
        sqlx::query(
            "INSERT INTO devices \
             (device_id, profile_id, created_at, last_seen_at, auth_token_hash) \
             VALUES ('device-a', 'profile-a', strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), \
             strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), ?)",
        )
        .bind(sync_api::hash_device_token(token))
        .execute(pool)
        .await
        .expect("paired device is persisted");
    }

    async fn request_history_erase(
        app: Router,
        profile_id: &str,
        device_token: Option<&str>,
        guardian_token: Option<&str>,
    ) -> axum::http::Response<Body> {
        let mut request = Request::builder()
            .method("DELETE")
            .uri(format!("/v1/profiles/{profile_id}/history"));
        if let Some(token) = device_token {
            request = request.header("authorization", format!("Bearer {token}"));
        }
        if let Some(token) = guardian_token {
            request = request.header("x-guardian-authorization", format!("Bearer {token}"));
        }
        app.oneshot(
            request
                .body(Body::empty())
                .expect("valid history erase request"),
        )
        .await
        .expect("history erase endpoint responds")
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
             ('profile-a', 4, strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), \
             strftime('%Y-%m-%dT%H:%M:%fZ', 'now')), \
             ('profile-b', 5, strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), \
             strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))",
        )
        .execute(&pool)
        .await
        .expect("profiles are persisted");
        let token_hash = sync_api::hash_device_token("device-token");
        sqlx::query(
            "INSERT INTO devices \
             (device_id, profile_id, created_at, last_seen_at, auth_token_hash) \
             VALUES ('device-a', 'profile-a', strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), \
             strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), ?)",
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
    #[cfg(not(feature = "sync-legal-approved"))]
    async fn sync_api_is_not_mounted_on_the_production_application() {
        let pool = SqlitePoolOptions::new()
            .max_connections(1)
            .connect("sqlite::memory:")
            .await
            .expect("temporary SQLite database");
        connect_and_migrate(&pool).await.expect("migrations apply");

        let app = super::app(pool);
        let response = app
            .clone()
            .oneshot(
                Request::builder()
                    .uri("/v1/profiles/profile-a/sync")
                    .body(Body::empty())
                    .expect("valid request"),
            )
            .await
            .expect("application responds");

        assert_eq!(response.status(), axum::http::StatusCode::NOT_FOUND);

        let erasure = app
            .oneshot(
                Request::builder()
                    .method("DELETE")
                    .uri("/v1/profiles/profile-a/history")
                    .body(Body::empty())
                    .expect("valid request"),
            )
            .await
            .expect("application responds");
        assert_eq!(erasure.status(), axum::http::StatusCode::NOT_FOUND);
    }

    #[tokio::test]
    #[cfg(feature = "sync-legal-approved")]
    async fn sync_api_is_mounted_only_with_the_legal_approval_feature() {
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

        assert_eq!(response.status(), axum::http::StatusCode::UNAUTHORIZED);
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
             VALUES ('profile-a', 4, strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), \
             strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))",
        )
        .execute(&pool)
        .await
        .expect("profile is persisted");
        sqlx::query(
            "INSERT INTO devices \
             (device_id, profile_id, created_at, last_seen_at, auth_token_hash) \
             VALUES ('device-a', 'profile-a', strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), \
             strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), ?)",
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
             VALUES ('profile-a', 3, strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), \
             strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))",
        )
        .execute(&pool)
        .await
        .expect("profile is persisted");
        let token_a = sync_api::hash_device_token("device-a-token");
        let token_b = sync_api::hash_device_token("device-b-token");
        sqlx::query(
            "INSERT INTO devices \
             (device_id, profile_id, created_at, last_seen_at, auth_token_hash) VALUES \
             ('device-a', 'profile-a', strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), \
              strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), ?), \
             ('device-b', 'profile-a', strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), \
              strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), ?)",
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
                    "recorded_at": recorded_at.clone(),
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
        assert_eq!(
            snapshot,
            serde_json::json!({
                "profile_id": "profile-a",
                "grade": 4,
                "history": [
                    {
                        "entry_id": "entry-a",
                        "expression": "2 × 3",
                        "result": "6",
                        "recorded_at": recorded_at,
                        "topic_tag": "multiplication"
                    },
                    {
                        "entry_id": "entry-b",
                        "expression": "7 − 4",
                        "result": "3",
                        "recorded_at": recorded_at,
                        "topic_tag": "subtraction"
                    }
                ]
            })
        );
    }

    #[tokio::test]
    async fn guardian_history_erasure_keeps_the_profile_and_paired_device() {
        let pool = SqlitePoolOptions::new()
            .max_connections(1)
            .connect("sqlite::memory:")
            .await
            .expect("temporary SQLite database");
        connect_and_migrate(&pool).await.expect("migrations apply");
        let token = "guardian-device-token";
        create_paired_profile(&pool, token, false).await;
        let guardian_token = "guardian-secret-for-profile-a";
        sqlx::query("UPDATE profiles SET guardian_token_hash = ? WHERE profile_id = 'profile-a'")
            .bind(sync_api::hash_device_token(guardian_token))
            .execute(&pool)
            .await
            .expect("guardian credential is provisioned");
        let erased_entry_recorded_at: String =
            sqlx::query_scalar("SELECT strftime('%Y-%m-%dT%H:%M:%fZ', 'now', '-1 second')")
                .fetch_one(&pool)
                .await
                .expect("recorded timestamp is available");
        sqlx::query(
            "INSERT INTO history_entries \
             (entry_id, profile_id, expression, result, recorded_at, topic_tag, expires_at) \
             VALUES ('entry-a', 'profile-a', '2 + 3', '5', ?, 'addition', \
             strftime('%Y-%m-%dT%H:%M:%fZ', ?, '+90 days'))",
        )
        .bind(&erased_entry_recorded_at)
        .bind(&erased_entry_recorded_at)
        .execute(&pool)
        .await
        .expect("history is persisted");
        let app = sync_api::routes()
            .with_state(pool.clone())
            .merge(pairing::router(
                pool.clone(),
                pairing::PairingConfig::new(vec![b'p'; 32]).expect("pairing config is valid"),
            ));

        let device_erase = request_history_erase(app.clone(), "profile-a", Some(token), None).await;
        assert_eq!(device_erase.status(), axum::http::StatusCode::UNAUTHORIZED);

        let unauthenticated = request_history_erase(app.clone(), "profile-a", None, None).await;
        assert_eq!(
            unauthenticated.status(),
            axum::http::StatusCode::UNAUTHORIZED
        );

        let erased =
            request_history_erase(app.clone(), "profile-a", None, Some(guardian_token)).await;
        assert_eq!(erased.status(), axum::http::StatusCode::NO_CONTENT);

        let snapshot = app
            .clone()
            .oneshot(
                Request::builder()
                    .uri("/v1/profiles/profile-a/sync")
                    .header("authorization", format!("Bearer {token}"))
                    .body(Body::empty())
                    .expect("valid snapshot request"),
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
        assert_eq!(snapshot["profile_id"], "profile-a");
        assert_eq!(snapshot["history"], serde_json::json!([]));

        let pairing = app
            .clone()
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/api/pairing-codes")
                    .header("authorization", format!("Bearer {token}"))
                    .body(Body::empty())
                    .expect("valid pairing-code request"),
            )
            .await
            .expect("pairing endpoint responds");
        assert_eq!(pairing.status(), axum::http::StatusCode::CREATED);

        let replayed_entry = submit_sync(
            app.clone(),
            "profile-a",
            token,
            serde_json::json!({
                "history": [{
                    "entry_id": "entry-a",
                    "expression": "2 + 3",
                    "result": "5",
                    "recorded_at": erased_entry_recorded_at,
                    "topic_tag": "addition"
                }]
            }),
        )
        .await;
        assert_eq!(
            replayed_entry.status(),
            axum::http::StatusCode::UNPROCESSABLE_ENTITY
        );

        let future_recorded_at: String =
            sqlx::query_scalar("SELECT strftime('%Y-%m-%dT%H:%M:%fZ', 'now', '+1 minute')")
                .fetch_one(&pool)
                .await
                .expect("future timestamp is available");
        let future_replay = submit_sync(
            app.clone(),
            "profile-a",
            token,
            serde_json::json!({
                "history": [{
                    "entry_id": "entry-c",
                    "expression": "3 + 2",
                    "result": "5",
                    "recorded_at": future_recorded_at,
                    "topic_tag": "addition"
                }]
            }),
        )
        .await;
        assert_eq!(
            future_replay.status(),
            axum::http::StatusCode::UNPROCESSABLE_ENTITY
        );

        let recorded_at: String =
            sqlx::query_scalar("SELECT strftime('%Y-%m-%dT%H:%M:%fZ', 'now')")
                .fetch_one(&pool)
                .await
                .expect("current timestamp is available");
        let next_entry = submit_sync(
            app.clone(),
            "profile-a",
            token,
            serde_json::json!({
                "history": [{
                    "entry_id": "entry-b",
                    "expression": "4 + 1",
                    "result": "5",
                    "recorded_at": recorded_at,
                    "topic_tag": "addition"
                }]
            }),
        )
        .await;
        assert_eq!(next_entry.status(), axum::http::StatusCode::OK);
    }

    #[tokio::test]
    async fn empty_profiles_and_pairing_metadata_expire_after_inactivity() {
        let pool = SqlitePoolOptions::new()
            .max_connections(1)
            .connect("sqlite::memory:")
            .await
            .expect("temporary SQLite database");
        connect_and_migrate(&pool).await.expect("migrations apply");
        let token = "inactive-device-token";
        create_paired_profile(&pool, token, true).await;
        sqlx::query(
            "INSERT INTO pairing_codes \
             (pairing_id, profile_id, code_hash, created_at, expires_at) \
             VALUES ('pair-a', 'profile-a', 'expired-code-hash', \
             strftime('%Y-%m-%dT%H:%M:%fZ', 'now', '-91 days'), \
             strftime('%Y-%m-%dT%H:%M:%fZ', 'now', '-90 days'))",
        )
        .execute(&pool)
        .await
        .expect("pairing metadata is persisted");
        let app = sync_api::routes().with_state(pool);

        let expired = app
            .oneshot(
                Request::builder()
                    .uri("/v1/profiles/profile-a/sync")
                    .header("authorization", format!("Bearer {token}"))
                    .body(Body::empty())
                    .expect("valid snapshot request"),
            )
            .await
            .expect("sync endpoint responds");

        assert_eq!(expired.status(), axum::http::StatusCode::FORBIDDEN);
    }

    #[tokio::test]
    async fn linked_device_activity_does_not_extend_history_entry_expiry() {
        let pool = SqlitePoolOptions::new()
            .max_connections(1)
            .connect("sqlite::memory:")
            .await
            .expect("temporary SQLite database");
        connect_and_migrate(&pool).await.expect("migrations apply");
        let token = "active-device-token";
        create_paired_profile(&pool, token, false).await;
        sqlx::query(
            "INSERT INTO history_entries \
             (entry_id, profile_id, expression, result, recorded_at, topic_tag, expires_at) \
             VALUES \
             ('expired-entry', 'profile-a', '1 + 1', '2', \
              strftime('%Y-%m-%dT%H:%M:%fZ', 'now', '-90 days', '-1 second'), \
              'addition', strftime('%Y-%m-%dT%H:%M:%fZ', 'now', '-1 second')), \
             ('retained-entry', 'profile-a', '2 + 2', '4', \
              strftime('%Y-%m-%dT%H:%M:%fZ', 'now', '-89 days'), \
              'addition', strftime('%Y-%m-%dT%H:%M:%fZ', 'now', '+1 day'))",
        )
        .execute(&pool)
        .await
        .expect("history entries are persisted");
        let app = sync_api::routes().with_state(pool);

        let snapshot = app
            .oneshot(
                Request::builder()
                    .uri("/v1/profiles/profile-a/sync")
                    .header("authorization", format!("Bearer {token}"))
                    .body(Body::empty())
                    .expect("valid snapshot request"),
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
        let history = snapshot["history"].as_array().expect("history list");
        assert_eq!(history.len(), 1);
        assert_eq!(history[0]["entry_id"], "retained-entry");
        assert_eq!(history[0]["expression"], "2 + 2");
    }

    #[tokio::test]
    async fn future_recorded_at_is_rejected_by_the_sync_http_contract() {
        let pool = SqlitePoolOptions::new()
            .max_connections(1)
            .connect("sqlite::memory:")
            .await
            .expect("temporary SQLite database");
        connect_and_migrate(&pool).await.expect("migrations apply");
        let token = "future-timestamp-device-token";
        create_paired_profile(&pool, token, false).await;
        let future_recorded_at: String =
            sqlx::query_scalar("SELECT strftime('%Y-%m-%dT%H:%M:%fZ', 'now', '+1 minute')")
                .fetch_one(&pool)
                .await
                .expect("future timestamp is available");
        let app = sync_api::routes().with_state(pool);

        let response = submit_sync(
            app,
            "profile-a",
            token,
            serde_json::json!({
                "history": [{
                    "entry_id": "future-entry",
                    "expression": "1 + 1",
                    "result": "2",
                    "recorded_at": future_recorded_at,
                    "topic_tag": "addition"
                }]
            }),
        )
        .await;

        assert_eq!(
            response.status(),
            axum::http::StatusCode::UNPROCESSABLE_ENTITY
        );
    }
}
