#!/usr/bin/env bash
set -euo pipefail

SERVICE="${1:?usage: deploy-service.sh <api|frontend> <image>}"
IMAGE="${2:?usage: deploy-service.sh <api|frontend> <image>}"

APP_DIR="${APP_DIR:-/opt/assembly}"
INFRA_DIR="${INFRA_DIR:-$APP_DIR/infra}"
ENV_FILE="${ENV_FILE:-$INFRA_DIR/.env}"
LEGACY_ENV_FILE="$APP_DIR/.env"
COMPOSE_FILE="${COMPOSE_FILE:-$INFRA_DIR/compose.yaml}"

case "$SERVICE" in
  api|frontend) ;;
  *) echo "Unsupported service: $SERVICE" >&2; exit 2 ;;
esac

if [ ! -f "$COMPOSE_FILE" ]; then
  COMPOSE_FILE="$INFRA_DIR/docker-compose.prod.yml"
  if [ ! -f "$COMPOSE_FILE" ]; then
    echo "$COMPOSE_FILE is missing. Sync the infra repo to the server first." >&2
    exit 1
  fi
fi

LOCK_DIR="$APP_DIR/.deploy.lock"
LOCKED=0
for _ in $(seq 1 60); do
  if mkdir "$LOCK_DIR" 2>/dev/null; then
    LOCKED=1
    trap 'rmdir "$LOCK_DIR"' EXIT
    break
  fi
  sleep 2
done

if [ "$LOCKED" -ne 1 ]; then
  echo "Timed out waiting for another deployment to finish." >&2
  exit 1
fi

if docker info >/dev/null 2>&1; then
  DOCKER=(docker)
elif sudo -n docker info >/dev/null 2>&1; then
  DOCKER=(sudo docker)
else
  echo "Docker is not available to this user. Run scripts/bootstrap-server.sh first." >&2
  exit 1
fi

COMPOSE=("${DOCKER[@]}" compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE")

set_env_var() {
  local key="$1"
  local value="$2"
  local tmp
  tmp="$(mktemp)"
  if [ -f "$ENV_FILE" ]; then
    grep -v "^${key}=" "$ENV_FILE" > "$tmp" || true
  fi
  printf '%s=%s\n' "$key" "$value" >> "$tmp"
  chmod 600 "$tmp"
  mv "$tmp" "$ENV_FILE"
}

ensure_env_file() {
  mkdir -p "$INFRA_DIR" "$APP_DIR/data/postgres" "$APP_DIR/data/media" "$APP_DIR/data/caddy/data" "$APP_DIR/data/caddy/config"

  if [ ! -f "$ENV_FILE" ]; then
    if [ -f "$LEGACY_ENV_FILE" ] && [ ! -L "$LEGACY_ENV_FILE" ]; then
      mv "$LEGACY_ENV_FILE" "$ENV_FILE"
    elif [ -f "$INFRA_DIR/.env.example" ]; then
      cp "$INFRA_DIR/.env.example" "$ENV_FILE"
    else
      echo "$ENV_FILE is missing and $INFRA_DIR/.env.example is unavailable." >&2
      exit 1
    fi
    chmod 600 "$ENV_FILE"
  fi

  ln -sfn "$ENV_FILE" "$LEGACY_ENV_FILE"

  set_env_var APP_ENV_FILE "$ENV_FILE"

  if ! grep -q '^APP_DATA_DIR=' "$ENV_FILE"; then
    set_env_var APP_DATA_DIR "$APP_DIR/data"
  fi

  if ! grep -q '^SECRET_KEY=' "$ENV_FILE" || grep -q '^SECRET_KEY=replace-me' "$ENV_FILE"; then
    set_env_var SECRET_KEY "$(openssl rand -base64 48 | tr -d '\n')"
  fi

  if ! grep -q '^POSTGRES_PASSWORD=' "$ENV_FILE" || grep -q '^POSTGRES_PASSWORD=replace-me' "$ENV_FILE"; then
    local generated_password
    generated_password="$(openssl rand -hex 24)"
    set_env_var POSTGRES_PASSWORD "$generated_password"
    set_env_var DATABASE_URL "postgres://${POSTGRES_USER:-assembly}:$generated_password@db:5432/${POSTGRES_DB:-assembly}"
  fi
}

wait_for_db() {
  for _ in $(seq 1 30); do
    if "${COMPOSE[@]}" exec -T db pg_isready -U "${POSTGRES_USER:-assembly}" -d "${POSTGRES_DB:-assembly}" >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done
  "${COMPOSE[@]}" logs --tail=80 db
  echo "Database did not become ready in time." >&2
  return 1
}

wait_for_service() {
  local service="$1"
  local container_id
  local health
  for _ in $(seq 1 30); do
    container_id="$("${COMPOSE[@]}" ps -q "$service" 2>/dev/null || true)"
    if [ -n "$container_id" ]; then
      health="$("${DOCKER[@]}" inspect --format '{{ if .State.Health }}{{ .State.Health.Status }}{{ else }}{{ .State.Status }}{{ end }}' "$container_id" 2>/dev/null || true)"
      if [ "$health" = "healthy" ] || [ "$health" = "running" ]; then
        return 0
      fi
    fi
    sleep 2
  done
  "${COMPOSE[@]}" logs --tail=100 "$service"
  echo "$service did not become healthy in time." >&2
  return 1
}

if [ "$SERVICE" = "api" ]; then
  ensure_env_file
  set_env_var BACKEND_IMAGE "$IMAGE"
else
  ensure_env_file
  set_env_var FRONTEND_IMAGE "$IMAGE"
fi

set -a
. "$ENV_FILE"
set +a

"${COMPOSE[@]}" pull db caddy "$SERVICE"
"${COMPOSE[@]}" up -d db
wait_for_db

if [ "$SERVICE" = "api" ]; then
  "${COMPOSE[@]}" run --rm api python manage.py migrate --noinput
fi

"${COMPOSE[@]}" up -d "$SERVICE"
"${COMPOSE[@]}" up -d --no-deps caddy

if [ "$SERVICE" = "api" ]; then
  wait_for_service api
else
  wait_for_service frontend
fi

"${COMPOSE[@]}" ps
