use axum::{Json, Router, http::StatusCode, routing::get};
use serde::Serialize;
use sqlx::{SqlitePool, migrate::MigrateError};
use thiserror::Error;

pub mod config;
pub mod pairing;

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
    Router::new()
        .route("/health/ready", get(readiness))
        .with_state(pool)
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
