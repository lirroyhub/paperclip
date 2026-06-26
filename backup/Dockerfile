FROM debian:bookworm-slim

# --- Install backup tooling -------------------------------------------------
# postgresql-client-17 : pg_dump matching the Postgres 17 server (version must
#                        be >= server; Debian's default client is 15, too old).
#                        Installed from the official PGDG apt repository.
# rclone          : upload to Google Drive (runs in Linux, so no macOS dyld wall)
# ca-certificates : TLS for rclone -> Google and for the PGDG repo
# tzdata          : so the cron schedule respects your timezone
# curl, gnupg     : fetch supercronic and the PGDG signing key (curl removed after)
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        tzdata \
        curl \
        gnupg \
        rclone \
    && install -d /usr/share/postgresql-common/pgdg \
    && curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc \
         -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc \
    && echo "deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] https://apt.postgresql.org/pub/repos/apt bookworm-pgdg main" \
         > /etc/apt/sources.list.d/pgdg.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends postgresql-client-17 \
    && rm -rf /var/lib/apt/lists/*

# --- Install supercronic (container-native cron) ----------------------------
# amd64 build, because Catalina/Intel host is x86_64.
# Version pinned and SHA1 verified so a tampered/truncated download fails the
# build instead of silently shipping.
ENV SUPERCRONIC_URL=https://github.com/aptible/supercronic/releases/download/v0.2.29/supercronic-linux-amd64 \
    SUPERCRONIC=supercronic-linux-amd64 \
    SUPERCRONIC_SHA1SUM=cd48d45c4b10f3f0bfdd3a57d054cd05ac96812b

RUN curl -fsSLO "$SUPERCRONIC_URL" \
    && echo "${SUPERCRONIC_SHA1SUM}  ${SUPERCRONIC}" | sha1sum -c - \
    && chmod +x "$SUPERCRONIC" \
    && mv "$SUPERCRONIC" "/usr/local/bin/${SUPERCRONIC}" \
    && ln -s "/usr/local/bin/${SUPERCRONIC}" /usr/local/bin/supercronic \
    && apt-get purge -y curl gnupg && apt-get autoremove -y

# --- App files --------------------------------------------------------------
COPY crontab /app/crontab
COPY backup.sh /usr/local/bin/backup.sh
COPY connect-gdrive.sh /usr/local/bin/connect-gdrive
RUN chmod +x /usr/local/bin/backup.sh /usr/local/bin/connect-gdrive \
    # Friendly alias so `docker compose run --rm backup backup-now` works.
    && ln -s /usr/local/bin/backup.sh /usr/local/bin/backup-now

WORKDIR /app

# supercronic must be PID 1 so it handles SIGTERM/SIGINT gracefully.
# It inherits all container env vars and logs job output to stdout/stderr,
# which surface via `docker compose logs backup`.
CMD ["supercronic", "/app/crontab"]
