use axum::{
    body::Body,
    extract::connect_info::ConnectInfo,
    http::{Request, Response},
};
use http_body_util::BodyExt;
use learning_calculator_service::{
    app, app_with_pairing, connect_and_migrate, pairing::PairingConfig,
};
use sha2::Digest;
use sqlx::sqlite::SqlitePoolOptions;
use tower::ServiceExt;

const OWNER_TOKEN: &str = "test-owner-device-token";
const PAIRING_PEPPER: &[u8] = b"test-only-pairing-pepper-with-32-bytes";

async fn pairing_database() -> sqlx::SqlitePool {
    let pool = SqlitePoolOptions::new()
        .max_connections(1)
        .connect("sqlite::memory:")
        .await
        .expect("temporary SQLite database");
    connect_and_migrate(&pool).await.expect("migrations apply");

    let token_hash = format!("{:x}", sha2::Sha256::digest(OWNER_TOKEN.as_bytes()));
    sqlx::query(
        "INSERT INTO profiles (profile_id, grade, created_at, last_activity_at) \
         VALUES ('opaque-profile', 4, strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), \
                 strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))",
    )
    .execute(&pool)
    .await
    .expect("fixture profile");
    sqlx::query(
        "INSERT INTO devices \
         (device_id, profile_id, created_at, last_seen_at, auth_token_hash) \
         VALUES ('owner-device', 'opaque-profile', strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), \
                 strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), ?)",
    )
    .bind(token_hash)
    .execute(&pool)
    .await
    .expect("fixture guardian device");
    pool
}

async fn post(
    pool: sqlx::SqlitePool,
    uri: &str,
    body: String,
    authorization: Option<&str>,
) -> Response<Body> {
    let mut request = Request::builder()
        .method("POST")
        .uri(uri)
        .header("content-type", "application/json")
        .extension(ConnectInfo(
            "127.0.0.1:12345"
                .parse::<std::net::SocketAddr>()
                .expect("socket address"),
        ));
    if let Some(authorization) = authorization {
        request = request.header("authorization", authorization);
    }

    app_with_pairing(
        pool,
        PairingConfig::new(PAIRING_PEPPER.to_vec()).expect("valid pairing config"),
    )
    .oneshot(request.body(Body::from(body)).expect("valid HTTP request"))
    .await
    .expect("pairing endpoint responds")
}

async fn response_json(response: Response<Body>) -> serde_json::Value {
    let body = response
        .into_body()
        .collect()
        .await
        .expect("response body")
        .to_bytes();
    serde_json::from_slice(&body).expect("JSON response")
}

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
async fn default_service_router_keeps_pairing_disabled() {
    let pool = pairing_database().await;
    let response = app(pool)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/pairing-codes")
                .body(Body::from("{}"))
                .expect("valid request"),
        )
        .await
        .expect("service responds");

    assert_eq!(response.status(), axum::http::StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn guardian_can_create_a_code_and_pair_a_second_device_once() {
    let pool = pairing_database().await;
    let created = post(
        pool.clone(),
        "/api/pairing-codes",
        "{}".to_owned(),
        Some(&format!("Bearer {OWNER_TOKEN}")),
    )
    .await;

    assert_eq!(created.status(), axum::http::StatusCode::CREATED);
    let created = response_json(created).await;
    let code = created["code"].as_str().expect("manual pairing code");
    assert_eq!(code.len(), 10);

    let paired = post(
        pool.clone(),
        "/api/pair",
        serde_json::json!({ "code": code }).to_string(),
        None,
    )
    .await;
    assert_eq!(paired.status(), axum::http::StatusCode::CREATED);
    let paired = response_json(paired).await;
    assert!(paired["device_id"].as_str().is_some());
    assert!(paired["device_token"].as_str().is_some());
    assert_eq!(paired["profile_id"], "opaque-profile");

    let reused = post(
        pool,
        "/api/pair",
        serde_json::json!({ "code": code }).to_string(),
        None,
    )
    .await;
    assert_eq!(reused.status(), axum::http::StatusCode::BAD_REQUEST);
    assert_eq!(
        response_json(reused).await,
        serde_json::json!({ "error": "pairing unavailable" })
    );
}

#[tokio::test]
async fn expired_and_unrecognized_codes_have_the_same_response() {
    let pool = pairing_database().await;
    let created = post(
        pool.clone(),
        "/api/pairing-codes",
        "{}".to_owned(),
        Some(&format!("Bearer {OWNER_TOKEN}")),
    )
    .await;
    let code = response_json(created).await["code"]
        .as_str()
        .expect("manual pairing code")
        .to_owned();

    sqlx::query("UPDATE pairing_codes SET expires_at = '2000-01-01T00:00:00Z'")
        .execute(&pool)
        .await
        .expect("expire test code");

    let expired = post(
        pool.clone(),
        "/api/pair",
        serde_json::json!({ "code": code }).to_string(),
        None,
    )
    .await;
    assert_eq!(expired.status(), axum::http::StatusCode::BAD_REQUEST);
    let expired_body = response_json(expired).await;

    let unknown = post(
        pool,
        "/api/pair",
        serde_json::json!({ "code": "0000000000" }).to_string(),
        None,
    )
    .await;
    assert_eq!(unknown.status(), axum::http::StatusCode::BAD_REQUEST);
    assert_eq!(response_json(unknown).await, expired_body);
}

#[tokio::test]
async fn pairing_attempts_are_limited_per_client() {
    let pool = pairing_database().await;
    for _ in 0..5 {
        let response = post(
            pool.clone(),
            "/api/pair",
            r#"{"code":"0000000000"}"#.to_owned(),
            None,
        )
        .await;
        assert_eq!(response.status(), axum::http::StatusCode::BAD_REQUEST);
        assert_eq!(
            response_json(response).await,
            serde_json::json!({ "error": "pairing unavailable" })
        );
    }

    let limited = post(
        pool,
        "/api/pair",
        r#"{"code":"0000000000"}"#.to_owned(),
        None,
    )
    .await;
    assert_eq!(limited.status(), axum::http::StatusCode::TOO_MANY_REQUESTS);
    assert_eq!(
        response_json(limited).await,
        serde_json::json!({ "error": "pairing unavailable" })
    );
}

#[tokio::test]
async fn only_an_authenticated_device_can_create_a_pairing_code() {
    let pool = pairing_database().await;

    let missing = post(pool.clone(), "/api/pairing-codes", "{}".to_owned(), None).await;
    assert_eq!(missing.status(), axum::http::StatusCode::UNAUTHORIZED);

    let invalid = post(
        pool,
        "/api/pairing-codes",
        "{}".to_owned(),
        Some("Bearer not-a-device-token"),
    )
    .await;
    assert_eq!(invalid.status(), axum::http::StatusCode::UNAUTHORIZED);
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
