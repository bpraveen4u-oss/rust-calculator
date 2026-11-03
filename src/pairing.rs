use std::{net::SocketAddr, sync::Arc};

use axum::{
    Json, Router,
    extract::{ConnectInfo, State},
    http::{HeaderMap, StatusCode, header},
    response::IntoResponse,
    routing::post,
};
use hmac::{Hmac, Mac};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use sqlx::SqlitePool;

use crate::retention::expire_cloud_data;

type HmacSha256 = Hmac<Sha256>;

const CODE_ALPHABET: &[u8; 32] = b"ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
const CODE_LENGTH: usize = 10;
const CODE_LIFETIME_SECONDS: i64 = 10 * 60;
const ATTEMPT_LIMIT: i64 = 5;
const ATTEMPT_WINDOW_SECONDS: i64 = 10 * 60;
const UNAVAILABLE_MESSAGE: &str = "pairing unavailable";

#[derive(Clone, Debug)]
pub struct PairingConfig {
    pepper: Arc<[u8]>,
}

impl PairingConfig {
    pub fn new(pepper: Vec<u8>) -> Result<Self, &'static str> {
        if pepper.len() < 32 {
            return Err("pairing pepper must contain at least 32 bytes");
        }

        Ok(Self {
            pepper: pepper.into(),
        })
    }
}

#[derive(Clone)]
struct PairingState {
    pool: SqlitePool,
    config: PairingConfig,
}

#[derive(Serialize)]
struct CreatedCode {
    code: String,
    expires_at: String,
}

#[derive(Deserialize)]
struct PairRequest {
    code: String,
}

#[derive(Serialize)]
struct PairedDevice {
    device_id: String,
    device_token: String,
}

#[derive(Serialize)]
struct ErrorResponse {
    error: &'static str,
}

enum PairOutcome {
    Created(PairedDevice),
    Unavailable,
    RateLimited,
}

pub(crate) fn router(pool: SqlitePool, config: PairingConfig) -> Router {
    Router::new()
        .route("/api/pairing-codes", post(create_code))
        .route("/api/pair", post(pair_device))
        .with_state(PairingState { pool, config })
}

async fn create_code(State(state): State<PairingState>, headers: HeaderMap) -> impl IntoResponse {
    if expire_cloud_data(&state.pool).await.is_err() {
        return StatusCode::INTERNAL_SERVER_ERROR.into_response();
    }
    let Some(token) = headers
        .get(header::AUTHORIZATION)
        .and_then(|value| value.to_str().ok())
        .and_then(|value| value.strip_prefix("Bearer "))
        .filter(|value| !value.is_empty())
    else {
        return StatusCode::UNAUTHORIZED.into_response();
    };

    let token_hash = sha256_hex(token.as_bytes());
    let profile_id = match sqlx::query_scalar::<_, String>(
        "SELECT profile_id FROM devices WHERE auth_token_hash = ?",
    )
    .bind(&token_hash)
    .fetch_optional(&state.pool)
    .await
    {
        Ok(Some(profile_id)) => profile_id,
        Ok(None) => return StatusCode::UNAUTHORIZED.into_response(),
        Err(_) => return StatusCode::INTERNAL_SERVER_ERROR.into_response(),
    };

    let updated = sqlx::query(
        "UPDATE devices SET last_seen_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now') \
         WHERE auth_token_hash = ?",
    )
    .bind(&token_hash)
    .execute(&state.pool)
    .await;
    if updated.is_err() {
        return StatusCode::INTERNAL_SERVER_ERROR.into_response();
    }
    let activity = sqlx::query(
        "UPDATE profiles SET last_activity_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now') \
         WHERE profile_id = ?",
    )
    .bind(&profile_id)
    .execute(&state.pool)
    .await;
    if activity.is_err() {
        return StatusCode::INTERNAL_SERVER_ERROR.into_response();
    }

    let mut random = [0; CODE_LENGTH];
    if getrandom::getrandom(&mut random).is_err() {
        return StatusCode::INTERNAL_SERVER_ERROR.into_response();
    }
    let code: String = random
        .iter()
        .map(|byte| CODE_ALPHABET[usize::from(byte & 31)] as char)
        .collect();
    let Some(code_hash) = keyed_hash(&state.config.pepper, code.as_bytes()) else {
        return StatusCode::INTERNAL_SERVER_ERROR.into_response();
    };
    let mut random_id = [0; 16];
    if getrandom::getrandom(&mut random_id).is_err() {
        return StatusCode::INTERNAL_SERVER_ERROR.into_response();
    }
    let pairing_id = hex(&random_id);

    let expires_at = match sqlx::query_scalar::<_, String>(
        "INSERT INTO pairing_codes \
         (pairing_id, profile_id, code_hash, created_at, expires_at) \
         VALUES (?, ?, ?, strftime('%Y-%m-%dT%H:%M:%SZ', 'now'), \
                 strftime('%Y-%m-%dT%H:%M:%SZ', 'now', '+' || ? || ' seconds')) \
         RETURNING expires_at",
    )
    .bind(pairing_id)
    .bind(profile_id)
    .bind(code_hash)
    .bind(CODE_LIFETIME_SECONDS)
    .fetch_one(&state.pool)
    .await
    {
        Ok(expires_at) => expires_at,
        Err(_) => return StatusCode::INTERNAL_SERVER_ERROR.into_response(),
    };

    (StatusCode::CREATED, Json(CreatedCode { code, expires_at })).into_response()
}

async fn pair_device(
    State(state): State<PairingState>,
    ConnectInfo(address): ConnectInfo<SocketAddr>,
    Json(request): Json<PairRequest>,
) -> impl IntoResponse {
    match create_paired_device(&state, address, &request.code).await {
        Ok(PairOutcome::Created(device)) => (StatusCode::CREATED, Json(device)).into_response(),
        Ok(PairOutcome::Unavailable) => unavailable(StatusCode::BAD_REQUEST),
        Ok(PairOutcome::RateLimited) => unavailable(StatusCode::TOO_MANY_REQUESTS),
        Err(()) => StatusCode::INTERNAL_SERVER_ERROR.into_response(),
    }
}

async fn create_paired_device(
    state: &PairingState,
    address: SocketAddr,
    submitted_code: &str,
) -> Result<PairOutcome, ()> {
    expire_cloud_data(&state.pool).await.map_err(|_| ())?;
    let client_key =
        keyed_hash(&state.config.pepper, address.ip().to_string().as_bytes()).ok_or(())?;
    let code = normalize_code(submitted_code);
    let code_hash = keyed_hash(&state.config.pepper, code.as_bytes()).ok_or(())?;
    let mut transaction = state.pool.begin().await.map_err(|_| ())?;

    sqlx::query(
        "DELETE FROM pairing_attempts \
         WHERE window_started_at + ? <= CAST(strftime('%s', 'now') AS INTEGER)",
    )
    .bind(ATTEMPT_WINDOW_SECONDS)
    .execute(&mut *transaction)
    .await
    .map_err(|_| ())?;

    let attempts = sqlx::query_scalar::<_, i64>(
        "INSERT INTO pairing_attempts (client_key, window_started_at, attempts) \
         VALUES (?, CAST(strftime('%s', 'now') AS INTEGER), 1) \
         ON CONFLICT(client_key) DO UPDATE SET \
           attempts = CASE \
             WHEN pairing_attempts.window_started_at + ? <= \
                  CAST(strftime('%s', 'now') AS INTEGER) THEN 1 \
             ELSE pairing_attempts.attempts + 1 \
           END, \
           window_started_at = CASE \
             WHEN pairing_attempts.window_started_at + ? <= \
                  CAST(strftime('%s', 'now') AS INTEGER) \
             THEN CAST(strftime('%s', 'now') AS INTEGER) \
             ELSE pairing_attempts.window_started_at \
           END \
         RETURNING attempts",
    )
    .bind(client_key)
    .bind(ATTEMPT_WINDOW_SECONDS)
    .bind(ATTEMPT_WINDOW_SECONDS)
    .fetch_one(&mut *transaction)
    .await
    .map_err(|_| ())?;

    if attempts > ATTEMPT_LIMIT {
        transaction.commit().await.map_err(|_| ())?;
        return Ok(PairOutcome::RateLimited);
    }

    let profile_id = sqlx::query_scalar::<_, String>(
        "UPDATE pairing_codes \
         SET consumed_at = strftime('%Y-%m-%dT%H:%M:%SZ', 'now'), attempts = attempts + 1 \
         WHERE code_hash = ? AND consumed_at IS NULL \
           AND expires_at > strftime('%Y-%m-%dT%H:%M:%SZ', 'now') \
           AND attempts < ? \
         RETURNING profile_id",
    )
    .bind(code_hash)
    .bind(ATTEMPT_LIMIT)
    .fetch_optional(&mut *transaction)
    .await
    .map_err(|_| ())?;

    let Some(profile_id) = profile_id else {
        transaction.commit().await.map_err(|_| ())?;
        return Ok(PairOutcome::Unavailable);
    };

    let mut token_bytes = [0; 32];
    let mut device_bytes = [0; 16];
    if getrandom::getrandom(&mut token_bytes).is_err()
        || getrandom::getrandom(&mut device_bytes).is_err()
    {
        return Err(());
    }
    let device_token = hex(&token_bytes);
    let device_id = hex(&device_bytes);

    sqlx::query(
        "INSERT INTO devices \
         (device_id, profile_id, created_at, last_seen_at, auth_token_hash) \
         VALUES (?, ?, strftime('%Y-%m-%dT%H:%M:%SZ', 'now'), \
                 strftime('%Y-%m-%dT%H:%M:%SZ', 'now'), ?)",
    )
    .bind(&device_id)
    .bind(&profile_id)
    .bind(sha256_hex(device_token.as_bytes()))
    .execute(&mut *transaction)
    .await
    .map_err(|_| ())?;
    sqlx::query(
        "UPDATE profiles SET last_activity_at = strftime('%Y-%m-%dT%H:%M:%SZ', 'now') \
         WHERE profile_id = ?",
    )
    .bind(profile_id)
    .execute(&mut *transaction)
    .await
    .map_err(|_| ())?;

    transaction.commit().await.map_err(|_| ())?;
    Ok(PairOutcome::Created(PairedDevice {
        device_id,
        device_token,
    }))
}

fn unavailable(status: StatusCode) -> axum::response::Response {
    (
        status,
        Json(ErrorResponse {
            error: UNAVAILABLE_MESSAGE,
        }),
    )
        .into_response()
}

fn normalize_code(code: &str) -> String {
    code.chars()
        .filter(|character| *character != '-' && !character.is_ascii_whitespace())
        .map(|character| character.to_ascii_uppercase())
        .collect()
}

fn keyed_hash(key: &[u8], value: &[u8]) -> Option<String> {
    let mut mac = HmacSha256::new_from_slice(key).ok()?;
    mac.update(value);
    Some(hex(&mac.finalize().into_bytes()))
}

fn sha256_hex(value: &[u8]) -> String {
    hex(&Sha256::digest(value))
}

fn hex(bytes: &[u8]) -> String {
    const DIGITS: &[u8; 16] = b"0123456789abcdef";
    let mut encoded = String::with_capacity(bytes.len() * 2);
    for byte in bytes {
        encoded.push(DIGITS[usize::from(byte >> 4)] as char);
        encoded.push(DIGITS[usize::from(byte & 15)] as char);
    }
    encoded
}
