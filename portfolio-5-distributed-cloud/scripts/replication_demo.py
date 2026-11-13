#!/usr/bin/env python3
"""
StitchLine — replication, consistency and failover demos (Portfolio 5)

Run after `./cluster.sh up`, as the same OS user that owns the cluster:
    python3 replication_demo.py

  R1  Replication status (primary and both replicas)
  R2  Propagation: how long until a committed order is visible on each replica
  R3  Replicas are read-only
  R4  Reports can run on a replica and return the same answer
  R5  Asynchronous lag: a stale read from a replica (read-your-writes broken)
  R6  Synchronous replication: commit latency, read-your-writes, and the
      availability cost when the synchronous replica dies (FIRST 1 vs ANY 1)
  R7  Failover: crash the primary, promote replica1, re-point replica2,
      rewind the old primary and re-attach it as a replica

R7 changes the topology (replica1 becomes the primary).
Rebuild with `./cluster.sh reset && ./cluster.sh up`.
Output is saved to ../test-results/replication-demo-output.txt
"""

import getpass
import io
import os
import shutil
import statistics
import subprocess
import sys
import threading
import time
from contextlib import redirect_stdout
from pathlib import Path

import psycopg

BASE = os.environ.get("BASE", "/tmp/stitchline-cluster")
SOCK = f"{BASE}/sock"
PG_BIN = os.environ.get("PG_BIN") or os.path.dirname(shutil.which("pg_ctl") or "/usr/lib/postgresql/16/bin/pg_ctl")
PORT = {"primary": 5440, "replica1": 5441, "replica2": 5442}
USER = getpass.getuser()
OUT = Path(__file__).resolve().parent.parent / "test-results" / "replication-demo-output.txt"


def conn(node, db="stitchline"):
    c = psycopg.connect(host=SOCK, port=PORT[node], dbname=db, user=USER, autocommit=True)
    c.execute("SET search_path TO stitchline, public")
    return c


def one(c, sql, *a):
    return c.execute(sql, a).fetchone()


def pg_ctl(node, *args):
    return subprocess.run([f"{PG_BIN}/pg_ctl", "-D", f"{BASE}/{node}", "-l", f"{BASE}/{node}.log", "-w", *args],
                          capture_output=True, text=True)


def header(t):
    print(f"\n{'=' * 78}\n{t}\n{'=' * 78}")


def table(rows, cols):
    w = [max(len(str(c)), *(len(str(r[i])) for r in rows)) for i, c in enumerate(cols)] if rows else [len(c) for c in cols]
    print("  " + "  ".join(str(c).ljust(w[i]) for i, c in enumerate(cols)))
    for r in rows:
        print("  " + "  ".join(str(v).ljust(w[i]) for i, v in enumerate(r)))


def set_sync(p, value):
    p.execute(f"ALTER SYSTEM SET synchronous_standby_names = '{value}'")
    p.execute("SELECT pg_reload_conf()")
    time.sleep(0.5)


# ----------------------------------------------------------------------
def r1_status(p, r1, r2):
    header("R1  Replication status")
    rows = p.execute("""SELECT application_name, state, sync_state,
                               pg_wal_lsn_diff(sent_lsn, replay_lsn) AS bytes_behind,
                               COALESCE(replay_lag::text, '0') AS replay_lag
                        FROM pg_stat_replication ORDER BY 1""").fetchall()
    print("  on the primary — pg_stat_replication:")
    table(rows, ["replica", "state", "sync", "bytes_behind", "replay_lag"])
    rows = p.execute("SELECT slot_name, active, wal_status FROM pg_replication_slots ORDER BY 1").fetchall()
    print("  replication slots (the primary keeps WAL until each replica has it):")
    table(rows, ["slot", "active", "wal_status"])
    for n, c in (("replica1", r1), ("replica2", r2)):
        rec, lsn = one(c, "SELECT pg_is_in_recovery(), pg_last_wal_replay_lsn()")
        st = one(c, "SELECT status, sender_port FROM pg_stat_wal_receiver")
        print(f"  {n}: in_recovery={rec}  replayed_up_to={lsn}  receiver={st[0]} from port {st[1]}")
    counts = [one(c, "SELECT COUNT(*) FROM sales_order")[0] for c in (p, r1, r2)]
    print(f"  sales_order rows  primary={counts[0]:,}  replica1={counts[1]:,}  replica2={counts[2]:,}")


def r2_propagation(p, r1, r2):
    header("R2  Propagation delay: commit on the primary, poll each replica until visible (20 orders)")
    delays = {"replica1": [], "replica2": []}
    for i in range(20):
        oid = one(p, "SELECT place_order(4, 2, CURRENT_DATE + 14, '[{\"variant_id\": 2, \"quantity\": 1}]', 'P5-TEST')")[0]
        t0 = time.perf_counter()
        pending = {"replica1": r1, "replica2": r2}
        while pending:
            for n, c in list(pending.items()):
                if one(c, "SELECT EXISTS (SELECT 1 FROM sales_order WHERE order_id = %s)", oid)[0]:
                    delays[n].append((time.perf_counter() - t0) * 1000)
                    del pending[n]
    for n, d in delays.items():
        print(f"  {n}: median {statistics.median(d):.2f} ms, max {max(d):.2f} ms until the new order was readable")
    print("  (asynchronous replication: the primary did NOT wait for this before confirming each commit)")


def r3_readonly(r1):
    header("R3  Replicas are read-only (hot standby)")
    for sql in ["INSERT INTO payment (invoice_id, amount, method, received_by) VALUES (4, 1, 'cash', 2)",
                "SELECT place_order(4, 2, CURRENT_DATE + 14, '[{\"variant_id\": 2, \"quantity\": 1}]', 'P5-TEST')"]:
        try:
            r1.execute(sql)
            print("  write accepted on replica1 (unexpected)")
        except psycopg.Error as e:
            print(f"  replica1 ← {sql[:58]}…\n      ERROR [{e.diag.sqlstate}] {e.diag.message_primary}")


def r4_reports(p, r1):
    header("R4  Run the annual revenue report on a replica")
    sql = """SELECT p.category, SUM(oi.quantity * oi.unit_price) AS revenue
             FROM sales_order o JOIN order_item oi USING (order_id)
             JOIN product_variant v USING (variant_id) JOIN product p USING (product_id)
             WHERE o.order_date >= '2025-01-01' AND o.order_date < '2026-01-01' AND o.status <> 'cancelled'
             GROUP BY 1 ORDER BY 1"""
    a = p.execute(sql).fetchall()
    t = time.perf_counter()
    b = r1.execute(sql).fetchall()
    ms = (time.perf_counter() - t) * 1000
    table([(cat, f"{rev:,.2f}") for cat, rev in b], ["category", "revenue (from replica1)"])
    print(f"  replica1 answered in {ms:.0f} ms; identical to the primary's answer: {a == b}")


def r5_stale(p, r1, r2):
    header("R5  Asynchronous lag → stale read (replay paused on replica1 to make the lag visible)")
    r1.execute("SELECT pg_wal_replay_pause()")
    before = one(p, "SELECT amount_paid FROM invoice WHERE invoice_id = 4")[0]
    p.execute("INSERT INTO payment (invoice_id, amount, method, reference, received_by) "
              "VALUES (4, 25.00, 'cash', 'P5-TEST', 2)")
    print(f"  front desk records a 25.00 payment on INV-2026-0004 (was {before}) — COMMIT returns at once")
    time.sleep(0.3)
    rows = [(n, one(c, "SELECT amount_paid FROM invoice WHERE invoice_id = 4")[0]) for n, c in
            (("primary", p), ("replica1", r1), ("replica2", r2))]
    table(rows, ["server", "amount_paid seen"])
    lag = one(p, """SELECT pg_wal_lsn_diff(sent_lsn, replay_lsn), replay_lag FROM pg_stat_replication
                    WHERE application_name = 'replica1'""")
    print(f"  replica1 is {lag[0]:.0f} bytes of WAL behind — anyone reading from it sees the OLD balance")
    r1.execute("SELECT pg_wal_replay_resume()")
    t = time.perf_counter()
    while one(r1, "SELECT amount_paid FROM invoice WHERE invoice_id = 4")[0] == before:
        time.sleep(0.01)
    print(f"  replay resumed → replica1 shows {one(r1, 'SELECT amount_paid FROM invoice WHERE invoice_id = 4')[0]} "
          f"after {(time.perf_counter() - t) * 1000:.0f} ms  (eventual consistency)")


def r6_sync(p, r1, r2):
    header("R6  Synchronous replication: latency, read-your-writes, availability")
    p.execute("CREATE TABLE IF NOT EXISTS public.p5_commit_test (id serial PRIMARY KEY, at timestamptz DEFAULT now())")
    time.sleep(0.5)

    def commits(mode, n=200):
        p.execute(f"SET synchronous_commit = {mode}")
        t = []
        for _ in range(n):
            s = time.perf_counter()
            p.execute("INSERT INTO public.p5_commit_test DEFAULT VALUES")
            t.append((time.perf_counter() - s) * 1000)
        p.execute("RESET synchronous_commit")
        return statistics.median(t)

    def immediate_reads(mode, n=50):
        """insert on primary, then IMMEDIATELY read the row on replica1"""
        p.execute(f"SET synchronous_commit = {mode}")
        seen = 0
        for _ in range(n):
            new_id = one(p, "INSERT INTO public.p5_commit_test DEFAULT VALUES RETURNING id")[0]
            seen += one(r1, "SELECT EXISTS (SELECT 1 FROM public.p5_commit_test WHERE id = %s)", new_id)[0]
        p.execute("RESET synchronous_commit")
        return seen

    set_sync(p, "")
    rows = [("asynchronous (synchronous_standby_names = '')", f"{commits('on'):.3f}", f"{immediate_reads('on')}/50")]
    set_sync(p, "FIRST 1 (replica1)")
    rows.append(("FIRST 1 (replica1), synchronous_commit = on", f"{commits('on'):.3f}", f"{immediate_reads('on')}/50"))
    rows.append(("FIRST 1 (replica1), synchronous_commit = remote_apply", f"{commits('remote_apply'):.3f}",
                 f"{immediate_reads('remote_apply')}/50"))
    table(rows, ["mode", "median commit ms", "read-your-write on replica1"])
    print("  'on' waits until replica1 has the WAL on disk; 'remote_apply' waits until it is visible to queries")

    print("\n  -- replica1 (the synchronous replica) crashes --")
    pg_ctl("replica1", "stop", "-m", "immediate")
    blocked = {}

    def writer():
        c = conn("primary")
        blocked["pid"] = one(c, "SELECT pg_backend_pid()")[0]
        s = time.perf_counter()
        try:
            with c.cursor() as cur:
                cur.execute("INSERT INTO public.p5_commit_test DEFAULT VALUES")
                blocked["result"] = "committed"
        except psycopg.Error as e:
            blocked["result"] = f"ERROR {e.diag.message_primary}"
        blocked["secs"] = time.perf_counter() - s
        c.close()

    th = threading.Thread(target=writer)
    th.start()
    th.join(timeout=3)
    print(f"  FIRST 1 (replica1): a new commit on the primary is still waiting after 3 s → "
          f"{'BLOCKED (writes unavailable)' if th.is_alive() else 'completed?!'}")
    wait = one(p, "SELECT wait_event FROM pg_stat_activity WHERE pid = %s", blocked["pid"])
    print(f"  pg_stat_activity shows the session waiting on: {wait[0] if wait else '?'}")
    set_sync(p, "ANY 1 (replica1, replica2)")
    th.join(timeout=10)
    print(f"  switched to quorum ANY 1 (replica1, replica2) → the waiting commit {blocked.get('result')} "
          f"after {blocked.get('secs', 0):.1f} s in total")
    if blocked.get("secs", 0) > 4:
        print("     (released at replica2's next status report; an idle replica reports every "
              "wal_receiver_status_interval = 10 s)")
    s = time.perf_counter()
    p.execute("INSERT INTO public.p5_commit_test DEFAULT VALUES")
    print(f"  next commit with replica1 still down: {(time.perf_counter() - s) * 1000:.2f} ms ✓")
    pg_ctl("replica1", "start")
    time.sleep(1.5)
    st = one(p, "SELECT state, sync_state FROM pg_stat_replication WHERE application_name = 'replica1'")
    print(f"  replica1 restarted and caught up from its slot: state={st[0]} sync={st[1]}")
    set_sync(p, "")


def cleanup(p):
    p.execute("""DELETE FROM payment WHERE reference = 'P5-TEST'""")
    p.execute("""SELECT p3_reset()""")          # Portfolio 3 helper removes test orders, resets stock
    p.execute("""DELETE FROM payment WHERE invoice_id IN
                 (SELECT invoice_id FROM invoice JOIN sales_order USING (order_id) WHERE notes = 'P5-TEST')""")
    p.execute("""DELETE FROM invoice WHERE order_id IN (SELECT order_id FROM sales_order WHERE notes = 'P5-TEST')""")
    p.execute("""DELETE FROM stock_movement WHERE order_id IN (SELECT order_id FROM sales_order WHERE notes = 'P5-TEST')""")
    p.execute("""DELETE FROM order_stage_history WHERE order_id IN (SELECT order_id FROM sales_order WHERE notes = 'P5-TEST')""")
    p.execute("""DELETE FROM sales_order WHERE notes = 'P5-TEST'""")
    p.execute("""UPDATE material m SET stock_qty = (SELECT SUM(change_qty) FROM stock_movement s
                 WHERE s.material_id = m.material_id)""")
    p.execute("DROP TABLE IF EXISTS public.p5_commit_test")


def r7_failover():
    header("R7  Failover: the primary crashes")
    p = conn("primary")
    p.execute("CREATE TABLE IF NOT EXISTS public.p5_marker (note text, at timestamptz DEFAULT now())")
    p.execute("INSERT INTO public.p5_marker (note) VALUES ('written on the original primary just before the crash')")
    orders_before = one(p, "SELECT COUNT(*) FROM sales_order")[0]
    time.sleep(0.5)
    p.close()

    t0 = time.perf_counter()
    pg_ctl("primary", "stop", "-m", "immediate")
    print("  t=0.00s  primary killed (pg_ctl stop -m immediate = simulated crash)")
    try:
        conn("primary")
    except psycopg.Error:
        print(f"  t={time.perf_counter() - t0:.2f}s  application cannot connect to port 5440: writes are DOWN")

    r = pg_ctl("replica1", "promote")
    r1 = conn("replica1")
    while one(r1, "SELECT pg_is_in_recovery()")[0]:
        time.sleep(0.05)
    print(f"  t={time.perf_counter() - t0:.2f}s  replica1 promoted (pg_ctl promote) → now accepts writes")
    oid = one(r1, "SELECT place_order(4, 2, CURRENT_DATE + 14, '[{\"variant_id\": 2, \"quantity\": 1}]', 'P5-TEST')")[0]
    rto = time.perf_counter() - t0
    print(f"  t={rto:.2f}s  first order written on the new primary (order_id {oid})  → downtime ≈ {rto:.1f} s")
    tl = int(one(r1, "SELECT pg_walfile_name(pg_current_wal_lsn())")[0][:8], 16)
    print(f"  new primary is on timeline {tl}; marker row survived: "
          f"{one(r1, 'SELECT note FROM public.p5_marker')[0]!r}")
    print(f"  orders before crash {orders_before:,} → on new primary {one(r1, 'SELECT COUNT(*) FROM sales_order')[0]:,} "
          f"(+1 new): no committed data lost")

    # replica2 follows the new primary
    r1.execute("SELECT pg_create_physical_replication_slot('replica2')")
    r2 = conn("replica2")
    r2.execute(f"ALTER SYSTEM SET primary_conninfo = 'host={SOCK} port={PORT['replica1']} user={USER}'")
    r2.execute("SELECT pg_reload_conf()")
    for _ in range(100):
        row = one(r1, "SELECT state FROM pg_stat_replication WHERE application_name = 'replica2'")
        if row and row[0] == "streaming":
            break
        time.sleep(0.1)
    print(f"  replica2 re-pointed to port {PORT['replica1']} (ALTER SYSTEM primary_conninfo + reload): "
          f"{row[0] if row else 'not connected'}, sees order {oid}: "
          f"{one(r2, 'SELECT EXISTS (SELECT 1 FROM sales_order WHERE order_id = %s)', oid)[0] if row else '?'}")

    # old primary comes back as a replica of the new primary
    r1.execute("SELECT pg_create_physical_replication_slot('old_primary')")
    rw = subprocess.run([f"{PG_BIN}/pg_rewind", f"--target-pgdata={BASE}/primary",
                         f"--source-server=host={SOCK} port={PORT['replica1']} user={USER} dbname=postgres"],
                        capture_output=True, text=True)
    print(f"  pg_rewind on the old primary: {'ok' if rw.returncode == 0 else rw.stderr.strip()[:200]}")
    Path(f"{BASE}/primary/standby.signal").touch()
    with open(f"{BASE}/primary/postgresql.auto.conf", "a") as f:
        f.write(f"\nprimary_conninfo = 'host={SOCK} port={PORT['replica1']} user={USER} application_name=old_primary'\n"
                f"primary_slot_name = 'old_primary'\n"
                # pg_rewind copied replica1's config files; restore this server's own identity
                f"port = {PORT['primary']}\ncluster_name = 'primary'\n")
    pg_ctl("primary", "start")
    time.sleep(2)
    rows = r1.execute("SELECT application_name, state, sync_state FROM pg_stat_replication ORDER BY 1").fetchall()
    print("  new topology — pg_stat_replication on replica1 (the new primary):")
    table(rows, ["replica", "state", "sync"])
    print("  the old primary (port 5440) is now a read-only replica; the cluster is back to 1 primary + 2 replicas")

    cleanup(r1)
    r1.execute("DROP TABLE IF EXISTS public.p5_marker")
    for c in (r1, r2):
        c.close()


def main():
    buf = io.StringIO()

    class Tee(io.TextIOBase):
        def write(self, s):
            sys.__stdout__.write(s)
            buf.write(s)
            return len(s)

    with redirect_stdout(Tee()):
        print(f"StitchLine replication demo — run {time.strftime('%Y-%m-%d %H:%M')} — cluster in {BASE}")
        p, r1, r2 = conn("primary"), conn("replica1"), conn("replica2")
        r1_status(p, r1, r2)
        r2_propagation(p, r1, r2)
        r3_readonly(r1)
        r4_reports(p, r1)
        r5_stale(p, r1, r2)
        r6_sync(p, r1, r2)
        cleanup(p)
        for c in (p, r1, r2):
            c.close()
        if "--no-failover" not in sys.argv:
            r7_failover()
    OUT.parent.mkdir(exist_ok=True)
    OUT.write_text(buf.getvalue(), encoding="utf-8")


if __name__ == "__main__":
    main()
