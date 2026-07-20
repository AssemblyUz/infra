#!/usr/bin/env bash
set -euo pipefail

if [ "$(id -u)" -eq 0 ]; then
  SUDO=()
else
  SUDO=(sudo)
fi

APP_DIR="${APP_DIR:-/opt/assembly}"
SSH_USER="${SSH_USER:-ubuntu}"
SWAP_FILE="${SWAP_FILE:-/swapfile}"
SWAP_SIZE="${SWAP_SIZE:-2G}"

export DEBIAN_FRONTEND=noninteractive

"${SUDO[@]}" apt-get update
"${SUDO[@]}" apt-get install -y ca-certificates curl gnupg openssl ufw

if [ ! -f /etc/apt/sources.list.d/docker.list ]; then
  "${SUDO[@]}" install -m 0755 -d /etc/apt/keyrings
  "${SUDO[@]}" rm -f /etc/apt/keyrings/docker.gpg
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | "${SUDO[@]}" gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  "${SUDO[@]}" chmod a+r /etc/apt/keyrings/docker.gpg

  . /etc/os-release
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" \
    | "${SUDO[@]}" tee /etc/apt/sources.list.d/docker.list >/dev/null

  "${SUDO[@]}" apt-get update
fi

"${SUDO[@]}" apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
"${SUDO[@]}" usermod -aG docker "$SSH_USER"

"${SUDO[@]}" mkdir -p \
  "$APP_DIR/infra" \
  "$APP_DIR/data/postgres" \
  "$APP_DIR/data/media" \
  "$APP_DIR/data/caddy/data" \
  "$APP_DIR/data/caddy/config"
"${SUDO[@]}" chown -R "$SSH_USER:$SSH_USER" \
  "$APP_DIR/infra" \
  "$APP_DIR/data/media" \
  "$APP_DIR/data/caddy"

if [ -z "$("${SUDO[@]}" find "$APP_DIR/data/postgres" -mindepth 1 -maxdepth 1 -print -quit)" ]; then
  "${SUDO[@]}" chown 70:70 "$APP_DIR/data/postgres"
fi

if ! "${SUDO[@]}" swapon --show | grep -q "$SWAP_FILE"; then
  if [ ! -f "$SWAP_FILE" ]; then
    if ! "${SUDO[@]}" fallocate -l "$SWAP_SIZE" "$SWAP_FILE"; then
      "${SUDO[@]}" dd if=/dev/zero of="$SWAP_FILE" bs=1M count=2048 status=progress
    fi
    "${SUDO[@]}" chmod 600 "$SWAP_FILE"
    "${SUDO[@]}" mkswap "$SWAP_FILE"
  fi
  "${SUDO[@]}" swapon "$SWAP_FILE"
fi

if ! grep -q "^${SWAP_FILE} " /etc/fstab; then
  echo "${SWAP_FILE} none swap sw 0 0" | "${SUDO[@]}" tee -a /etc/fstab >/dev/null
fi

"${SUDO[@]}" ufw allow OpenSSH
"${SUDO[@]}" ufw allow 80/tcp
"${SUDO[@]}" ufw allow 443/tcp
"${SUDO[@]}" ufw --force enable

echo "Bootstrap complete. Reconnect SSH if docker group membership was just added."
