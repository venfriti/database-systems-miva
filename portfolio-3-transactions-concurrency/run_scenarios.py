#!/usr/bin/env python3
"""
StitchLine — two-session concurrency scenario runner (Portfolio 3)

Each file in scenarios/ describes two database sessions (A and B) as an
ordered list of steps. This runner opens two real connections and executes
the steps in exactly that order, so the interleaving is the same every time.
A step that waits on a lock is detected and recorded as BLOCKED, and the
moment it is released is recorded too.

Scenario file format
    -- TITLE:  one-line title
    -- LEVEL:  isolation level(s) used
    -- EXPECT: what should happen
    -- @SETUP      statements run first on a separate admin connection
    -- @A          a step for session A (everything until the next marker)
    -- @B          a step for session B
    -- @CHECK      statements run at the end on the admin connection
    -- @TEARDOWN   clean-up on the admin connection

The same file can be followed by hand in two psql terminals: run each @A
block in terminal A and each @B block in terminal B, in file order.

Usage
    python3 run_scenarios.py                 # all scenarios
    python3 run_scenarios.py s05 s06         # selected scenarios

Connection: standard PG* environment variables; database defaults to stitchline.
Transcripts are written to test-results/<scenario>.txt
"""

import os
import re
import sys
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import psycopg

HERE = Path(__file__).resolve().parent
SCEN_DIR = HERE / "scenarios"
OUT_DIR = HERE / "test-results"
BLOCK_WAIT = 2.0          # seconds before a step is reported as blocked
MAX_WAIT = 15.0           # give up waiting for a blocked step after this


def connect(name: str) -> psycopg.Connection:
    conn = psycopg.connect(dbname=os.environ.get("PGDATABASE", "stitchline"),
                           autocommit=True, application_name=f"stitchline-{name}")
    conn.execute("SET search_path TO stitchline")
    conn.execute("SET lock_timeout = '20s'")
    return conn


def fmt_rows(cur) -> str:
    if cur.description is None:
        return cur.statusmessage or "OK"
    cols = [d.name for d in cur.description]
    rows = cur.fetchall()
    if not rows:
        return "(0 rows)"
    shown = []
    for r in rows[:6]:
        shown.append(", ".join(f"{c}={v}" for c, v in zip(cols, r)))
    more = f"  … ({len(rows)} rows)" if len(rows) > 6 else ""
    return " | ".join(shown) + more


def run_sql(conn, sql: str) -> str:
    """Run one step (possibly several statements). Return a printable result."""
    parts = []
    with conn.cursor() as cur:
        try:
            cur.execute(sql)
            while True:
                if cur.description is not None:
                    parts.append(fmt_rows(cur))
                elif cur.statusmessage:
                    parts.append(cur.statusmessage)
                if not cur.nextset():
                    break
        except psycopg.Error as e:
            diag = e.diag
            msg = (diag.message_primary or str(e)).strip()
            code = diag.sqlstate or ""
            return f"ERROR [{code}] {msg}"
    return " ; ".join(p for p in parts if p) or "OK"


def parse(path: Path):
    meta, steps = {}, []
    current = None
    for line in path.read_text(encoding="utf-8").splitlines():
        m = re.match(r"--\s*(TITLE|LEVEL|EXPECT|STORY|RULE):\s*(.*)", line)
        if m:
            meta[m.group(1)] = (meta.get(m.group(1), "") + " " + m.group(2)).strip()
            continue
        m = re.match(r"--\s*@(SETUP|A|B|CHECK|TEARDOWN)\b", line)
        if m:
            current = [m.group(1), []]
            steps.append(current)
            continue
        if current is not None and line.strip() and not line.strip().startswith("--"):
            current[1].append(line)
    return meta, [(who, "\n".join(body).strip()) for who, body in steps if "\n".join(body).strip()]


def one_line(sql: str, width: int = 70) -> str:
    s = " ".join(sql.split())
    return s if len(s) <= width else s[: width - 1] + "…"


def run_scenario(path: Path) -> str:
    meta, steps = parse(path)
    out = [f"SCENARIO {path.stem}", f"Title : {meta.get('TITLE','')}",
           f"Level : {meta.get('LEVEL','')}", f"Expect: {meta.get('EXPECT','')}"] + ([f"Story : {meta['STORY']}"] if 'STORY' in meta else []) + ([f"Rule  : {meta['RULE']}"] if 'RULE' in meta else []) + [""]
    admin = connect("admin")
    sess = {"A": connect("A"), "B": connect("B")}
    pool = ThreadPoolExecutor(max_workers=2)
    pending = {}                 # session -> (step_no, future, started)
    lock = threading.Lock()
    t0 = time.perf_counter()
    n = 0

    def log(line):
        with lock:
            out.append(line)

    def stamp():
        return f"{time.perf_counter() - t0:6.2f}s"

    def reap(timeout=0.0):
        """Report blocked steps that have now finished."""
        for who in list(pending):
            step_no, fut, started = pending[who]
            try:
                res = fut.result(timeout=timeout)
            except Exception:
                continue
            waited = time.perf_counter() - started
            log(f"{stamp()}  [{step_no:>2}] {who}  ↳ UNBLOCKED after {waited:.2f}s → {res}")
            del pending[who]

    for who, sql in steps:
        if who in ("SETUP", "CHECK", "TEARDOWN"):
            if who != "SETUP":
                for w in list(pending):
                    reap(timeout=MAX_WAIT)
            res = run_sql(admin, sql)
            if who == "SETUP":
                log(f"SETUP   {one_line(sql, 90)}")
            elif who == "CHECK":
                log("")
                log(f"CHECK   {one_line(sql, 90)}")
                log(f"        → {res}")
            continue

        if who in pending:                      # this session is still blocked
            reap(timeout=MAX_WAIT)
        if n == 0:
            log("")
            log(f"{'time':>7}  {'#':>4} S  statement  →  result")
        n += 1
        started = time.perf_counter()
        at = f"{started - t0:6.2f}s"
        fut = pool.submit(run_sql, sess[who], sql)
        try:
            res = fut.result(timeout=BLOCK_WAIT)
            log(f"{at}  [{n:>2}] {who}  {one_line(sql)}  →  {res}")
        except Exception:
            log(f"{at}  [{n:>2}] {who}  {one_line(sql)}  →  ⏳ BLOCKED (waiting for a lock)")
            pending[who] = (n, fut, started)
        time.sleep(0.15)
        reap(timeout=0.3)

    reap(timeout=MAX_WAIT)
    for c in sess.values():
        try:
            c.execute("ROLLBACK")
        except Exception:
            pass
        c.close()
    admin.close()
    pool.shutdown()
    return "\n".join(out) + "\n"


def main():
    wanted = sys.argv[1:]
    files = sorted(SCEN_DIR.glob("s*.sql"))
    if wanted:
        files = [f for f in files if any(f.stem.startswith(w) for w in wanted)]
    OUT_DIR.mkdir(exist_ok=True)
    for f in files:
        text = run_scenario(f)
        (OUT_DIR / f"{f.stem}.txt").write_text(text, encoding="utf-8")
        print(text)


if __name__ == "__main__":
    main()
