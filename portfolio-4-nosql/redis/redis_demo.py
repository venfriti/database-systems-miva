#!/usr/bin/env python3
"""
StitchLine — Redis key-value model (Portfolio 4)

Four small, real uses of a key-value store next to PostgreSQL:
  R1  Production board cache   (hashes + a sorted set, loaded from PostgreSQL)
  R2  Optimistic stage move    (WATCH / MULTI / EXEC between two clients)
  R3  Idempotent payment entry (SET NX EX: a double-click cannot pay twice)
  R4  Stock reservation        (Lua script vs naive GET/SET under 50 threads)

Usage
  python3 redis_demo.py
Connections: REDIS_URL (default redis://localhost:6379/0) and PG* variables.
Output is printed and saved to ../test-results/redis-demo-output.txt
"""

import io
import os
import statistics
import threading
import time
import uuid
from contextlib import redirect_stdout
from pathlib import Path

import psycopg
import redis

HERE = Path(__file__).resolve().parent
OPEN = ("received", "cutting", "sewing", "embroidery", "ready")
r = redis.Redis.from_url(os.environ.get("REDIS_URL", "redis://localhost:6379/0"), decode_responses=True)


def median_ms(fn, n=200):
    times = []
    for _ in range(n):
        t = time.perf_counter()
        fn()
        times.append((time.perf_counter() - t) * 1000)
    return statistics.median(times)


def r1_board(pg):
    print("=== R1 Production board cache")
    rows = pg.execute("""
        SELECT o.order_number, COALESCE(s.school_name, ic.first_name || ' ' || ic.last_name) AS customer,
               o.status, o.due_date
        FROM sales_order o
        LEFT JOIN school s ON s.customer_id = o.customer_id
        LEFT JOIN individual_customer ic ON ic.customer_id = o.customer_id
        WHERE o.status IN %s""" % (OPEN,)).fetchall()

    for k in r.scan_iter("sl:*"):
        r.delete(k)
    t = time.perf_counter()
    p = r.pipeline(transaction=False)
    for num, cust, status, due in rows:
        p.hset(f"sl:order:{num}", mapping={"customer": cust, "status": status, "due": due.isoformat()})
        p.zadd("sl:board:due", {num: time.mktime(due.timetuple())})
        p.hincrby("sl:board:stage_count", status, 1)
    p.execute()
    print(f"  loaded {len(rows)} open orders in {(time.perf_counter() - t) * 1000:.1f} ms "
          f"(1 hash per order + sorted set by due date + stage counter)")

    def top10_redis():
        nums = r.zrange("sl:board:due", 0, 9)
        p = r.pipeline(transaction=False)
        for n in nums:
            p.hgetall(f"sl:order:{n}")
        return list(zip(nums, p.execute()))

    top10_sql = """
        SELECT o.order_number, COALESCE(s.school_name, ic.first_name || ' ' || ic.last_name), o.status, o.due_date
        FROM sales_order o
        LEFT JOIN school s ON s.customer_id = o.customer_id
        LEFT JOIN individual_customer ic ON ic.customer_id = o.customer_id
        WHERE o.status IN ('received','cutting','sewing','embroidery','ready')
        ORDER BY o.due_date LIMIT 10"""

    print("  10 most urgent orders (from Redis):")
    for num, h in top10_redis()[:5]:
        print(f"    {num:<16} {h['due']}  {h['status']:<10} {h['customer']}")
    print("    …")
    print(f"  stage counts: {r.hgetall('sl:board:stage_count')}")

    redis_ms = median_ms(top10_redis)
    sql_ms = median_ms(lambda: pg.execute(top10_sql).fetchall())
    cnt_r = median_ms(lambda: r.hgetall("sl:board:stage_count"))
    cnt_s = median_ms(lambda: pg.execute(
        "SELECT status, COUNT(*) FROM sales_order WHERE status IN %s GROUP BY status" % (OPEN,)).fetchall())
    print("  round-trip latency, median of 200 calls from Python (includes network/driver):")
    print(f"    top-10 board    Redis {redis_ms:6.3f} ms   PostgreSQL (indexed, Portfolio 2) {sql_ms:6.3f} ms")
    print(f"    stage counts    Redis {cnt_r:6.3f} ms   PostgreSQL GROUP BY               {cnt_s:6.3f} ms")
    print(f"  memory used by Redis: {r.info('memory')['used_memory_human']} for {r.dbsize()} keys; "
          f"one order hash = {r.memory_usage('sl:order:' + rows[0][0])} bytes")


def r2_watch():
    print("\n=== R2 Optimistic stage move with WATCH / MULTI / EXEC")
    num = r.zrange("sl:board:due", 0, 0)[0]
    key = f"sl:order:{num}"
    r.hset(key, "status", "cutting")
    a = redis.Redis(connection_pool=r.connection_pool)      # client A
    b = redis.Redis(connection_pool=r.connection_pool)      # client B

    pa = a.pipeline()
    pa.watch(key)                                            # A starts watching
    seen = pa.hget(key, "status")
    print(f"  A: WATCH {key}; sees status = {seen}")

    with b.pipeline() as pb:                                 # B moves it first
        pb.watch(key)
        pb.multi()
        pb.hset(key, "status", "sewing")
        pb.execute()
    print("  B: WATCH, MULTI, HSET status=sewing, EXEC → committed")

    try:
        pa.multi()
        pa.hset(key, "status", "cancelled")
        pa.execute()
        print("  A: EXEC → committed (unexpected)")
    except redis.WatchError:
        print("  A: MULTI, HSET status=cancelled, EXEC → WatchError: key changed since WATCH, nothing applied")
    finally:
        pa.reset()
    print(f"  final status = {r.hget(key, 'status')}  (B's move kept; A must refresh and decide again)")


def r3_idempotency():
    print("\n=== R3 Idempotent payment submission (SET NX EX)")
    token = str(uuid.uuid4())                   # generated when the payment form is opened

    def submit(click):
        first = r.set(f"sl:pay:idem:{token}", "INV-2026-0004", nx=True, ex=600)
        print(f"  click {click}: SET NX → {'OK, record payment' if first else 'already submitted, ignore'}")
        return bool(first)

    recorded = sum(submit(i) for i in (1, 2, 3))
    print(f"  payments recorded: {recorded}; token expires in {r.ttl(f'sl:pay:idem:{token}')} s")


LUA_RESERVE = """
local stock = tonumber(redis.call('GET', KEYS[1]) or '0')
local want  = tonumber(ARGV[1])
if stock >= want then
  redis.call('INCRBYFLOAT', KEYS[1], -want)
  return 1
end
return 0
"""


def r4_reservation():
    print("\n=== R4 Stock reservation: 50 threads each try to reserve 1 cone from 30")
    key = "sl:stock:gold_thread"

    def race(fn):
        r.set(key, 30)
        ok = []
        barrier = threading.Barrier(50)

        def worker():
            barrier.wait()
            ok.append(fn())
        ts = [threading.Thread(target=worker) for _ in range(50)]
        [t.start() for t in ts]
        [t.join() for t in ts]
        return sum(ok), float(r.get(key))

    def naive():                               # read, check, write back: the s06 bug
        stock = float(r.get(key))
        if stock >= 1:
            time.sleep(0.001)                  # the app does some work between read and write
            r.set(key, stock - 1)
            return 1
        return 0

    reserve = r.register_script(LUA_RESERVE)
    atomic = lambda: int(reserve(keys=[key], args=[1]))

    n_ok, left = race(naive)
    print(f"  naive GET-then-SET : {n_ok} reservations accepted, stock left {left:g}  "
          f"→ {'OVERSOLD by ' + str(int(n_ok - 30)) if n_ok > 30 else 'ok'} (lost updates)")
    n_ok, left = race(atomic)
    print(f"  Lua script         : {n_ok} reservations accepted, stock left {left:g}  "
          f"→ {'correct' if n_ok == 30 and left == 0 else 'WRONG'} (script runs atomically)")


def main():
    pg = psycopg.connect(dbname=os.environ.get("PGDATABASE", "stitchline"), autocommit=True)
    pg.execute("SET search_path TO stitchline")
    buf = io.StringIO()
    with redirect_stdout(buf):
        print(f"StitchLine Redis demo — Redis {r.info('server')['redis_version']} — "
              f"run {time.strftime('%Y-%m-%d %H:%M')}\n")
        r1_board(pg)
        r2_watch()
        r3_idempotency()
        r4_reservation()
    print(buf.getvalue())
    out = HERE.parent / "test-results" / "redis-demo-output.txt"
    out.parent.mkdir(exist_ok=True)
    out.write_text(buf.getvalue())


if __name__ == "__main__":
    main()
