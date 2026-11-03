use std::{env, net::SocketAddr, str::FromStr};

use thiserror::Error;

#[derive(Debug, Error, PartialEq, Eq)]
pub enum ConfigError {
    #[error("DATABASE_URL must be set")]
    MissingDatabaseUrl,
    #[error("BIND_ADDR must be a valid socket address")]
    InvalidBindAddress,
}

#[derive(Debug, Clone)]
pub struct Config {
    pub bind_addr: SocketAddr,
    pub database_url: String,
}

impl Config {
    pub fn from_env() -> Result<Self, ConfigError> {
        let database_url = env::var("DATABASE_URL").map_err(|_| ConfigError::MissingDatabaseUrl)?;
        let bind_addr = env::var("BIND_ADDR").unwrap_or_else(|_| "127.0.0.1:3000".into());
        Self::from_values(&bind_addr, database_url)
    }

    pub fn from_values(bind_addr: &str, database_url: String) -> Result<Self, ConfigError> {
        let bind_addr =
            SocketAddr::from_str(bind_addr).map_err(|_| ConfigError::InvalidBindAddress)?;
        Ok(Self {
            bind_addr,
            database_url,
        })
    }
}
