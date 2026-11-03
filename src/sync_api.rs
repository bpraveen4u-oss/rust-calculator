use axum::{
    Json, Router,
    extract::{Path, State},
    http::{HeaderMap, StatusCode},
    routing::get,
};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use sqlx::{FromRow, SqlitePool};

use crate::retention::expire_cloud_data;

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct SyncRequest {
    #[serde(default)]
    grade: Option<i32>,
    #[serde(default)]
    history: Vec<HistoryEntry>,
}

#[derive(Debug, Deserialize, Serialize, FromRow)]
#[serde(deny_unknown_fields)]
struct HistoryEntry {
    entry_id: String,
    expression: String,
    result: String,
    recorded_at: String,
    topic_tag: String,
}

#[derive(Serialize)]
struct SyncSnapshot {
    profile_id: String,
    grade: i32,
    history: Vec<HistoryEntry>,
}

pub(crate) fn routes() -> Router<SqlitePool> {
    Router::new()
        .route(
            "/v1/profiles/{profile_id}/sync",
            get(read_profile).post(write_profile),
        )
        .route(
            "/v1/profiles/{profile_id}/history",
            axum::routing::delete(erase_history),
        )
}

pub(crate) fn hash_device_token(token: &str) -> String {
    Sha256::digest(token.as_bytes())
        .iter()
        .map(|byte| format!("{byte:02x}"))
        .collect()
}

async fn read_profile(
    State(pool): State<SqlitePool>,
    Path(profile_id): Path<String>,
    headers: HeaderMap,
) -> Result<Json<SyncSnapshot>, StatusCode> {
    if !is_opaque_id(&profile_id) {
        return Err(StatusCode::BAD_REQUEST);
    }
    expire_cloud_data(&pool)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    authorize(&pool, &profile_id, &headers).await?;

    let grade = sqlx::query_scalar::<_, i32>("SELECT grade FROM profiles WHERE profile_id = ?")
        .bind(&profile_id)
        .fetch_optional(&pool)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?
        .ok_or(StatusCode::NOT_FOUND)?;
    let history = sqlx::query_as::<_, HistoryEntry>(
        "SELECT entry_id, expression, result, recorded_at, topic_tag \
         FROM history_entries \
         WHERE profile_id = ? AND julianday(expires_at) > julianday('now') \
         ORDER BY recorded_at, entry_id",
    )
    .bind(&profile_id)
    .fetch_all(&pool)
    .await
    .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    Ok(Json(SyncSnapshot {
        profile_id,
        grade,
        history,
    }))
}

async fn write_profile(
    State(pool): State<SqlitePool>,
    Path(profile_id): Path<String>,
    headers: HeaderMap,
    Json(request): Json<SyncRequest>,
) -> Result<Json<SyncSnapshot>, StatusCode> {
    if !is_opaque_id(&profile_id) {
        return Err(StatusCode::BAD_REQUEST);
    }
    expire_cloud_data(&pool)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    authorize(&pool, &profile_id, &headers).await?;
    if request.grade.is_none() && request.history.is_empty() {
        return Err(StatusCode::UNPROCESSABLE_ENTITY);
    }
    if request.grade.is_some_and(|grade| !(3..=5).contains(&grade)) {
        return Err(StatusCode::UNPROCESSABLE_ENTITY);
    }
    for entry in &request.history {
        if entry.entry_id.is_empty()
            || entry.entry_id.len() > 128
            || !is_opaque_id(&entry.entry_id)
            || !is_math_expression(&entry.expression)
            || entry.expression.len() > 500
            || !is_numeric_result(&entry.result)
            || entry.result.len() > 200
            || !is_allowed_topic(&entry.topic_tag)
            || entry.recorded_at.len() > 40
            || !(entry.recorded_at.ends_with('Z')
                || entry.recorded_at.ends_with("+00:00")
                || entry.recorded_at.ends_with("-00:00"))
        {
            return Err(StatusCode::UNPROCESSABLE_ENTITY);
        }
        let valid_timestamp = sqlx::query_scalar::<_, bool>(
            "SELECT julianday(?) IS NOT NULL \
             AND julianday(?) <= julianday('now', '+5 minutes') \
             AND julianday(?) > julianday('now', '-90 days')",
        )
        .bind(&entry.recorded_at)
        .bind(&entry.recorded_at)
        .bind(&entry.recorded_at)
        .fetch_one(&pool)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
        if !valid_timestamp {
            return Err(StatusCode::UNPROCESSABLE_ENTITY);
        }
    }

    let mut transaction = pool
        .begin()
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    for entry in &request.history {
        let is_after_clear = sqlx::query_scalar::<_, bool>(
            "SELECT history_cleared_at IS NULL \
             OR julianday(?) > julianday(history_cleared_at) \
             FROM profiles WHERE profile_id = ?",
        )
        .bind(&entry.recorded_at)
        .bind(&profile_id)
        .fetch_optional(&mut *transaction)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?
        .unwrap_or(false);
        if !is_after_clear {
            return Err(StatusCode::UNPROCESSABLE_ENTITY);
        }
    }
    if let Some(grade) = request.grade {
        let updated = sqlx::query(
            "UPDATE profiles SET grade = ?, \
             last_activity_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now') \
             WHERE profile_id = ?",
        )
        .bind(grade)
        .bind(&profile_id)
        .execute(&mut *transaction)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
        if updated.rows_affected() == 0 {
            return Err(StatusCode::NOT_FOUND);
        }
    }

    for entry in request.history {
        sqlx::query(
            "INSERT INTO history_entries \
             (entry_id, profile_id, expression, result, recorded_at, topic_tag, expires_at) \
             VALUES (?, ?, ?, ?, ?, ?, strftime('%Y-%m-%dT%H:%M:%fZ', ?, '+90 days')) \
             ON CONFLICT(entry_id) DO NOTHING",
        )
        .bind(&entry.entry_id)
        .bind(&profile_id)
        .bind(&entry.expression)
        .bind(&entry.result)
        .bind(&entry.recorded_at)
        .bind(&entry.topic_tag)
        .bind(&entry.recorded_at)
        .execute(&mut *transaction)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    }
    transaction
        .commit()
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    read_profile(State(pool), Path(profile_id), headers).await
}

async fn erase_history(
    State(pool): State<SqlitePool>,
    Path(profile_id): Path<String>,
    headers: HeaderMap,
) -> Result<StatusCode, StatusCode> {
    if !is_opaque_id(&profile_id) {
        return Err(StatusCode::BAD_REQUEST);
    }
    expire_cloud_data(&pool)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    authorize(&pool, &profile_id, &headers).await?;
    let mut transaction = pool
        .begin()
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    sqlx::query(
        "UPDATE profiles SET \
         history_cleared_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), \
         last_activity_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now') \
         WHERE profile_id = ?",
    )
    .bind(&profile_id)
    .execute(&mut *transaction)
    .await
    .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    sqlx::query("DELETE FROM history_entries WHERE profile_id = ?")
        .bind(profile_id)
        .execute(&mut *transaction)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    transaction
        .commit()
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    Ok(StatusCode::NO_CONTENT)
}

fn is_opaque_id(value: &str) -> bool {
    !value.is_empty()
        && value.len() <= 128
        && value
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'-' | b'_'))
}

fn is_math_expression(value: &str) -> bool {
    !value.is_empty()
        && value.len() <= 500
        && value.chars().any(|character| character.is_ascii_digit())
        && value.chars().all(|character| {
            character.is_ascii_digit()
                || matches!(
                    character,
                    '+' | '-' | '*' | '/' | '(' | ')' | '.' | ' ' | '×' | '÷' | '−'
                )
        })
}

fn is_numeric_result(value: &str) -> bool {
    !value.is_empty()
        && value.len() <= 200
        && value.bytes().any(|byte| byte.is_ascii_digit())
        && value
            .bytes()
            .all(|byte| byte.is_ascii_digit() || matches!(byte, b'-' | b'.' | b'/' | b' '))
}

fn is_allowed_topic(value: &str) -> bool {
    matches!(
        value,
        "addition"
            | "subtraction"
            | "multiplication"
            | "division"
            | "expressions"
            | "order_of_operations"
            | "fractions"
            | "decimals"
    )
}

async fn authorize(
    pool: &SqlitePool,
    profile_id: &str,
    headers: &HeaderMap,
) -> Result<(), StatusCode> {
    let token = headers
        .get(axum::http::header::AUTHORIZATION)
        .and_then(|value| value.to_str().ok())
        .and_then(|value| value.strip_prefix("Bearer "))
        .filter(|token| !token.is_empty())
        .ok_or(StatusCode::UNAUTHORIZED)?;
    let token_hash = hash_device_token(token);
    let mut transaction = pool
        .begin()
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    let device_id = sqlx::query_scalar::<_, String>(
        "UPDATE devices SET last_seen_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now') \
         WHERE profile_id = ? AND auth_token_hash = ? \
         RETURNING device_id",
    )
    .bind(profile_id)
    .bind(token_hash)
    .fetch_optional(&mut *transaction)
    .await
    .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    if device_id.is_none() {
        return Err(StatusCode::FORBIDDEN);
    }
    sqlx::query(
        "UPDATE profiles SET last_activity_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now') \
         WHERE profile_id = ?",
    )
    .bind(profile_id)
    .execute(&mut *transaction)
    .await
    .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    transaction
        .commit()
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    Ok(())
}
