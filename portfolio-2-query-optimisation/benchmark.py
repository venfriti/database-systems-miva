#!/usr/bin/env python3
"""
StitchLine — query benchmark runner (Portfolio 2)

Runs every query in sql/queries/ with EXPLAIN (ANALYZE, BUFFERS), repeats it
several times, and records:
  * the full execution plan of the last run   -> execution-plans/<phase>/<query>.txt
  * min / median / max execution time         -> results/timings.csv

Usage
  python3 benchmark.py <phase> [--runs N] [--only q1,q3]

  <phase> is a label for the state of the database, e.g. "before", "after-indexes".

Connection details are taken from the standard PostgreSQL environment
variables (PGHOST, PGPORT, PGUSER, PGDATABASE). Default database: stitchline.

Method
  * One warm-up run first, so every measured run reads from a warm cache.
  * Queries whose first line is "-- WRITE" run inside BEGIN ... ROLLBACK,
    so measuring them never changes the data.
  * The median is reported because it is not distorted by a single slow run.
"""

import argparse
import csv
import datetime as dt
import os
import re
import statistics
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
QUERY_DIR = HERE / "sql" / "queries"
PLAN_DIR = HERE / "execution-plans"
RESULTS_CSV = HERE / "results" / "timings.csv"

EXEC_RE = re.compile(r"Execution Time: ([\d.]+) ms")
PLAN_RE = re.compile(r"Planning Time: ([\d.]+) ms")


def run_explain(sql: str, is_write: bool) -> str:
    body = f"EXPLAIN (ANALYZE, BUFFERS) {sql.strip().rstrip(';')};"
    if is_write:
        body = f"BEGIN;\n{body}\nROLLBACK;"
    script = f"SET search_path TO stitchline;\n{body}\n"
    env = {**os.environ}
    env.setdefault("PGDATABASE", "stitchline")
    out = subprocess.run(
        ["psql", "-X", "-q", "-A", "-t", "-v", "ON_ERROR_STOP=1"],
        input=script, capture_output=True, text=True, env=env,
    )
    if out.returncode != 0:
        sys.exit(f"psql failed:\n{out.stderr}")
    return out.stdout


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("phase")
    ap.add_argument("--runs", type=int, default=5)
    ap.add_argument("--only", default="", help="comma-separated query prefixes, e.g. q1,q5a")
    args = ap.parse_args()

    only = [p.strip() for p in args.only.split(",") if p.strip()]
    files = sorted(QUERY_DIR.glob("q*.sql"))
    if only:
        files = [f for f in files if any(f.stem.startswith(p + "_") or f.stem == p for p in only)]

    out_dir = PLAN_DIR / args.phase
    out_dir.mkdir(parents=True, exist_ok=True)
    RESULTS_CSV.parent.mkdir(parents=True, exist_ok=True)
    new_csv = not RESULTS_CSV.exists()

    with RESULTS_CSV.open("a", newline="") as fh:
        writer = csv.writer(fh)
        if new_csv:
            writer.writerow(["timestamp", "phase", "query", "runs",
                             "min_ms", "median_ms", "max_ms", "planning_ms"])

        for f in files:
            sql_text = f.read_text()
            is_write = sql_text.lstrip().startswith("-- WRITE")
            query_only = "\n".join(l for l in sql_text.splitlines() if not l.startswith("--"))

            run_explain(query_only, is_write)                 # warm-up
            times, plan_times, plan = [], [], ""
            for _ in range(args.runs):
                plan = run_explain(query_only, is_write)
                times.append(float(EXEC_RE.search(plan).group(1)))
                plan_times.append(float(PLAN_RE.search(plan).group(1)))

            med = statistics.median(times)
            header = (
                f"-- Query : {f.stem}\n"
                f"-- Phase : {args.phase}\n"
                f"-- Runs  : {args.runs} (after 1 warm-up)\n"
                f"-- Execution time  min {min(times):.3f} ms | median {med:.3f} ms | max {max(times):.3f} ms\n"
                f"-- Planning time   median {statistics.median(plan_times):.3f} ms\n\n"
                f"{sql_text.strip()}\n\n-- Plan of the last run:\n"
            )
            (out_dir / f"{f.stem}.txt").write_text(header + plan)
            writer.writerow([dt.datetime.now().isoformat(timespec="seconds"), args.phase, f.stem,
                             args.runs, f"{min(times):.3f}", f"{med:.3f}", f"{max(times):.3f}",
                             f"{statistics.median(plan_times):.3f}"])
            fh.flush()
            print(f"{args.phase:>16}  {f.stem:<32} median {med:10.3f} ms")


if __name__ == "__main__":
    main()
