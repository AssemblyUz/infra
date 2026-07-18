#!/usr/bin/env bash
set -euo pipefail

SERVICE="${1:?usage: deploy-service.sh <api|frontend> <image>}"
IMAGE="${2:?usage: deploy-service.sh <api|frontend> <image>}"

APP_DIR="${APP_DIR:-/opt/assembly}"
INFRA_DIR="${INFRA_DIR:-$APP_DIR/infra}"
ENV_FILE="${ENV_FILE:-$APP_DIR/.env}"
COMPOSE_FILE="$INFRA_DIR/docker-compose.prod.yml"

case "$SERVICE" in
  api|frontend) ;;
  *) echo "Unsupported service: $SERVICE" >&2; exit 2 ;;
esac

if [ ! -f "$ENV_FILE" ]; then
  echo "$ENV_FILE is missing. Create it from infra/.env.example before deploying." >&2
  exit 1
fi

if [ ! -f "$COMPOSE_FILE" ]; then
  echo "$COMPOSE_FILE is missing. Sync the infra repo to the server first." >&2
  exit 1
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
  local command="$2"
  for _ in $(seq 1 30); do
    if "${COMPOSE[@]}" exec -T "$service" sh -lc "$command" >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done
  "${COMPOSE[@]}" logs --tail=100 "$service"
  echo "$service did not become healthy in time." >&2
  return 1
}

if [ "$SERVICE" = "api" ]; then
  set_env_var BACKEND_IMAGE "$IMAGE"
else
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
  wait_for_service api 'python -c "import urllib.request; urllib.request.urlopen('\''http://127.0.0.1:8000/healthz/'\'', timeout=3).read()"'
else
  wait_for_service frontend 'node -e "fetch('\''http://127.0.0.1:3000/healthz'\'').then((r) => { if (!r.ok) process.exit(1); }).catch(() => process.exit(1))"'
fi

"${COMPOSE[@]}" ps
