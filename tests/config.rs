use learning_calculator_service::config::{Config, ConfigError};

#[test]
fn configuration_rejects_an_invalid_bind_address() {
    let error = Config::from_values("not-an-address", "sqlite://service.db".into())
        .expect_err("invalid bind address must fail");

    assert_eq!(error, ConfigError::InvalidBindAddress);
}

#[test]
fn configuration_accepts_local_defaults_explicitly() {
    let config =
        Config::from_values("127.0.0.1:3000", "sqlite://service.db".into()).expect("valid config");

    assert_eq!(config.bind_addr.to_string(), "127.0.0.1:3000");
    assert_eq!(config.database_url, "sqlite://service.db");
}
