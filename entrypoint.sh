#!/usr/bin/env sh
set -e

# Default host and port (can be overridden with PB_HOST and PB_PORT environment variables)
HOST=${PB_HOST:-0.0.0.0}
PORT=${PB_PORT:-8090}

# Default serve command arguments
DEFAULT_SERVE_ARGS="serve --http=${HOST}:${PORT} --dir=/pb_data --publicDir=/pb_public --hooksDir=/pb_hooks"

LITESTREAM_PID=""
PB_PID=""

# Single-writer lock file and how long an incoming replica waits for it.
# Set PB_SINGLE_WRITER_TIMEOUT=0 to disable the lock entirely (see
# acquire_single_writer_lock for why you almost certainly should not).
SINGLE_WRITER_LOCK=/pb_data/.pb_singlewriter.lock
SINGLE_WRITER_TIMEOUT=${PB_SINGLE_WRITER_TIMEOUT:-75}

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

# Hold /pb_data against a second SQLite writer for the life of this process.
#
# Azure Container Apps performs a ROLLING revision transition: the incoming
# replica is started and made ready BEFORE the outgoing one is drained. For
# ~40s two PocketBase processes therefore hold the same NFS /pb_data, which is
# exactly the case SQLite does not survive. `maxReplicas: 1` does not prevent
# it — that bounds replicas per revision, not across a rollout. The overlap is
# directly observable in ContainerAppConsoleLogs_CL, where two RevisionName_s
# values emit request logs in the same second, and it corrupted auxiliary.db on
# 2026-06-09, 2026-08-15, 2026-08-31 and 2026-09-05 (issue #35).
#
# /pb_data is deliberately NFS rather than SMB because NFS carries the POSIX
# locks SQLite's WAL needs, so take one: an exclusive flock held on fd 9 for
# the life of the shell. fd 9 is inherited by pocketbase and litestream, so the
# lock outlives even a SIGKILL that skips the shutdown trap, and is released by
# the kernel once the whole process tree is gone.
#
# Timing out is the safe outcome, not the bad one: the rollout fails loudly and
# the previous revision keeps serving, which beats corrupting the volume. The
# default wait covers the worst case, terminationGracePeriodSeconds (60s), and
# still leaves the startup probe (95s) room to see a listening port.
acquire_single_writer_lock() {
    if [ "$SINGLE_WRITER_TIMEOUT" = "0" ]; then
        echo "[entrypoint] WARN: PB_SINGLE_WRITER_TIMEOUT=0 — single-writer lock disabled."
        echo "[entrypoint]       Two replicas sharing /pb_data will corrupt SQLite."
        return 0
    fi

    if ! command -v flock >/dev/null 2>&1; then
        echo "[entrypoint] FATAL: flock not found — cannot guarantee a single SQLite writer."
        echo "[entrypoint]        Install util-linux flock in the image, or set"
        echo "[entrypoint]        PB_SINGLE_WRITER_TIMEOUT=0 to start anyway and risk corruption."
        exit 1
    fi

    # PocketBase creates --dir itself, but that happens after this runs, and an
    # image started without a mounted volume has no /pb_data at all.
    if ! mkdir -p /pb_data 2>/dev/null; then
        echo "[entrypoint] FATAL: cannot create /pb_data."
        exit 1
    fi

    # Create the lock file first so an unwritable volume is a clear message
    # rather than a bare `exec` redirection failure, which in a non-interactive
    # shell kills the shell before anything can be printed.
    if ! touch "$SINGLE_WRITER_LOCK" 2>/dev/null; then
        echo "[entrypoint] FATAL: cannot create $SINGLE_WRITER_LOCK — is /pb_data writable?"
        exit 1
    fi

    # Append rather than truncate: another replica may be holding this very file.
    exec 9>>"$SINGLE_WRITER_LOCK"

    echo "[entrypoint] acquiring single-writer lock on /pb_data (waiting up to ${SINGLE_WRITER_TIMEOUT}s)..."
    if flock -x -w "$SINGLE_WRITER_TIMEOUT" 9; then
        echo "[entrypoint] single-writer lock acquired."
        return 0
    fi

    echo "[entrypoint] FATAL: another replica still holds /pb_data after ${SINGLE_WRITER_TIMEOUT}s."
    echo "[entrypoint]        Refusing to start a second SQLite writer; the previous revision keeps serving."
    exit 1
}

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
    # Before anything opens data.db or auxiliary.db — including the Litestream
    # restore and the superuser bootstrap below.
    acquire_single_writer_lock
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
