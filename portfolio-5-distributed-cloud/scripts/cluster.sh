#!/usr/bin/env bash
# =====================================================================
# StitchLine — local distributed PostgreSQL cluster (Portfolio 5)
#
#   ./cluster.sh up       build and start everything (copies the stitchline DB)
#   ./cluster.sh status   show which servers are running and replication state
#   ./cluster.sh down     stop every server
#   ./cluster.sh reset    stop and delete everything
#
# Topology (all on one machine, each server has its own data directory and port)
#   5440  primary    read/write, the stitchline database
#   5441  replica1   streaming replica of the primary (hot standby, read-only)
#   5442  replica2   streaming replica of the primary (hot standby, read-only)
#   5450  shard1     independent server holding half of the sharded orders
#   5451  shard2     independent server holding the other half
#
# Needs PostgreSQL 14+ server binaries (initdb, pg_ctl, pg_basebackup).
# Linux / macOS / WSL. Run as a normal (non-root) user.
# The SOURCE database is read with the standard PG* variables
# (e.g. PGHOST, PGPORT, PGUSER) and SRC_DB (default: stitchline).
# =====================================================================
set -euo pipefail

BASE=${BASE:-/tmp/stitchline-cluster}
PG_BIN=${PG_BIN:-$(dirname "$(command -v pg_ctl 2>/dev/null || echo /usr/lib/postgresql/16/bin/pg_ctl)")}
SRC_DB=${SRC_DB:-stitchline}
SOCK="$BASE/sock"
declare -A PORT=([primary]=5440 [replica1]=5441 [replica2]=5442 [shard1]=5450 [shard2]=5451)
ORDER=(primary replica1 replica2 shard1 shard2)

pgc()  { "$PG_BIN/pg_ctl" -D "$BASE/$1" -l "$BASE/$1.log" -w "${@:2}"; }
q()    { "$PG_BIN/psql" -X -q -h "$SOCK" -p "${PORT[$1]}" -U "$(whoami)" -d "${3:-postgres}" -Atc "$2"; }

common_conf() {   # settings shared by every server
  cat >> "$BASE/$1/postgresql.conf" <<EOF

# ---- StitchLine Portfolio 5 ----
port = ${PORT[$1]}
listen_addresses = ''
unix_socket_directories = '$SOCK'
cluster_name = '$1'
shared_buffers = 64MB
max_connections = 50
logging_collector = off
EOF
}

up() {
  mkdir -p "$SOCK"
  echo "==> dumping source database '$SRC_DB'"
  "$PG_BIN/pg_dump" -Fc -d "$SRC_DB" -f "$BASE/stitchline.dump"

  echo "==> primary (port ${PORT[primary]})"
  "$PG_BIN/initdb" -D "$BASE/primary" -A trust -U "$(whoami)" --data-checksums >/dev/null
  common_conf primary
  cat >> "$BASE/primary/postgresql.conf" <<EOF
wal_level = replica
max_wal_senders = 10
max_replication_slots = 10
wal_log_hints = on                 # lets pg_rewind re-attach an old primary after failover
wal_keep_size = '256MB'            # pg_rewind reads the old primary's WAL back to before the fork
synchronous_standby_names = ''     # asynchronous by default; demos switch this on and off
max_prepared_transactions = 10
EOF
  pgc primary start >/dev/null
  q primary "CREATE DATABASE stitchline"
  "$PG_BIN/pg_restore" -h "$SOCK" -p "${PORT[primary]}" -U "$(whoami)" -d stitchline --no-owner "$BASE/stitchline.dump"
  q primary "SELECT pg_create_physical_replication_slot('replica1'), pg_create_physical_replication_slot('replica2')" >/dev/null

  for r in replica1 replica2; do
    echo "==> $r (port ${PORT[$r]}) — base backup from the primary"
    # -R writes standby.signal + primary_conninfo; -S uses the replication slot
    "$PG_BIN/pg_basebackup" -h "$SOCK" -p "${PORT[primary]}" -U "$(whoami)" -D "$BASE/$r" -R -S "$r" -X stream
    common_conf "$r"
    echo "hot_standby = on" >> "$BASE/$r/postgresql.conf"
    pgc "$r" start >/dev/null
  done

  for s in shard1 shard2; do
    echo "==> $s (port ${PORT[$s]})"
    "$PG_BIN/initdb" -D "$BASE/$s" -A trust -U "$(whoami)" >/dev/null
    common_conf "$s"
    echo "max_prepared_transactions = 10" >> "$BASE/$s/postgresql.conf"
    pgc "$s" start >/dev/null
    q "$s" "CREATE DATABASE stitchline_shard"
  done
  status
}

status() {
  for n in "${ORDER[@]}"; do
    if [ -d "$BASE/$n" ] && "$PG_BIN/pg_ctl" -D "$BASE/$n" status >/dev/null 2>&1; then
      role=$(q "$n" "SELECT CASE WHEN pg_is_in_recovery() THEN 'standby' ELSE 'primary/standalone' END")
      printf "  %-9s port %-5s running  %s\n" "$n" "${PORT[$n]}" "$role"
    else
      printf "  %-9s port %-5s stopped\n" "$n" "${PORT[$n]}"
    fi
  done
  # after a failover (replication_demo.py R7) replica1 is the primary, so ask whichever node is
  for n in primary replica1 replica2; do
    if "$PG_BIN/pg_ctl" -D "$BASE/$n" status >/dev/null 2>&1 && [ "$(q "$n" "SELECT pg_is_in_recovery()")" = f ]; then
      echo "  replication (from $n, the current primary):"
      q "$n" "SELECT '    ' || application_name || '  state=' || state || '  sync=' || sync_state FROM pg_stat_replication ORDER BY 1"
      break
    fi
  done
}

down() {
  for n in "${ORDER[@]}"; do
    [ -d "$BASE/$n" ] && "$PG_BIN/pg_ctl" -D "$BASE/$n" stop -m fast >/dev/null 2>&1 || true
  done
  echo "all servers stopped"
}

case "${1:-}" in
  up)     [ -d "$BASE/primary" ] && { echo "$BASE exists — run '$0 reset' first"; exit 1; }; up ;;
  status) status ;;
  down)   down ;;
  reset)  down; rm -rf "$BASE"; echo "removed $BASE" ;;
  *)      echo "usage: $0 up|status|down|reset"; exit 1 ;;
esac
