use std::str::FromStr;

use learning_calculator_service::{app, config::Config, connect_and_migrate};
use sqlx::sqlite::{SqliteConnectOptions, SqlitePoolOptions};
use tracing_subscriber::EnvFilter;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    tracing_subscriber::fmt()
        .with_env_filter(EnvFilter::try_from_default_env().unwrap_or_else(|_| "info".into()))
        .init();

    let config = Config::from_env()?;
    let sqlite_options = SqliteConnectOptions::from_str(&config.database_url)?
        .create_if_missing(true)
        .foreign_keys(true);
    let pool = SqlitePoolOptions::new()
        .connect_with(sqlite_options)
        .await?;
    connect_and_migrate(&pool).await?;

    let listener = tokio::net::TcpListener::bind(config.bind_addr).await?;
    tracing::info!(address = %config.bind_addr, "service listening");
    axum::serve(listener, app(pool)).await?;
    Ok(())
}
