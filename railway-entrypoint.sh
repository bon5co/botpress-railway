#!/bin/bash
# Railway wrapper entrypoint for Botpress. Starts as root to fix volume ownership, then runs the
# stock command (duckling and bp) as the botpress user.
set -eu

fail() { echo "railway-entrypoint: $1" >&2; exit 1; }

[ -n "${BOTPRESS_ADMIN_PASSWORD:-}" ] || fail "BOTPRESS_ADMIN_PASSWORD is empty; refusing to start with no administrator password"
[ "${#BOTPRESS_ADMIN_PASSWORD}" -ge 12 ] || fail "BOTPRESS_ADMIN_PASSWORD is shorter than 12 characters"
[ -n "${BOTPRESS_APP_SECRET:-}" ] || fail "BOTPRESS_APP_SECRET is empty; refusing to start with no signing secret"
[ "${#BOTPRESS_APP_SECRET}" -ge 32 ] || fail "BOTPRESS_APP_SECRET is shorter than 32 characters"

# Database: a full DATABASE_URL wins; otherwise build it from the postgres service's host and password.
if [ -z "${DATABASE_URL:-}" ]; then
  [ -n "${DB_HOST:-}" ] || fail "neither DATABASE_URL nor DB_HOST is set"
  [ -n "${DB_PASSWORD:-}" ] || fail "DB_PASSWORD is empty"
  export DATABASE_URL="postgres://${DB_USER:-botpress}:${DB_PASSWORD}@${DB_HOST}:5432/${DB_NAME:-botpress}"
  until (exec 3<>"/dev/tcp/${DB_HOST}/5432") 2>/dev/null; do
    echo "railway-entrypoint: waiting for the database"
    sleep 2
  done
fi

# Public URL comes from the Railway domain unless the deployer set a custom one.
if [ -z "${EXTERNAL_URL:-}" ]; then
  [ -n "${RAILWAY_PUBLIC_DOMAIN:-}" ] || fail "EXTERNAL_URL is unset and the service has no public domain"
  export EXTERNAL_URL="https://${RAILWAY_PUBLIC_DOMAIN}"
fi

# A fixed application secret keeps every issued token valid across redeploys.
export BP_CONFIG_APPSECRET="$BOTPRESS_APP_SECRET"

# Railway injects PORT and its healthcheck dials it; Botpress reads PORT itself. The bundled duckling
# also reads PORT and would take it first (Botpress then slides to 8081), so duckling is pinned to 8000.
LISTEN_PORT="${PORT:-3000}"
export PORT="$LISTEN_PORT"

# Railway mounts volumes owned by root; Botpress runs as botpress (uid 999).
mkdir -p "$BP_DATA_PATH"
chown -R botpress:botpress "$BP_DATA_PATH"

# Create the administrator at first boot. The first account registered on a fresh instance becomes
# the super administrator, and self sign-up is closed after it, so this runs the moment Botpress
# answers and does nothing on later boots.
bootstrap() {
  local email="$BOTPRESS_ADMIN_EMAIL" tries=0 out
  http() { # method path [body]
    local body="${3:-}"
    exec 3<>"/dev/tcp/127.0.0.1/${LISTEN_PORT}" || return 1
    printf '%s %s HTTP/1.0\r\nHost: localhost\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s' \
      "$1" "$2" "${#body}" "$body" >&3
    cat <&3
    exec 3<&-
  }
  while [ "$tries" -lt 600 ]; do
    tries=$((tries + 1))
    if out="$(http GET /api/v1/admin/auth/config 2>/dev/null)" && [[ "$out" == *'"isFirstUser"'* ]]; then
      if [[ "$out" == *'"isFirstUser":true'* ]]; then
        out="$(http POST /api/v1/auth/register/basic/default "{\"email\":\"${email}\",\"password\":\"${BOTPRESS_ADMIN_PASSWORD}\"}" 2>/dev/null || true)"
        if [[ "$out" == *'Registration successful'* ]]; then
          echo "railway-entrypoint: administrator ${email} created"
          return 0
        fi
        echo "railway-entrypoint: administrator registration failed, retrying"
      else
        echo "railway-entrypoint: administrator already exists"
        return 0
      fi
    fi
    sleep 1
  done
  echo "railway-entrypoint: gave up creating the administrator" >&2
}
bootstrap &

echo "railway-entrypoint: listen=${LISTEN_PORT} url=${EXTERNAL_URL} data-owner=$(stat -c %u:%g "$BP_DATA_PATH")"

export HOME=/home/botpress
cd /botpress
exec setpriv --reuid=botpress --regid=botpress --init-groups /bin/sh -c 'PORT=8000 ./duckling & ./bp'
