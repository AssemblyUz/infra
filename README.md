# Assembly infrastructure

Production deployment files for the Assembly frontend and backend.

## GitOps flow

- `deploy/backend/image.txt` is the desired backend image.
- `deploy/frontend/image.txt` is the desired frontend image.
- Backend and frontend repos build immutable GHCR images tagged by commit SHA.
- After a successful image push, each app repo commits only its own image file
  in this repo.
- Infra workflows deploy from those image-file changes:
  - `Deploy backend` runs when `deploy/backend/image.txt` changes.
  - `Deploy frontend` runs when `deploy/frontend/image.txt` changes.

Backend and frontend repos need only `INFRA_WRITE_TOKEN` to update this repo.
The production VPS secrets stay in this infra repo.

## Server layout

- `/opt/assembly/infra` - this repository copied by GitHub Actions.
- `/opt/assembly/infra/.env` - production configuration and secrets.
- `/opt/assembly/.env` - compatibility symlink to `/opt/assembly/infra/.env`.
- `/opt/assembly/data` - Postgres data, media files, and Caddy certificates/config.

## First server setup

```bash
sudo APP_DIR=/opt/assembly SSH_USER=ubuntu bash scripts/bootstrap-server.sh
bash scripts/deploy-service.sh api "$(cat deploy/backend/image.txt)"
bash scripts/deploy-service.sh frontend "$(cat deploy/frontend/image.txt)"
```

The deploy script creates `/opt/assembly/infra/.env` from `.env.example` when
it is missing, generates `SECRET_KEY` and `POSTGRES_PASSWORD`, and keeps
`/opt/assembly/.env` as a compatibility symlink. Edit email settings manually
if SMTP is required.

If you move Django admin from `/admin/`, update both `ADMIN_URL` for Django
and `ADMIN_PREFIX` for Caddy. For example, `ADMIN_URL=panel-7fa2/` pairs with
`ADMIN_PREFIX=/panel-7fa2`.

## Manual deploy from the server

```bash
cd /opt/assembly/infra
bash scripts/deploy-service.sh api "$(cat deploy/backend/image.txt)"
bash scripts/deploy-service.sh frontend "$(cat deploy/frontend/image.txt)"
```

Use `docker compose ps`, `docker compose logs`, and `docker compose up -d` from
`/opt/assembly/infra`. Do not run `docker compose down -v` in production unless
you are intentionally deleting persistent data. Current Compose bind-mounts
state under `/opt/assembly/data`, so certificates and database files are not
Docker named volumes.

## Required infra secrets

- `VPS_HOST`
- `VPS_PORT`
- `VPS_USER`
- `VPS_SSH_KEY`

Optional, but useful while GHCR packages are private or still settling:

- `GHCR_USERNAME`
- `GHCR_READ_TOKEN`
