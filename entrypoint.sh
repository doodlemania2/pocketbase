#!/usr/bin/env sh
set -e

# Default host and port (can be overridden with PB_HOST and PB_PORT environment variables)
HOST=${PB_HOST:-0.0.0.0}
PORT=${PB_PORT:-8090}

# Default serve command arguments
DEFAULT_SERVE_ARGS="serve --http=${HOST}:${PORT} --dir=/pb_data --publicDir=/pb_public --hooksDir=/pb_hooks"

LITESTREAM_PID=""
PB_PID=""
WATCHER_PID=""

# Single-writer handover across a rollout — see request_handover() for why.
SINGLE_WRITER_LOCK=/pb_data/.pb_singlewriter.lock
HANDOVER_FILE=/pb_data/.pb_handover
# How long an incoming replica waits for the outgoing one to let go. The normal
# wait is a poll interval plus a graceful drain, a few seconds; this only
# bounds the pathological case. Set PB_HANDOVER_TIMEOUT=0 to disable the whole
# mechanism.
HANDOVER_TIMEOUT=${PB_HANDOVER_TIMEOUT:-60}
HANDOVER_POLL=2
# Identifies this REPLICA to the other one. The container hostname is the pod
# name, which is stable across a container restart inside the same replica —
# that is deliberate, see start_handover_watcher.
INSTANCE_ID="${PB_INSTANCE_ID:-$(hostname 2>/dev/null || echo unknown)}"

# Graceful shutdown: drain PocketBase first so in-flight HTTP requests complete
# and SQLite WAL is checkpointed, THEN signal Litestream so it can replicate the
# final WAL frames to the blob replica before exiting. Without this, the
# ephemeral /pb_data is wiped on container restart and the last few seconds of
# writes are lost. The Container App must set terminationGracePeriodSeconds
# high enough (>= 60s) for this to actually run to completion.
shutdown() {
    echo "[entrypoint] received shutdown signal — stopping pocketbase + litestream..."
    if [ -n "$WATCHER_PID" ]; then
        kill -TERM "$WATCHER_PID" 2>/dev/null || true
    fi
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

# Hand /pb_data to an incoming replica WITHOUT exiting.
#
# Exiting here looks like a crash to Container Apps, which restarts the
# container; that restart then races the genuine incoming replica for the lock
# and can win it, leaving the incoming replica to time out and start unlocked.
# Observed live on 2026-09-06 22:49. So stop PocketBase, close both databases,
# drop the lock, and then sit still until ACA drains this replica. Health
# probes fail while parked, which is correct: traffic belongs to the incoming
# replica now.
handover_release() {
    echo "[entrypoint] handover: stopping pocketbase and releasing /pb_data..."
    if [ -n "$PB_PID" ]; then
        kill -TERM "$PB_PID" 2>/dev/null || true
        wait "$PB_PID" 2>/dev/null || true
        PB_PID=""
    fi
    if [ -n "$LITESTREAM_PID" ]; then
        kill -TERM "$LITESTREAM_PID" 2>/dev/null || true
        wait "$LITESTREAM_PID" 2>/dev/null || true
        LITESTREAM_PID=""
    fi
    # Closing fd 9 is what actually releases the single-writer lock.
    exec 9>&- 2>/dev/null || true
    echo "[entrypoint] /pb_data released. Parking until this replica is drained."
    # Never returns — returning would resume run_serve and exit the container,
    # which is the restart-and-steal behaviour this exists to avoid.
    while :; do
        sleep 3600 &
        wait $! 2>/dev/null || true
    done
}
trap handover_release USR1

# Serialize /pb_data across a rollout, by making the OUTGOING replica leave.
#
# Azure Container Apps rolls a revision transition: the incoming replica is
# started and made READY before the outgoing one is drained. Two PocketBase
# processes therefore write the same NFS /pb_data for ~40s, which is what
# corrupted auxiliary.db five times (#35). `maxReplicas: 1` does not prevent it
# — that bounds replicas per revision, not across a transition.
#
# The obvious fix does NOT work and must not be reintroduced: having the
# incoming replica block on an exclusive flock deadlocks, because readiness
# gates the handover in both directions. ACA will not drain the outgoing
# replica until the incoming one reports ready, and the incoming one cannot
# report ready while it is blocked on a lock the outgoing one holds. That
# shipped on 2026-09-06 (b7642f75) and was reverted the same day.
#
# So the dependency is inverted. The incoming replica *asks*, and the outgoing
# replica leaves of its own accord rather than waiting to be drained:
#
#   1. incoming writes its id to /pb_data/.pb_handover
#   2. the outgoing replica's watcher reads an id that is not its own, and
#      shuts itself down gracefully — closing both databases and releasing the
#      lock, without ACA having to drain it
#   3. incoming's flock returns, it clears the handover file and starts serving
#
# It FAILS OPEN. If the wait expires, the incoming replica starts anyway with a
# loud warning. That is deliberate: the deploy that introduces this ships
# against an outgoing replica with no watcher, which would otherwise never
# answer and would fail every rollout from then on. A brief overlap is
# recoverable; a container app that can no longer be deployed is not.
request_handover() {
    tmp="$HANDOVER_FILE.$$"
    if printf '%s\n' "$INSTANCE_ID" > "$tmp" 2>/dev/null && mv -f "$tmp" "$HANDOVER_FILE" 2>/dev/null; then
        return 0
    fi
    rm -f "$tmp" 2>/dev/null || true
    echo "[entrypoint] WARN: could not write $HANDOVER_FILE; the previous replica will not be asked to leave."
    return 0
}

# Poll for a handover request from a replica that is not us, and hand the main
# shell a TERM so it takes its normal graceful shutdown path.
start_handover_watcher() {
    (
        while :; do
            if [ -f "$HANDOVER_FILE" ]; then
                requester=$(cat "$HANDOVER_FILE" 2>/dev/null || true)
                # A request carrying our own id is this replica's container
                # restarting, not a new replica. Answering it would hand the
                # volume to ourselves and flap.
                if [ -n "$requester" ] && [ "$requester" != "$INSTANCE_ID" ]; then
                    echo "[entrypoint] handover requested by '$requester' — releasing /pb_data."
                    kill -USR1 "$MAIN_PID" 2>/dev/null || true
                    exit 0
                fi
            fi
            sleep "$HANDOVER_POLL"
        done
    ) &
    WATCHER_PID=$!
}

acquire_single_writer() {
    if [ "$HANDOVER_TIMEOUT" = "0" ]; then
        echo "[entrypoint] WARN: PB_HANDOVER_TIMEOUT=0 — single-writer handover disabled."
        echo "[entrypoint]       Two replicas sharing /pb_data will corrupt SQLite."
        return 0
    fi

    # PocketBase creates --dir itself, but that happens after this runs, and an
    # image started without a mounted volume has no /pb_data at all.
    if ! mkdir -p /pb_data 2>/dev/null; then
        echo "[entrypoint] WARN: cannot create /pb_data; skipping single-writer handover."
        return 0
    fi

    request_handover

    if ! command -v flock >/dev/null 2>&1; then
        echo "[entrypoint] WARN: flock not found — cannot confirm the previous replica let go."
        return 0
    fi

    if ! touch "$SINGLE_WRITER_LOCK" 2>/dev/null; then
        echo "[entrypoint] WARN: cannot create $SINGLE_WRITER_LOCK; skipping the lock wait."
        return 0
    fi

    # fd 9 stays open for the life of the shell, which is what holds the lock.
    # It is inherited by pocketbase and litestream, so the lock outlives even a
    # SIGKILL that skips the shutdown trap, and the kernel releases it once the
    # whole process tree is gone.
    exec 9>>"$SINGLE_WRITER_LOCK"

    echo "[entrypoint] waiting for the previous replica to release /pb_data (up to ${HANDOVER_TIMEOUT}s)..."
    if flock -x -w "$HANDOVER_TIMEOUT" 9; then
        echo "[entrypoint] /pb_data is ours — single writer confirmed."
    else
        echo "[entrypoint] WARN: no handover after ${HANDOVER_TIMEOUT}s. Starting anyway WITHOUT the lock."
        echo "[entrypoint]       Expected once, on the deploy that introduces this mechanism, because the"
        echo "[entrypoint]       outgoing replica predates it. If it repeats, two writers are sharing"
        echo "[entrypoint]       /pb_data and auxiliary.db will corrupt — see DEPLOY.md and #35."
    fi

    # Clear our own request before the watcher starts, or we would ask
    # ourselves to leave.
    rm -f "$HANDOVER_FILE" 2>/dev/null || true
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
    # The main shell's pid, for the watcher subshell to signal.
    MAIN_PID=$$

    # Before anything opens data.db or auxiliary.db — ahead of the Litestream
    # restore and the superuser bootstrap below.
    acquire_single_writer
    start_handover_watcher
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
    if [ -n "$WATCHER_PID" ]; then
        kill -TERM "$WATCHER_PID" 2>/dev/null || true
    fi
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
