# Paperclip Stack

Self-host [Paperclip](https://github.com/paperclipai/paperclip) — the open-source
platform for orchestrating teams of AI agents as "companies" — with Docker Compose,
a dedicated PostgreSQL database, and an automated off-machine backup layer.

This repo is **self-contained**: it pulls the official Paperclip image, so you do
**not** need to clone the Paperclip source. One instance hosts many companies
(Paperclip isolates them internally), so this single stack covers your whole
portfolio.

---

## What you get

| Service | Role |
|---|---|
| **server** | The Paperclip app — control plane, agent runtime, and React dashboard — from the official `ghcr.io/paperclipai/paperclip` image. Dashboard at `http://localhost:3100`. |
| **db** | A dedicated PostgreSQL 17 container. Holds every company's org charts, tickets, audit logs, agent configs, budgets, and secrets. |
| **backup** | *(optional layer)* A small container that dumps the database, archives the data volume, and uploads to a dated Google Drive folder daily, pruning copies older than 30 days. |

The backup service is a convenience layer on top of a working Paperclip — you can
run Paperclip without ever configuring it, and add it when you're ready.

---

## Repository structure

```
paperclip-stack/
├── README.md                    # this file
├── .gitignore                   # keeps secrets and local artifacts out of git
├── .env.example                 # template for your real (git-ignored) .env
├── docker-compose.yml           # server + db + backup
├── install-rclone-catalina.sh   # host-side rclone installer (macOS 10.15 only)
└── backup/
    ├── Dockerfile               # Debian + postgresql-client-17 + rclone + supercronic
    ├── crontab                  # supercronic schedule (daily 03:30)
    ├── backup.sh                # dump + archive + upload + prune
    └── connect-gdrive.sh        # pointer to the host-side auth flow
```

The `backup/` folder is generic and reusable — drop it into another Compose
stack, adjust the env vars, and it works the same way.

---

## Prerequisites

- **Docker Desktop** running (the whole stack depends on it).
- *(Backup only)* a **Google account** and **rclone on the host** for the one-time
  Drive authorization. On macOS 10.15 (Catalina) use rclone **v1.70.3**
  (`install-rclone-catalina.sh`); newer builds won't run on Catalina. On macOS 11+
  or Linux, any current rclone is fine.

> **Where this runs best.** The durable home for an always-on deployment is a
> Linux host or a small cloud VM. On macOS, Docker Desktop — and therefore this
> stack and its backups — only runs while the user is logged in; agents and
> backups pause when the machine sleeps or that user logs out. It's fine on a Mac
> for development and personal use, and this Compose setup moves to Linux unchanged.

---

## Part 1 — Run Paperclip

### 1. Configure environment

```bash
cp .env.example .env
```

Edit `.env` and set:

- `BETTER_AUTH_SECRET` — `openssl rand -hex 32`
- `POSTGRES_PASSWORD` — `openssl rand -hex 16`
- a model provider key (e.g. `ANTHROPIC_API_KEY`)

Leave `PAPERCLIP_AUTH_DISABLE_SIGN_UP=false` for now (you'll flip it after creating
your admin in step 3). The real `.env` is git-ignored — **never commit it**.

### 2. Start the stack

```bash
docker compose up -d --build
```

This pulls the official Paperclip image and the Postgres image, and builds the
small local backup image. Watch it come up:

```bash
docker compose logs -f server
```

Wait until the server reports it's listening on `3100` and `db` is healthy
(`docker compose ps`). Ctrl+C just stops following the logs.

> Pin `PAPERCLIP_IMAGE` in `.env` to a specific release tag (instead of `:latest`)
> for predictable, repeatable deploys. Tags:
> https://github.com/paperclipai/paperclip/pkgs/container/paperclip

### 3. Create your first admin

Open `http://localhost:3100` and sign up — the first account to register becomes
the instance admin. (If your image instead shows a "no admin yet" message asking
for a CLI step, run `docker compose exec server pnpm paperclipai bootstrap-ceo`
and follow the printed link.)

### 4. Lock down sign-ups

Once your admin account exists and you can log in, prevent anyone else from
registering. In `.env` set:

```
PAPERCLIP_AUTH_DISABLE_SIGN_UP=true
```

Then recreate the server so it picks up the change:

```bash
docker compose up -d
```

> Environment changes only take effect when the container is recreated — editing
> `.env` alone does nothing to a running container. `docker compose up -d`
> recreates just the changed service; your database and data volumes are untouched.

### 5. Create your companies

In the dashboard, create one **company** per venture. Everything is
company-scoped — separate data, audit trail, and budget — so a single instance
cleanly runs your whole portfolio.

**At this point Paperclip is fully running.** The backup layer below is optional.

---

## Part 2 — Add the backup layer (optional)

The backup container is already running on its daily schedule, but it can't upload
until rclone is authorized for Google Drive. This is a one-time setup.

> **Why authorize on the host, not in the container?** rclone's Google login opens
> a local server on `127.0.0.1:53682`. Inside a container that loopback isn't
> reachable from your Mac's browser, so the in-container flow can't complete. We
> authorize on the host (browser and rclone co-located) and copy the credentials
> into the container's volume, where they persist for unattended runs.

### 6. Install rclone on the host

macOS 10.15 (Catalina) must use rclone **v1.70.3** — newer builds crash with
`dyld: Symbol not found` because their Go runtime requires macOS 11+. The included
script handles this without admin rights (installs to `~/bin`):

```bash
./install-rclone-catalina.sh
# macOS 11+ or Linux: use your package manager instead, e.g. `brew install rclone`
```

Confirm: `rclone version` prints a version, not a dyld error.

### 7. Create the `gdrive` remote on the host

```bash
rclone config
```

| Prompt | Answer |
|---|---|
| `name>` | `gdrive` |
| `Storage>` | `drive` |
| `client_id>` / `client_secret>` | *(press Enter — blank)* |
| `scope>` | `3`  (access to files rclone creates — safest) |
| `service_account_file>` | *(press Enter — blank)* |
| `Edit advanced config?` | `n` |
| `Use auto config?` | `y`  (host + browser are co-located, so this works) |
| *(browser opens — log in, click Allow)* | |
| `Configure this as a Shared Drive?` | `n` |
| `Keep this remote?` | `y` |
| final menu | `q` |

The remote **must** be named `gdrive` (the backup uses that name). This writes
`~/.config/rclone/rclone.conf`.

### 8. Copy the config into the backup container's volume

```bash
docker compose run --rm -v ~/.config/rclone:/host-rclone:ro backup \
  sh -c "mkdir -p /config/rclone && cp /host-rclone/rclone.conf /config/rclone/rclone.conf && echo copied"
```

Confirm the container sees the remote:

```bash
docker compose run --rm backup rclone listremotes      # expect: gdrive:
```

### 9. Run a backup to verify

```bash
docker compose run --rm backup backup-now
```

Check Google Drive for a dated folder (e.g. `2026-06-26`) under
`paperclip-backups/`, containing three files (see below). If it's there, the daily
03:30 job will do the same automatically.

---

## What gets backed up

Each daily run produces a dated folder (`YYYY-MM-DD`) with:

- `paperclip-db_*.sql.gz` — full Postgres dump (**all companies at once**).
- `paperclip-data_*.tar.gz` — the Paperclip data volume (agent workspaces,
  sessions, run logs).
- `env_*.backup` — a copy of `.env`. **Critical**: holds `BETTER_AUTH_SECRET`;
  without it a restore can't authenticate.

Because all companies share one database, a single dump captures the entire
portfolio with isolation intact.

---

## Restore

Onto a fresh stack:

1. Start just the database: `docker compose up -d db`
2. Restore it:
   ```bash
   gunzip -c paperclip-db_TIMESTAMP.sql.gz \
     | docker compose exec -T db psql -U paperclip paperclip
   ```
3. Restore the data archive into the `paperclip-data` volume (e.g. a helper
   container that untars the archive into `/data`).
4. Put the backed-up `.env` in place so `BETTER_AUTH_SECRET` matches.
5. Start the rest: `docker compose up -d`

> Test a restore at least once before relying on the backups. An untested backup
> is a hope, not a guarantee.

---

## Operations

```bash
docker compose ps                 # status of all services
docker compose logs -f server     # app logs
docker compose logs backup        # backup run history (success/failure)
docker compose run --rm backup backup-now    # manual backup
docker compose down               # stop (keeps volumes/data)
docker compose up -d --build      # apply changes / update image
```

To update Paperclip: bump `PAPERCLIP_IMAGE` in `.env` to a newer tag, then
`docker compose up -d`. Check Paperclip's release notes for any required DB
migrations. The named volumes preserve your data across updates.

---

## Troubleshooting

- **`unable to prepare context: path "./backup" not found`** — run `docker compose`
  from the folder containing `docker-compose.yml`, and make sure the `backup/`
  subfolder (with its four files) sits next to it.
- **`pg_dump: server version mismatch`** — the backup image's Postgres client must
  be **>=** the server version. This stack installs `postgresql-client-17` to match
  Postgres 17. If you upgrade the `db` image, bump the client version in
  `backup/Dockerfile` to match, then `docker compose build backup`.
- **`dyld: Symbol not found: _SecTrustCopyCertificateChain`** on the host — the
  binary is built for macOS 11+. On Catalina, pin to the last compatible version
  (rclone v1.70.3 via the included script). The same OS floor applies to other
  Go/native tools.
- **rclone auth never completes inside the container** — expected; use the
  host-side flow (Part 2). The in-container loopback can't reach the host browser.
- **Backups stop running** — confirm Docker Desktop is up and the owning user is
  logged in. On macOS the stack only runs during an active login session.

---

## Security notes

- The dashboard binds to `127.0.0.1` only. Don't change to `0.0.0.0` without an
  auth gate in front.
- Disable sign-ups (step 4) right after creating your admin.
- For remote access, prefer a private network (e.g. Tailscale) or a tunnel behind
  an access gate (e.g. Cloudflare Tunnel + Access) over exposing the port.
- Keep `.env`, `rclone.conf`, and `backups/` out of git — the included
  `.gitignore` handles this.
