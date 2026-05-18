#!/usr/bin/env sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ENV_FILE="${ENV_FILE:-$ROOT_DIR/.env}"
COMPOSE_FILE="${COMPOSE_FILE:-$ROOT_DIR/docker-compose.sidecar.yml}"

fail() {
  printf 'ERROR: %s\n' "$1" >&2
  exit 1
}

note() {
  printf '%s\n' "$1"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "missing command: $1"
}

load_env() {
  [ -f "$ENV_FILE" ] || fail "missing env file: $ENV_FILE"
  set -a
  # shellcheck disable=SC1090
  . "$ENV_FILE"
  set +a
}

require_var() {
  eval "value=\${$1:-}"
  [ -n "${value}" ] || fail "missing required env: $1"
}

check_file() {
  [ -f "$1" ] || fail "missing file: $1"
}

check_url() {
  case "$1" in
    http://*|https://*) ;;
    *) fail "invalid url for $2: $1" ;;
  esac
}

detect_compose() {
  if docker compose version >/dev/null 2>&1; then
    printf 'docker compose'
    return 0
  fi
  if command -v docker-compose >/dev/null 2>&1; then
    printf 'docker-compose'
    return 0
  fi
  fail "docker compose not available"
}

main() {
  note "Checking prerequisites..."
  require_cmd docker
  COMPOSE_CMD=$(detect_compose)

  note "Checking files..."
  check_file "$COMPOSE_FILE"
  check_file "$ROOT_DIR/quota-dashboard/server.sh"
  check_file "$ROOT_DIR/quota-dashboard/index.html"
  check_file "$ROOT_DIR/quota-dashboard/query.sql"
  check_file "$ROOT_DIR/quota-dashboard/init.sql"

  note "Loading env..."
  load_env

  note "Checking required env..."
  require_var POSTGRES_HOST
  require_var POSTGRES_PORT
  require_var POSTGRES_USER
  require_var POSTGRES_PASSWORD
  require_var POSTGRES_DB
  require_var QUOTA_DASHBOARD_SUB2API_BASE_URL
  require_var QUOTA_DASHBOARD_TOKEN
  require_var QUOTA_DASHBOARD_PORT

  if [ -z "${QUOTA_DASHBOARD_ADMIN_API_KEY:-}" ]; then
    require_var QUOTA_DASHBOARD_ADMIN_EMAIL
    require_var QUOTA_DASHBOARD_ADMIN_PASSWORD
  fi

  check_url "$QUOTA_DASHBOARD_SUB2API_BASE_URL" "QUOTA_DASHBOARD_SUB2API_BASE_URL"
  if [ -n "${QUOTA_DASHBOARD_PUBLIC_URL:-}" ]; then
    check_url "$QUOTA_DASHBOARD_PUBLIC_URL" "QUOTA_DASHBOARD_PUBLIC_URL"
  fi

  note "Checking Docker access..."
  docker info >/dev/null 2>&1 || fail "docker daemon is not reachable"

  note "Checking compose config..."
  if [ "$COMPOSE_CMD" = "docker compose" ]; then
    docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" config >/dev/null
  else
    docker-compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" config >/dev/null
  fi

  note "OK"
  note "Prerequisites:"
  note "- sub2api and PostgreSQL must already be running"
  note "- the quota dashboard container must be able to reach POSTGRES_HOST"
  note "- the quota dashboard container must be able to reach QUOTA_DASHBOARD_SUB2API_BASE_URL"
  note "- if sub2api runs in another Docker network, join that network before deploy"
  note "- scheduled refresh can use QUOTA_DASHBOARD_ADMIN_API_KEY or fallback admin credentials"
}

main "$@"
