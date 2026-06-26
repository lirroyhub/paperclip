#!/usr/bin/env bash
#
# connect-gdrive — DEPRECATED in-container path.
#
# Authorizing rclone from inside the container does not work on macOS hosts:
# rclone's auth opens a server on 127.0.0.1:53682 that the host browser cannot
# reach across the container boundary. Use the HOST-SIDE flow instead.
#
# Correct steps (see README section 4):
#   1. On the host, install rclone (Catalina: v1.70.3 via install-rclone-catalina.sh).
#   2. On the host:   rclone config      (name the remote: gdrive)
#   3. Copy the host config into this container's volume:
#        docker compose run --rm -v ~/.config/rclone:/host-rclone:ro backup \
#          sh -c "mkdir -p /config/rclone && cp /host-rclone/rclone.conf /config/rclone/rclone.conf && echo copied"
#   4. Verify:        docker compose run --rm backup rclone listremotes
#   5. Test backup:   docker compose run --rm backup backup-now

cat <<'MSG'
────────────────────────────────────────────────────────────
  connect-gdrive is deprecated — use the host-side flow.
  In-container rclone auth can't reach the host browser
  (127.0.0.1:53682 is not crossable from inside the container).

  Do this instead (details in README section 4):
    1. Host: ./install-rclone-catalina.sh   (Catalina needs rclone v1.70.3)
    2. Host: rclone config                   (name the remote: gdrive)
    3. Copy config in:
         docker compose run --rm -v ~/.config/rclone:/host-rclone:ro backup \
           sh -c "mkdir -p /config/rclone && cp /host-rclone/rclone.conf /config/rclone/rclone.conf && echo copied"
    4. Verify:  docker compose run --rm backup rclone listremotes
    5. Test:    docker compose run --rm backup backup-now
────────────────────────────────────────────────────────────
MSG
