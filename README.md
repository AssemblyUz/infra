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
- `/opt/assembly/.env` - production configuration and secrets.
- Docker named volumes store Postgres, Caddy certificates, and media files.

## First server setup

```bash
sudo APP_DIR=/opt/assembly SSH_USER=ubuntu bash scripts/bootstrap-server.sh
cp .env.example /opt/assembly/.env
chmod 600 /opt/assembly/.env
```

Fill `/opt/assembly/.env` with the real domain, Django secret key, Postgres
password, and email settings before running a deploy.

## Manual deploy from the server

```bash
bash scripts/deploy-service.sh api "$(cat deploy/backend/image.txt)"
bash scripts/deploy-service.sh frontend "$(cat deploy/frontend/image.txt)"
```

## Required infra secrets

- `VPS_HOST`
- `VPS_PORT`
- `VPS_USER`
- `VPS_SSH_KEY`
