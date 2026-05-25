#!/usr/bin/env sh
set -e

# Default host and port (can be overridden with PB_HOST and PB_PORT environment variables)
HOST=${PB_HOST:-0.0.0.0}
PORT=${PB_PORT:-8090}

# Default serve command arguments
DEFAULT_SERVE_ARGS="serve --http=${HOST}:${PORT} --dir=/pb_data --publicDir=/pb_public --hooksDir=/pb_hooks"

LITESTREAM_PID=""
PB_PID=""

# Graceful shutdown: drain PocketBase first so in-flight HTTP requests complete
# and SQLite WAL is checkpointed, THEN signal Litestream so it can replicate the
# final WAL frames to the blob replica before exiting. Without this, the
# ephemeral /pb_data is wiped on container restart and the last few seconds of
# writes are lost. The Container App must set terminationGracePeriodSeconds
# high enough (>= 60s) for this to actually run to completion.
shutdown() {
    echo "[entrypoint] received shutdown signal — stopping pocketbase + litestream..."
    if [ -n "$PB_PID" ]; then
        kill -TERM "$PB_PID" 2>/dev/null || true
        wait "$PB_PID" 2>/dev/null || true
    fi
    if [ -n "$LITESTREAM_PID" ]; then
        kill -TERM "$LITESTREAM_PID" 2>/dev/null || true
        wait "$LITESTREAM_PID" 2>/dev/null || true
    fi
    echo "[entrypoint] shutdown complete."
    exit 0
}
trap shutdown TERM INT

litestream_restore() {
    if [ -n "$LITESTREAM_REPLICA_URL" ] && [ ! -f /pb_data/data.db ]; then
        echo "[entrypoint] no database found — attempting Litestream restore..."
        litestream restore -if-replica-exists -config /etc/litestream.yml /pb_data/data.db || true
        litestream restore -if-replica-exists -config /etc/litestream.yml /pb_data/auxiliary.db || true
    fi
}

litestream_replicate() {
    if [ -n "$LITESTREAM_REPLICA_URL" ]; then
        echo "[entrypoint] starting Litestream replication..."
        litestream replicate -config /etc/litestream.yml &
        LITESTREAM_PID=$!
    fi
}

# Bootstrap superuser on first boot. Uses `create` so an admin-set password is
# preserved across restarts (subsequent boots see "already exists" and no-op).
# Skips on empty/invalid email so a misconfigured secret can't spam SQLite opens
# on every restart.
create_superuser() {
    if [ -z "$PB_ADMIN_EMAIL" ] || [ -z "$PB_ADMIN_PASSWORD" ]; then
        return 0
    fi
    case "$PB_ADMIN_EMAIL" in
        *@*.*) ;;
        *)
            echo "[entrypoint] WARN: PB_ADMIN_EMAIL ('$PB_ADMIN_EMAIL') is not a valid email; skipping superuser bootstrap."
            echo "[entrypoint]       Fix with: azd env set PB_ADMIN_EMAIL <admin@example.com> && azd up"
            return 0
            ;;
    esac
    out=$(/usr/local/bin/pocketbase superuser create "$PB_ADMIN_EMAIL" "$PB_ADMIN_PASSWORD" --dir=/pb_data 2>&1) || true
    case "$out" in
        ""|*"already exists"*|*"UNIQUE constraint"*|*"Successfully"*) ;;
        *) echo "[entrypoint] superuser create: $out" ;;
    esac
}

run_serve() {
    litestream_restore
    litestream_replicate
    # Brief pause so Litestream can read the restored db, match it against the
    # replica, and adopt the existing generation BEFORE PocketBase opens
    # /pb_data/data.db. Without this, the first SQLite write from `superuser
    # create` or `serve` startup can race the initial Litestream sync and look
    # like the start of a new generation in the replica.
    if [ -n "$LITESTREAM_PID" ]; then
        sleep 2
    fi
    create_superuser
    # shellcheck disable=SC2086
    /usr/local/bin/pocketbase $DEFAULT_SERVE_ARGS "$@" &
    PB_PID=$!
    # `wait` is interruptible — when SIGTERM arrives the shell jumps to the
    # `shutdown` trap, which kills both children in order and exits.
    set +e
    wait "$PB_PID"
    rc=$?
    set -e
    if [ -n "$LITESTREAM_PID" ]; then
        kill -TERM "$LITESTREAM_PID" 2>/dev/null || true
        wait "$LITESTREAM_PID" 2>/dev/null || true
    fi
    exit "$rc"
}

# Default invocation (no args): supervised serve with Litestream restore + replicate.
if [ $# -eq 0 ]; then
    run_serve
fi

# Global flags pass through directly to pocketbase.
case "$1" in
    --help|-h|--version|-v)
        exec /usr/local/bin/pocketbase "$@"
        ;;
esac

# First arg starts with '-' = serve flags (run supervised).
if [ "${1#-}" != "$1" ]; then
    run_serve "$@"
fi

# Otherwise: subcommand passthrough (migrate, superuser, …) — no Litestream
# supervision, no graceful trap, because these are short-lived admin commands.
exec /usr/local/bin/pocketbase "$@"
