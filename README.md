# Assembly infrastructure

Production deployment files for the Assembly frontend and backend.

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
bash scripts/deploy-service.sh api ghcr.io/assemblyuz/backend:latest
bash scripts/deploy-service.sh frontend ghcr.io/assemblyuz/frontend:latest
```
