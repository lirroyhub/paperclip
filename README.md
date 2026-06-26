# Paperclip Stack

A self-hosted [Paperclip](https://github.com/paperclipai/paperclip) deployment via
Docker Compose, with a dedicated Postgres database and an automated daily backup
service that pushes to Google Drive.

One Paperclip instance hosts many companies (Paperclip isolates them internally),
so this single stack covers your whole portfolio.

---

## What's in the stack

Three services, one Compose file:

- **server** — the Paperclip app (the official `ghcr.io/paperclipai/paperclip`
  image: control plane, agent runtime, and React dashboard), reachable at
  `http://localhost:3100`. No Paperclip source checkout required — Docker pulls
  the prebuilt image.
- **db** — a dedicated PostgreSQL 17 container with a named volume. Holds every
  company's org charts, tickets, audit logs, agent configs, and budgets.
- **backup** — a small container running [supercronic](https://github.com/aptible/supercronic)
  that dumps the database, archives the data volume, and uploads everything to a
  dated Google Drive folder once a day, pruning copies older than 30 days.

---

## Repository structure

```
paperclip-stack/
├── README.md            # this file
├── .gitignore           # keeps secrets and local artifacts out of git
├── .env.example         # template for your real (git-ignored) .env
├── docker-compose.yml   # server + db + backup
└── backup/
    ├── Dockerfile       # Debian + postgres-client + rclone + supercronic
    ├── crontab          # supercronic schedule (daily 03:30)
    └── backup.sh        # dump + archive + upload + prune
```

The `backup/` folder is generic and reusable — drop it into another stack,
adjust the env vars, and it works the same way.

---

## Prerequisites

- Docker Desktop running (the whole stack depends on it).
- A Google account for backup storage.

> **Note:** the canonical home for an always-on deployment is a Linux host or a
> small cloud VM. On macOS, Docker Desktop — and therefore this stack — only runs
> while the user is logged in. It works fine on a Mac for development and personal
> use; just be aware backups and agents pause when the machine is asleep or logged
> out. This Compose setup moves to Linux unchanged.

---

## Setup

### 1. Configure environment

```bash
cp .env.example .env
```

Edit `.env` and set real values:

- `BETTER_AUTH_SECRET` — `openssl rand -hex 32`
- `POSTGRES_PASSWORD` — `openssl rand -hex 16`
- your model provider key (e.g. `ANTHROPIC_API_KEY`)

The real `.env` is git-ignored. **Never commit it** — it holds your auth secret
and API keys.

### 2. Build and start

```bash
docker compose up -d --build
```

This pulls the official Paperclip image and builds only the small local backup
image. Follow startup with:

```bash
docker compose logs -f server
```

> This repo is **self-contained** — it pulls the prebuilt Paperclip image from
> the registry, so you do **not** need to clone the Paperclip source. Pin
> `PAPERCLIP_IMAGE` in `.env` to a specific release tag for production stability.

### 3. Create the first board/CEO account

```bash
docker compose exec server pnpm paperclipai auth bootstrap-ceo
```

Open the printed link at `http://localhost:3100`, complete setup, then create a
company per venture inside the dashboard.

### 4. Authorize backups (one-time)

The backup container needs to authorize Google Drive once. rclone stores the
token in a named volume afterward, so scheduled runs are unattended.

```bash
docker compose run --rm backup rclone config
```

Create a remote named `gdrive` (Google Drive). On a headless setup, choose the
no-auto-config option and follow rclone's instructions to authorize on a machine
with a browser, then paste the token back.

> The backup service sets `RCLONE_CONFIG=/config/rclone/rclone.conf` so rclone
> finds its credentials in the mounted volume.

### 5. Verify a backup end-to-end

```bash
docker compose run --rm backup /usr/local/bin/backup.sh
```

Confirm a dated folder appears in Google Drive under `paperclip-backups/`.

---

## What gets backed up

Each daily run produces a dated folder (`YYYY-MM-DD`) containing:

- `paperclip-db_*.sql.gz` — full Postgres dump (all companies at once).
- `paperclip-data_*.tar.gz` — the Paperclip data volume.
- `env_*.backup` — a copy of `.env`. **Critical**: holds `BETTER_AUTH_SECRET`;
  without it a restore can't authenticate.

Because all companies share one database, a single dump captures the entire
portfolio with isolation intact.

---

## Restore

To restore onto a fresh stack:

1. Bring up `db` only: `docker compose up -d db`
2. Restore the database:
   ```bash
   gunzip -c paperclip-db_TIMESTAMP.sql.gz \
     | docker compose exec -T db psql -U paperclip paperclip
   ```
3. Restore the data volume contents into the `paperclip-data` volume (e.g. via a
   helper container that untars the archive into `/data`).
4. Put the backed-up `.env` in place (so `BETTER_AUTH_SECRET` matches).
5. Start the rest: `docker compose up -d`

> Test a restore at least once before you rely on the backups. An untested backup
> is a hope, not a guarantee.

---

## Operations

```bash
docker compose ps                 # status
docker compose logs -f server     # app logs
docker compose logs backup        # backup run history (success/failure)
docker compose down               # stop (keeps volumes/data)
docker compose up -d --build      # update after pulling a new Paperclip version
```

---

## Security notes

- The dashboard is bound to `127.0.0.1` only. Don't change this to `0.0.0.0`
  without an auth gate in front.
- For remote access, prefer a private path (e.g. Tailscale) or a tunnel behind an
  access gate (e.g. Cloudflare Tunnel + Access) rather than exposing the port.
- Keep `.env`, `rclone.conf`, and the `backups/` directory out of git (the
  provided `.gitignore` handles this).
