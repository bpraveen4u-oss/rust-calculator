use axum::{body::Body, http::Request};
use http_body_util::BodyExt;
use learning_calculator_service::{app, connect_and_migrate};
use sqlx::sqlite::SqlitePoolOptions;
use tower::ServiceExt;

#[tokio::test]
async fn readiness_reports_success_when_the_database_is_available() {
    let pool = SqlitePoolOptions::new()
        .max_connections(1)
        .connect("sqlite::memory:")
        .await
        .expect("temporary SQLite database");
    connect_and_migrate(&pool).await.expect("migrations apply");

    let response = app(pool)
        .oneshot(
            Request::builder()
                .uri("/health/ready")
                .body(Body::empty())
                .expect("valid request"),
        )
        .await
        .expect("health endpoint responds");

    assert_eq!(response.status(), axum::http::StatusCode::OK);
    let body = response.into_body().collect().await.expect("response body");
    assert_eq!(body.to_bytes(), r#"{"status":"ready"}"#);
}

#[tokio::test]
async fn migrations_create_pseudonymous_persistence_tables_and_restrict_grade() {
    let pool = SqlitePoolOptions::new()
        .max_connections(1)
        .connect("sqlite::memory:")
        .await
        .expect("temporary SQLite database");
    connect_and_migrate(&pool).await.expect("migrations apply");

    let table_count: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name IN \
         ('profiles', 'devices', 'pairing_codes', 'history_entries')",
    )
    .fetch_one(&pool)
    .await
    .expect("schema can be inspected");
    assert_eq!(table_count, 4);

    sqlx::query(
        "INSERT INTO profiles (profile_id, grade, created_at, last_activity_at) \
         VALUES ('opaque-profile', 4, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')",
    )
    .execute(&pool)
    .await
    .expect("pseudonymous profile can be persisted");

    let invalid_grade = sqlx::query(
        "INSERT INTO profiles (profile_id, grade, created_at, last_activity_at) \
         VALUES ('invalid-grade', 6, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')",
    )
    .execute(&pool)
    .await;
    assert!(invalid_grade.is_err());
}

#[tokio::test]
async fn readiness_reports_unavailable_when_the_database_is_closed() {
    let pool = SqlitePoolOptions::new()
        .max_connections(1)
        .connect("sqlite::memory:")
        .await
        .expect("temporary SQLite database");
    pool.close().await;

    let response = app(pool)
        .oneshot(
            Request::builder()
                .uri("/health/ready")
                .body(Body::empty())
                .expect("valid request"),
        )
        .await
        .expect("health endpoint responds");

    assert_eq!(
        response.status(),
        axum::http::StatusCode::SERVICE_UNAVAILABLE
    );
}
