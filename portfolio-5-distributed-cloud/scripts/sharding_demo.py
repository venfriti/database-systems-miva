#!/usr/bin/env python3
"""
StitchLine — hash sharding across two servers with postgres_fdw (Portfolio 5)

The primary acts as the COORDINATOR. Orders are spread over two independent
PostgreSQL servers (shard1, shard2) by a hash of customer_id. The
coordinator holds a partitioned table whose partitions are FOREIGN tables
living on the shards, so applications still query one table.

  S1  Set up shards, foreign servers and the sharded table; load 100,006 orders
  S2  Data distribution and skew
  S3  Single-shard query  (shard key in the WHERE clause → one shard)
  S4  Scatter-gather query across all shards; S4b aggregate pushed down to the shards
  S5  Query without the shard key (order_number) → must ask every shard
  S6  Cross-shard writes: two-phase commit, and what a coordinator crash leaves behind

Run after `./cluster.sh up`, as the cluster's OS user:
    python3 sharding_demo.py
Output is saved to ../test-results/sharding-demo-output.txt
"""

import getpass
import io
import os
import sys
import time
from contextlib import redirect_stdout
from pathlib import Path

import psycopg

BASE = os.environ.get("BASE", "/tmp/stitchline-cluster")
SOCK = f"{BASE}/sock"
USER = getpass.getuser()
COORD = int(os.environ.get("COORD_PORT", 5440))
SHARDS = {"shard1": 5450, "shard2": 5451}
# 4 hash partitions, 2 per shard: adding a third shard later means moving
# whole partitions, not re-hashing every row.
LAYOUT = [(0, "shard1"), (1, "shard2"), (2, "shard1"), (3, "shard2")]
OUT = Path(__file__).resolve().parent.parent / "test-results" / "sharding-demo-output.txt"

COLS = """order_id INT NOT NULL, order_number VARCHAR(20) NOT NULL, customer_id INT NOT NULL,
          order_date DATE NOT NULL, due_date DATE NOT NULL, status VARCHAR(12) NOT NULL,
          total_amount NUMERIC(12,2), amount_paid NUMERIC(12,2)"""


def conn(port, db):
    c = psycopg.connect(host=SOCK, port=port, dbname=db, user=USER, autocommit=True)
    return c


def header(t):
    print(f"\n{'=' * 78}\n{t}\n{'=' * 78}")


def show(c, sql, *a, indent="  "):
    cur = c.execute(sql, a)
    rows = cur.fetchall()
    if cur.description and len(cur.description) == 1 and cur.description[0].name == "QUERY PLAN":
        for (line,) in rows:
            print(indent + line)
        return rows
    cols = [d.name for d in cur.description]
    w = [max(len(str(x)) for x in [c_] + [r[i] for r in rows]) for i, c_ in enumerate(cols)]
    print(indent + "  ".join(c_.ljust(w[i]) for i, c_ in enumerate(cols)))
    for r in rows:
        print(indent + "  ".join(str(v).ljust(w[i]) for i, v in enumerate(r)))
    return rows


def s1_setup(co):
    header("S1  Build the sharded orders table")
    for name, port in SHARDS.items():
        sc = conn(port, "stitchline_shard")
        sc.execute("DROP SCHEMA IF EXISTS shard CASCADE; CREATE SCHEMA shard")
        for rem, owner in LAYOUT:
            if owner == name:
                sc.execute(f"CREATE TABLE shard.orders_p{rem} ({COLS}, PRIMARY KEY (order_id))")
                sc.execute(f"CREATE INDEX ON shard.orders_p{rem} (customer_id, order_date DESC)")
        sc.close()
    co.execute("SET search_path TO stitchline")
    co.execute("CREATE EXTENSION IF NOT EXISTS postgres_fdw")
    co.execute("DROP TABLE IF EXISTS orders_sharded CASCADE")
    for name, port in SHARDS.items():
        co.execute(f"DROP SERVER IF EXISTS {name} CASCADE")
        co.execute(f"""CREATE SERVER {name} FOREIGN DATA WRAPPER postgres_fdw
                       OPTIONS (host '{SOCK}', port '{port}', dbname 'stitchline_shard',
                                async_capable 'true', batch_size '1000', fetch_size '1000')""")
        co.execute(f"CREATE USER MAPPING FOR CURRENT_USER SERVER {name} OPTIONS (user '{USER}')")
    co.execute(f"CREATE TABLE orders_sharded ({COLS}) PARTITION BY HASH (customer_id)")
    for rem, owner in LAYOUT:
        co.execute(f"""CREATE FOREIGN TABLE orders_sharded_p{rem} PARTITION OF orders_sharded
                       FOR VALUES WITH (MODULUS 4, REMAINDER {rem})
                       SERVER {owner} OPTIONS (schema_name 'shard', table_name 'orders_p{rem}')""")
    t = time.perf_counter()
    loaded = co.execute("""INSERT INTO orders_sharded
                  SELECT o.order_id, o.order_number, o.customer_id, o.order_date, o.due_date, o.status,
                         i.total_amount, i.amount_paid
                  FROM sales_order o LEFT JOIN invoice i USING (order_id)""").rowcount
    print(f"  loaded {loaded:,} orders through the coordinator in {time.perf_counter() - t:.1f} s "
          f"(each row routed to its shard by hash(customer_id))")
    for p in SHARDS.values():
        sc = conn(p, "stitchline_shard")
        sc.execute("ANALYZE")
        sc.close()
    for rem in range(4):
        co.execute(f"ANALYZE orders_sharded_p{rem}")
    print("  coordinator layout:")
    show(co, """SELECT c.relname AS partition, pg_get_expr(c.relpartbound, c.oid) AS bound, s.srvname AS lives_on
                FROM pg_inherits i JOIN pg_class c ON c.oid = i.inhrelid
                JOIN pg_foreign_table f ON f.ftrelid = c.oid JOIN pg_foreign_server s ON s.oid = f.ftserver
                WHERE i.inhparent = 'stitchline.orders_sharded'::regclass ORDER BY 1""")


def s2_distribution(co):
    header("S2  Distribution and skew")
    for name, port in SHARDS.items():
        sc = conn(port, "stitchline_shard")
        parts = [f"orders_p{rem}" for rem, owner in LAYOUT if owner == name]
        n = sum(sc.execute(f"SELECT COUNT(*) FROM shard.{t}").fetchone()[0] for t in parts)
        size = sc.execute("SELECT pg_size_pretty(pg_database_size('stitchline_shard'))").fetchone()[0]
        print(f"  {name} (port {port}): {n:,} orders, database size {size}")
        sc.close()
    print("  the five largest customers and where they live:")
    show(co, """SELECT customer_id, COUNT(*) AS orders,
                       round(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_all,
                       tableoid::regclass AS partition
                FROM stitchline.orders_sharded GROUP BY customer_id, tableoid
                ORDER BY orders DESC LIMIT 5""")


def s3_single(co):
    header("S3  Single-shard query: customer history (shard key in WHERE)")
    show(co, """EXPLAIN (VERBOSE, COSTS OFF)
                SELECT order_number, order_date, status, total_amount
                FROM stitchline.orders_sharded WHERE customer_id = 94 ORDER BY order_date DESC""")
    t = time.perf_counter()
    n = len(co.execute("""SELECT order_number FROM stitchline.orders_sharded
                          WHERE customer_id = 94 ORDER BY order_date DESC""").fetchall())
    print(f"  → {n} rows from ONE shard in {(time.perf_counter() - t) * 1000:.1f} ms; the WHERE and ORDER BY ran on the shard")


def s4_scatter(co):
    header("S4  Scatter-gather: order counts and revenue by status across all shards")
    co.execute("SET enable_partitionwise_aggregate = on")
    show(co, """EXPLAIN (VERBOSE, COSTS OFF)
                SELECT status, COUNT(*), SUM(total_amount) FROM stitchline.orders_sharded GROUP BY status""")
    t = time.perf_counter()
    show(co, "SELECT status, COUNT(*) AS orders, SUM(total_amount) AS revenue FROM stitchline.orders_sharded GROUP BY status ORDER BY 2 DESC")
    sharded = (time.perf_counter() - t) * 1000
    t = time.perf_counter()
    co.execute("""SELECT o.status, COUNT(*), SUM(i.total_amount) FROM stitchline.sales_order o
                  LEFT JOIN stitchline.invoice i USING (order_id) GROUP BY o.status""").fetchall()
    local = (time.perf_counter() - t) * 1000
    print(f"  sharded: {sharded:.0f} ms   single server: {local:.0f} ms")
    print("  → PostgreSQL 16's postgres_fdw cannot push a PARTIAL aggregate to a shard: each shard")
    print("    ships its (status, total) rows and the coordinator aggregates per partition, then merges.")

    header("S4b Grouping BY THE SHARD KEY: the whole aggregate runs on the shards")
    show(co, """EXPLAIN (VERBOSE, COSTS OFF)
                SELECT customer_id, COUNT(*), SUM(total_amount) FROM stitchline.orders_sharded GROUP BY customer_id""")
    print("  → every customer lives on exactly one shard, so each shard can finish its own groups:")
    print("    'Remote SQL ... GROUP BY' — only one row per customer crosses the network")


def s5_broadcast(co):
    header("S5  Query WITHOUT the shard key: find one order by its number")
    show(co, """EXPLAIN (COSTS OFF) SELECT * FROM stitchline.orders_sharded WHERE order_number = 'SL-2026-0003'""")
    print("  → every shard must be asked (and order_number has no index on the shards)")
    print("  → uniqueness of order_number across shards can NOT be enforced by the database:")
    print("    each shard only knows its own rows, so a global UNIQUE constraint is impossible here")


def s6_twophase():
    header("S6  Cross-shard write: move a customer's order between shards with TWO-PHASE COMMIT")
    s1, s2 = conn(SHARDS["shard1"], "stitchline_shard"), conn(SHARDS["shard2"], "stitchline_shard")
    oid = s1.execute("SELECT order_id FROM shard.orders_p0 ORDER BY order_id LIMIT 1").fetchone()[0]
    print(f"  order {oid} must move from shard1 to shard2 (e.g. after re-sharding). Both writes must happen, or neither.")

    # phase 1: both shards do the work and PREPARE (vote yes, keep locks, survive a crash)
    s1.execute("BEGIN")
    row = s1.execute("DELETE FROM shard.orders_p0 WHERE order_id = %s RETURNING *", (oid,)).fetchone()
    s1.execute("PREPARE TRANSACTION 'move_order_1_shard1'")
    s2.execute("BEGIN")
    s2.execute("INSERT INTO shard.orders_p1 VALUES (%s,%s,%s,%s,%s,%s,%s,%s)", row)
    s2.execute("PREPARE TRANSACTION 'move_order_1_shard2'")
    print("  phase 1: both shards PREPARED (each has promised it can commit)")

    print("  -- coordinator crashes here, before sending COMMIT PREPARED --")
    s1.close(); s2.close()
    s1, s2 = conn(SHARDS["shard1"], "stitchline_shard"), conn(SHARDS["shard2"], "stitchline_shard")
    for name, c in (("shard1", s1), ("shard2", s2)):
        g = c.execute("SELECT gid, prepared FROM pg_prepared_xacts").fetchall()
        print(f"  {name}: pg_prepared_xacts → {[x[0] for x in g]} (survived the session ending)")
    s1.execute("SET lock_timeout = '1s'")
    try:
        s1.execute("UPDATE shard.orders_p0 SET status = status WHERE order_id = %s", (oid,))
        print("  another session updated the row (unexpected)")
    except psycopg.Error as e:
        print(f"  shard1: another session tries to touch order {oid} → ERROR {e.diag.message_primary}")
        print("          (the prepared transaction still holds its locks: 2PC BLOCKS until someone decides)")
    s1.execute("RESET lock_timeout")

    # phase 2: a recovering coordinator reads its decision log and finishes
    s1.execute("COMMIT PREPARED 'move_order_1_shard1'")
    s2.execute("COMMIT PREPARED 'move_order_1_shard2'")
    on1 = s1.execute("SELECT COUNT(*) FROM shard.orders_p0 WHERE order_id = %s", (oid,)).fetchone()[0]
    on2 = s2.execute("SELECT COUNT(*) FROM shard.orders_p1 WHERE order_id = %s", (oid,)).fetchone()[0]
    print(f"  phase 2: COMMIT PREPARED on both → order {oid} on shard1: {on1}, on shard2: {on2}  (moved exactly once)")
    print("  note: postgres_fdw on its own does NOT use 2PC; a crash between the two remote commits")
    print("        could leave one shard committed and the other not")
    s1.close(); s2.close()


def main():
    buf = io.StringIO()

    class Tee(io.TextIOBase):
        def write(self, s):
            sys.__stdout__.write(s)
            buf.write(s)
            return len(s)

    with redirect_stdout(Tee()):
        print(f"StitchLine sharding demo — run {time.strftime('%Y-%m-%d %H:%M')} — coordinator port {COORD}")
        co = conn(COORD, "stitchline")
        s1_setup(co)
        s2_distribution(co)
        s3_single(co)
        s4_scatter(co)
        s5_broadcast(co)
        s6_twophase()
        co.close()
    OUT.parent.mkdir(exist_ok=True)
    OUT.write_text(buf.getvalue(), encoding="utf-8")


if __name__ == "__main__":
    main()
