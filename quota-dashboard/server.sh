#!/bin/sh
set -eu

PORT="${PORT:-8081}"
SNAPSHOT_INTERVAL_SECONDS="${SNAPSHOT_INTERVAL_SECONDS:-3600}"
SUB2API_BASE_URL="${SUB2API_BASE_URL:?SUB2API_BASE_URL is required}"
QUOTA_DASHBOARD_MENU_ID="${QUOTA_DASHBOARD_MENU_ID:-account-quota-dashboard}"
QUOTA_DASHBOARD_MENU_LABEL="${QUOTA_DASHBOARD_MENU_LABEL:-账号额度统计}"
QUOTA_DASHBOARD_MENU_VISIBILITY="${QUOTA_DASHBOARD_MENU_VISIBILITY:-admin}"
if [ "${QUOTA_DASHBOARD_MENU_ICON_SVG+x}" != "x" ]; then
    QUOTA_DASHBOARD_MENU_ICON_SVG='<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><path d="M4.75 19.25h14.5"/><path d="M7.25 15.5V11"/><path d="M12 15.5V8.25"/><path d="M16.75 15.5v-3.25"/><path d="M6.75 8.25 10.25 6l2.75 1.5 4.25-3"/></svg>'
fi
USAGE_REFRESH_INTERVAL_SECONDS="${USAGE_REFRESH_INTERVAL_SECONDS:-3600}"
USAGE_REFRESH_BATCH_SIZE="${USAGE_REFRESH_BATCH_SIZE:-1000}"
USAGE_REFRESH_TIMEOUT_SECONDS="${USAGE_REFRESH_TIMEOUT_SECONDS:-15}"
USAGE_REFRESH_TOKEN_FILE="${USAGE_REFRESH_TOKEN_FILE:-/tmp/quota-dashboard-admin-token}"
USAGE_REFRESH_LOCK_DIR="${USAGE_REFRESH_LOCK_DIR:-/tmp/quota-dashboard-usage-refresh.lock}"
SUB2API_ADMIN_EMAIL="${SUB2API_ADMIN_EMAIL:-}"
SUB2API_ADMIN_PASSWORD="${SUB2API_ADMIN_PASSWORD:-}"

AUTHORIZED_ADMIN_TOKEN=""

export PGPASSWORD="${POSTGRES_PASSWORD:?POSTGRES_PASSWORD is required}"

psql_base() {
    psql \
        -h "${POSTGRES_HOST:-postgres}" \
        -p "${POSTGRES_PORT:-5432}" \
        -U "${POSTGRES_USER:-sub2api}" \
        -d "${POSTGRES_DB:-sub2api}" \
        "$@"
}

send_response() {
    status="$1"
    content_type="$2"
    body="$3"
    content_length="$(printf '%s' "$body" | wc -c | tr -d ' ')"
    printf 'HTTP/1.1 %s\r\n' "$status"
    printf 'Content-Type: %s\r\n' "$content_type"
    printf 'Content-Length: %s\r\n' "$content_length"
    printf 'Cache-Control: no-store\r\n'
    printf 'X-Content-Type-Options: nosniff\r\n'
    printf 'Connection: close\r\n'
    printf '\r\n'
    printf '%s' "$body"
}

query_param() {
    name="$1"
    query="$2"
    printf '%s' "$query" | tr '&' '\n' | awk -F= -v key="$name" '$1 == key { print $2; exit }'
}

is_admin_token() {
    token="$1"
    [ -n "$token" ] || return 1
    wget -q -T 5 --tries=1 -O /dev/null \
        --header="Authorization: Bearer $token" \
        "${SUB2API_BASE_URL%/}/api/v1/admin/users?page_size=1"
}

login_admin_token() {
    [ -n "$SUB2API_ADMIN_EMAIL" ] || return 1
    [ -n "$SUB2API_ADMIN_PASSWORD" ] || return 1

    body="$(printf '{"email":"%s","password":"%s"}' "$SUB2API_ADMIN_EMAIL" "$SUB2API_ADMIN_PASSWORD")"
    response="$(wget -q -T 10 --tries=1 -O - \
        --header='Content-Type: application/json' \
        --post-data="$body" \
        "${SUB2API_BASE_URL%/}/api/v1/auth/login")" || return 1

    token="$(printf '%s' "$response" | sed -n 's/.*"access_token"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"
    [ -n "$token" ] || return 1
    save_admin_token "$token"
    printf '%s' "$token"
}

is_authorized() {
    query="$1"
    AUTHORIZED_ADMIN_TOKEN=""
    token="$(query_param token "$query")"
    if [ -n "$token" ] && is_admin_token "$token"; then
        AUTHORIZED_ADMIN_TOKEN="$token"
        return 0
    fi

    secret="$(query_param secret "$query")"
    if [ -n "${DASHBOARD_TOKEN:-}" ] && [ "$secret" = "$DASHBOARD_TOKEN" ]; then
        return 0
    fi
    return 1
}

sync_custom_menu() {
    [ -n "${QUOTA_DASHBOARD_PUBLIC_URL:-}" ] || return 0

    psql_base \
        -v ON_ERROR_STOP=1 \
        -v menu_id="$QUOTA_DASHBOARD_MENU_ID" \
        -v menu_label="$QUOTA_DASHBOARD_MENU_LABEL" \
        -v menu_url="$QUOTA_DASHBOARD_PUBLIC_URL" \
        -v menu_visibility="$QUOTA_DASHBOARD_MENU_VISIBILITY" \
        -v menu_icon_svg="${QUOTA_DASHBOARD_MENU_ICON_SVG:-}" \
        -f /app/sync_menu.sql >/dev/null
}

save_admin_token() {
    token="$1"
    [ -n "$token" ] || return 0

    umask 077
    tmp_file="${USAGE_REFRESH_TOKEN_FILE}.tmp"
    printf '%s' "$token" > "$tmp_file"
    mv "$tmp_file" "$USAGE_REFRESH_TOKEN_FILE"
}

load_admin_token() {
    [ -f "$USAGE_REFRESH_TOKEN_FILE" ] || return 1
    tr -d '\r\n' < "$USAGE_REFRESH_TOKEN_FILE"
}

fetch_usage_account_ids() {
    psql_base \
        -qAtX \
        -v ON_ERROR_STOP=1 \
        -v batch_size="$USAGE_REFRESH_BATCH_SIZE" \
        -f /app/refresh_usage_accounts.sql
}

record_refresh_state() {
    account_id="$1"
    refresh_status="$2"
    refresh_error="${3:-}"
    usage_updated_at="${4:-}"
    five_hour_success="${5:-f}"
    seven_day_success="${6:-f}"
    primary_success="${7:-f}"
    secondary_success="${8:-f}"

    psql_base \
        -qAtX \
        -v ON_ERROR_STOP=1 \
        -v account_id="$account_id" \
        -v refresh_status="$refresh_status" \
        -v refresh_error="$refresh_error" \
        -v usage_updated_at="$usage_updated_at" \
        -v five_hour_success="$five_hour_success" \
        -v seven_day_success="$seven_day_success" \
        -v primary_success="$primary_success" \
        -v secondary_success="$secondary_success" \
        -f /app/record_usage_refresh.sql >/dev/null
}

refresh_account_usage() {
    account_id="$1"
    token="$2"
    if body="$(wget -q -T "$USAGE_REFRESH_TIMEOUT_SECONDS" --tries=1 -O - \
        --header="Authorization: Bearer $token" \
        "${SUB2API_BASE_URL%/}/api/v1/admin/accounts/${account_id}/usage")"; then
        body_b64="$(printf '%s' "$body" | base64 | tr -d '\n')"
        if psql_base \
            -qAtX \
            -v ON_ERROR_STOP=1 \
            -v account_id="$account_id" \
            -v body_b64="$body_b64" \
            -f /app/persist_usage_response.sql >/dev/null; then
            return 0
        fi
        record_refresh_state "$account_id" "failed" "persist_usage_response_failed"
        return 1
    else
        record_refresh_state "$account_id" "failed" "usage_request_failed"
        return 1
    fi
}

run_usage_refresh() {
    source="${1:-scheduled}"
    token="${2:-}"

    if [ -z "$token" ]; then
        token="$(load_admin_token 2>/dev/null || true)"
    fi
    if [ -z "$token" ]; then
        token="$(login_admin_token 2>/dev/null || true)"
    fi

    if [ -z "$token" ]; then
        printf '[quota-dashboard] usage refresh skip source=%s reason=no_admin_token\n' "$source" >&2
        return 0
    fi

    if ! is_admin_token "$token"; then
        rm -f "$USAGE_REFRESH_TOKEN_FILE"
        token="$(login_admin_token 2>/dev/null || true)"
        if [ -z "$token" ] || ! is_admin_token "$token"; then
            printf '[quota-dashboard] usage refresh skip source=%s reason=admin_token_invalid\n' "$source" >&2
            rm -f "$USAGE_REFRESH_TOKEN_FILE"
            return 0
        fi
    fi

    ids="$(fetch_usage_account_ids)"
    total="$(printf '%s\n' "$ids" | sed '/^$/d' | wc -l | tr -d ' ')"
    if [ "$total" = "0" ]; then
        printf '[quota-dashboard] usage refresh skip source=%s reason=no_accounts\n' "$source" >&2
        return 0
    fi

    ok=0
    fail=0
    printf '[quota-dashboard] usage refresh start source=%s total=%s\n' "$source" "$total" >&2

    for account_id in $ids; do
        if refresh_account_usage "$account_id" "$token"; then
            ok=$((ok + 1))
        else
            fail=$((fail + 1))
            printf '[quota-dashboard] usage refresh account_failed source=%s account_id=%s\n' "$source" "$account_id" >&2
        fi
    done

    printf '[quota-dashboard] usage refresh done source=%s ok=%s fail=%s\n' "$source" "$ok" "$fail" >&2
}

start_usage_refresh_async() {
    source="${1:-scheduled}"
    token="${2:-}"

    if mkdir "$USAGE_REFRESH_LOCK_DIR" 2>/dev/null; then
        (
            trap 'rmdir "$USAGE_REFRESH_LOCK_DIR"' EXIT HUP INT TERM
            run_usage_refresh "$source" "$token"
        ) &
    else
        printf '[quota-dashboard] usage refresh skip source=%s reason=busy\n' "$source" >&2
    fi
}

serve_quota_payload() {
    if body="$(psql_base -qAtX -v ON_ERROR_STOP=1 -f /app/query.sql 2>&1)"; then
        printf '[quota-dashboard] quotas ok bytes=%s\n' "$(printf '%s' "$body" | wc -c | tr -d ' ')" >&2
        send_response "200 OK" "application/json; charset=utf-8" "$body"
    else
        escaped="$(printf '%s' "$body" | sed 's/\\/\\\\/g; s/"/\\"/g')"
        printf '[quota-dashboard] quotas error\n' >&2
        send_response "500 Internal Server Error" "application/json; charset=utf-8" "{\"error\":\"query_failed\",\"detail\":\"$escaped\"}"
    fi
}

handle_request() {
    IFS= read -r request_line || exit 0

    while IFS= read -r header_line; do
        [ "$header_line" = "$(printf '\r')" ] && break
        [ -z "$header_line" ] && break
    done

    method="$(printf '%s' "$request_line" | awk '{print $1}')"
    target="$(printf '%s' "$request_line" | awk '{print $2}')"
    path="${target%%\?*}"
    query=""
    [ "$target" != "$path" ] && query="${target#*\?}"

    if [ "$path" = "/health" ]; then
        send_response "200 OK" "text/plain; charset=utf-8" "ok"
        exit 0
    fi

    if [ "$method" != "GET" ]; then
        send_response "405 Method Not Allowed" "application/json; charset=utf-8" '{"error":"method_not_allowed"}'
        exit 0
    fi

    case "$path" in
        "/"|"/index.html")
            send_response "200 OK" "text/html; charset=utf-8" "$(cat /app/index.html)"
            ;;
        "/beacon")
            stage="$(query_param stage "$query")"
            detail="$(query_param detail "$query")"
            printf '[quota-dashboard] beacon stage=%s detail=%s\n' "$stage" "$detail" >&2
            send_response "204 No Content" "text/plain; charset=utf-8" ""
            ;;
        "/api/quotas")
            printf '[quota-dashboard] quotas start\n' >&2
            if ! is_authorized "$query"; then
                send_response "403 Forbidden" "application/json; charset=utf-8" '{"error":"forbidden"}'
                exit 0
            fi
            if [ -n "$AUTHORIZED_ADMIN_TOKEN" ]; then
                save_admin_token "$AUTHORIZED_ADMIN_TOKEN"
            fi
            serve_quota_payload
            ;;
        "/api/quotas/refresh")
            printf '[quota-dashboard] quotas refresh start\n' >&2
            if ! is_authorized "$query"; then
                send_response "403 Forbidden" "application/json; charset=utf-8" '{"error":"forbidden"}'
                exit 0
            fi
            if [ -n "$AUTHORIZED_ADMIN_TOKEN" ]; then
                save_admin_token "$AUTHORIZED_ADMIN_TOKEN"
                run_usage_refresh "manual" "$AUTHORIZED_ADMIN_TOKEN"
            else
                run_usage_refresh "manual"
            fi
            serve_quota_payload
            ;;
        *)
            send_response "404 Not Found" "application/json; charset=utf-8" '{"error":"not_found"}'
            ;;
    esac
}

start_server() {
    psql_base -v ON_ERROR_STOP=1 -f /app/init.sql >/dev/null
    sync_custom_menu

    while :; do
        psql_base -qAtX -v ON_ERROR_STOP=1 -f /app/query.sql >/dev/null 2>&1 || true
        sleep "$SNAPSHOT_INTERVAL_SECONDS"
    done &

    while :; do
        start_usage_refresh_async "scheduled"
        sleep "$USAGE_REFRESH_INTERVAL_SECONDS"
    done &

    exec nc -lk -p "$PORT" -e /app/server.sh handle
}

case "${1:-server}" in
    handle)
        handle_request
        ;;
    server)
        start_server
        ;;
    *)
        echo "unknown command: $1" >&2
        exit 2
        ;;
esac
