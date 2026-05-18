#!/usr/bin/env sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ENV_FILE="${ENV_FILE:-$ROOT_DIR/.env}"
SIDECAR_COMPOSE_FILE="${SIDECAR_COMPOSE_FILE:-$ROOT_DIR/docker-compose.sidecar.yml}"
MAIN_COMPOSE_FILE="${MAIN_COMPOSE_FILE:-$ROOT_DIR/docker-compose.yml}"

fail() {
  printf 'ERROR: %s\n' "$1" >&2
  exit 1
}

note() {
  printf '%s\n' "$1"
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

run_check() {
  "$ROOT_DIR/check.sh"
}

deploy_with_main_compose() {
  note "Deploy mode: merge with existing docker-compose.yml"
  if [ "$COMPOSE_CMD" = "docker compose" ]; then
    docker compose --env-file "$ENV_FILE" -f "$MAIN_COMPOSE_FILE" -f "$SIDECAR_COMPOSE_FILE" up -d quota-dashboard
  else
    docker-compose --env-file "$ENV_FILE" -f "$MAIN_COMPOSE_FILE" -f "$SIDECAR_COMPOSE_FILE" up -d quota-dashboard
  fi
}

deploy_sidecar_only() {
  note "Deploy mode: sidecar only"
  if [ "$COMPOSE_CMD" = "docker compose" ]; then
    docker compose --env-file "$ENV_FILE" -f "$SIDECAR_COMPOSE_FILE" up -d
  else
    docker-compose --env-file "$ENV_FILE" -f "$SIDECAR_COMPOSE_FILE" up -d
  fi
}

print_steps() {
  note "Prerequisites:"
  note "1. sub2api must already be running"
  note "2. PostgreSQL must already be running"
  note "3. .env must be configured"
  note "4. the sidecar must be able to reach PostgreSQL and sub2api"
  note ""
  note "This script will:"
  note "1. check required commands"
  note "2. validate .env and compose config"
  note "3. start the quota dashboard service"
}

main() {
  COMPOSE_CMD=$(detect_compose)
  print_steps
  run_check

  if [ -f "$MAIN_COMPOSE_FILE" ]; then
    deploy_with_main_compose
  else
    deploy_sidecar_only
  fi

  note ""
  note "Done."
  note "Open:"
  note "http://your-host:${QUOTA_DASHBOARD_PORT:-18081}/?secret=${QUOTA_DASHBOARD_TOKEN:-}"
}

main "$@"
