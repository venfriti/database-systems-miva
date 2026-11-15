# Portfolio 2 — Query Processing and Optimisation

**Case study:** StitchLine Uniforms & Embroidery
**DBMS:** PostgreSQL 16

## Folder Contents

| Path | Contents |
|---|---|
| `data-generator/generate-data.sql` | Generates 11 years of realistic history (~100,000 orders) |
| `sql/queries/` | Seven business queries, plus rewritten versions (q2b, q4b, q5b) |
| `sql/indexes.sql` | Optimisation round 1: six indexes, each justified by a query |
| `sql/redesign.sql` | Optimisation round 2: stored balance and materialised summary view |
| `sql/write-overhead.sql` | Measures what the indexes cost on inserts |
| `benchmark.py` | Runs each query with `EXPLAIN (ANALYZE, BUFFERS)`, then saves the plan and median time |
| `report.py` | Builds `results/summary.md` and `results/before-after.png` |
| `execution-plans/<phase>/` | Full plan for every query in every phase |
| `results/` | Timings (CSV), summary table, chart, query output, write-overhead results, generator output |
| `screenshots/` | Screenshots of plans and results |

---

## 1. How PostgreSQL Processes a Query

Every query passes through four stages:

1. **Parser.** Checks the syntax and builds a parse tree.
2. **Analyser and rewriter.** Resolves table and column names and expands views. For example, `v_invoice_balance` in Q2 is replaced by its full definition.
3. **Planner/optimiser.** Builds candidate plans and estimates the cost of each, using table statistics gathered by `ANALYZE` (row counts, value distributions, correlation between column order and physical order). It picks the cheapest plan. This is where it chooses:
   - a **scan method**: sequential, index, index-only or bitmap;
   - a **join method**: nested loop, hash join or merge join;
   - a **join order**.
4. **Executor.** Runs the chosen plan.

`EXPLAIN ANALYZE` shows the planner's estimates (`cost=`, `rows=`) next to what actually happened (`actual time=`, `rows=`, `loops=`). Optimising means getting the planner a cheaper option: an index, a query it can rewrite, or less data to process.

---

## 2. Test Environment

| Item | Value |
|---|---|
| DBMS | PostgreSQL 16.13 in Docker (`postgres:16-alpine`), default configuration: `shared_buffers` 128 MB, `work_mem` 4 MB |
| Hardware | AMD Ryzen 7 5800H (8 cores / 16 threads, 3.2 GHz), 40 GB RAM, NVMe SSD, Windows 11. Docker Desktop on WSL2, VM limit 16 vCPU / 19 GB RAM |
| Method | 1 warm-up run, then the median of 5 runs. Warm cache. |
| Reference date | 2026-11-15, fixed in every query so results can be reproduced |

### Data volume

`data-generator/generate-data.sql` builds on the Portfolio 1 sample data. It is pure SQL and seeded, so every run produces identical data.

| Table | Rows |
|---|---|
| order_stage_history | 587,127 |
| order_item | 273,050 |
| stock_movement | 211,666 |
| payment | 140,227 |
| order_item_design | 116,581 |
| sales_order | 100,006 |
| invoice | 97,095 |
| customer (150 schools, 3,000 individuals) | 3,150 |

The generator builds in several features of real data, because they change what the planner decides:

- **Seasonal peaks.** 40% of orders fall in the August–September back-to-school rush.
- **Skewed customers.** A few large schools place most school orders. The biggest has 4,744 orders; a typical school has about 100.
- **Order ids follow dates.** `order_id` rises with `order_date`, because orders are entered as they arrive.
- **Few open orders.** Only 585 orders (0.6%) are still in production.
- **About 10% of invoices are unpaid.**

After generating, the script checks that no invoice is overpaid, that stock reconciles with its movement history, and that every invoice total matches its order lines. All three checks pass.

---

## 3. Business Queries

| # | Query | Business use | SQL features |
|---|---|---|---|
| Q1 | [Customer history](sql/queries/q1_customer_history.sql) | A school calls to reorder | 3-table outer join, grouping, sort |
| Q2 | [Outstanding balances](sql/queries/q2_outstanding.sql) | Accounts chases overdue invoices | View expansion, aggregation, top-N |
| Q3 | [Production board](sql/queries/q3_production_board.sql) | The workshop's to-do list | Supertype/subtype joins, `IN` filter |
| Q4 | [Monthly revenue by category](sql/queries/q4_monthly_revenue.sql) | Annual sales report | 4-table join, date range, `COUNT(DISTINCT)` |
| Q5a | [Stuck orders (correlated)](sql/queries/q5a_stuck_orders_correlated.sql) | Find orders nobody has moved for 7 days | Correlated scalar subquery |
| Q5b | [Stuck orders (`NOT EXISTS`)](sql/queries/q5b_stuck_orders_not_exists.sql) | Same question, rewritten | Anti-join |
| Q6 | [Reorder report](sql/queries/q6_reorder_report.sql) | What fabric to buy | Outer join, conditional aggregation |
| Q7 | [Record a payment](sql/queries/q7_record_payment.sql) | Accounts takes a payment | **Write path**, trigger cost |

Sample output from each query is in [`results/query-output/`](results/query-output/).

---

## 4. Optimisation Method

1. **Baseline.** Measure on the Portfolio 1 schema, which deliberately has no foreign-key indexes. → `execution-plans/before/`
2. **Round 1: indexes** (`sql/indexes.sql`). Read each baseline plan, find the expensive node, and add an index that removes it. → `execution-plans/after-indexes/`
3. **Round 2: redesign** (`sql/redesign.sql`). Two queries stayed slow after indexing, so the way their data is stored was changed. → `execution-plans/after-redesign/`
4. **Cost check.** Measure what the indexes cost on writes and in storage.
5. **Correctness.** Each rewritten query was compared with its original using `EXCEPT` in both directions. Q2 and Q2b return identical rows, as do Q4 and Q4b.

```bash
rm results/timings.csv        # benchmark.py appends, so start from an empty file
psql -d stitchline -f data-generator/generate-data.sql
python3 benchmark.py before --only q1,q2,q3,q4,q5a,q5b,q6,q7
psql -d stitchline -f sql/indexes.sql
python3 benchmark.py after-indexes --only q1,q2,q3,q4,q5a,q5b,q6,q7
psql -d stitchline -f sql/redesign.sql
python3 benchmark.py after-redesign --only q2,q2b,q4,q4b,q7
psql -d stitchline -f sql/write-overhead.sql    # run 9 times, see §7
python3 report.py
```

The first two benchmark phases are limited to the eight original queries. `q2b` and `q4b` read `invoice.amount_paid` and `mv_monthly_category_sales`, which only exist after `redesign.sql`. On Windows, use `python` instead of `python3`.

---

## 5. Results

![Before vs after](results/before-after.png)

| Query | Before | After indexes | After redesign | Speed-up | Technique |
|---|---|---|---|---|---|
| Q1 Customer history | 30.9 ms | 2.4 ms | — | **13×** | Composite index `(customer_id, order_date DESC)` |
| Q2 Outstanding balances | 365 ms | 355 ms | 0.84 ms | **435×** | Stored `amount_paid` + partial index |
| Q3 Production board | 18.7 ms | 2.1 ms | — | **8.8×** | Partial index on open orders |
| Q4 Monthly revenue | 98.1 ms | 94.6 ms | 0.19 ms | **519×** | Materialised summary view |
| Q5a Stuck orders (correlated) | 11,939 ms | 1.7 ms | — | **7,214×** | Index `(order_id, changed_at DESC)` |
| Q5b Stuck orders (`NOT EXISTS`) | 39.9 ms | 0.99 ms | — | **40×** | Rewritten to an anti-join, plus the same index |
| Q6 Reorder report | 17.5 ms | 10.8 ms | — | **1.6×** | Index `(material_id, moved_at)` |
| Q7 Record a payment (write) | 12.1 ms | 4.3 ms | 5.2 ms | **2.3×** | FK index on `payment(invoice_id)`; the redesign added no further gain |

Raw measurements are in [`results/timings.csv`](results/timings.csv).

---

## 6. Analysis

### Q1 — Composite index on the filter column

**Before:** `Seq Scan on sales_order … Rows Removed by Filter: 99,897`. The planner read all 100,000 orders to find 109. It then hashed all 140,227 payments to join them to those orders.

**After:** a **bitmap index scan** on `idx_sales_order_customer_date` finds the 109 orders directly. `idx_payment_invoice` turns the payment join into 109 index lookups. Putting `customer_id` first in the index is what matters, because it is the equality column.

The index's `order_date DESC` order is *not* used. The `GROUP BY` sorts the rows by `order_id` first, so the plan sorts the 109 results again for the final `ORDER BY order_date DESC`. Sorting 109 rows costs a fraction of a millisecond, so this does not matter here. It does show that a planner only uses an index's order when nothing in between reorders the rows.

### Q2 — When indexes cannot help

**Before and after indexes**, the plan is the same:

```
HashAggregate  (rows=9,675)  ← groups ALL 139,905 payment rows
  -> Hash Right Join
       -> Seq Scan on payment   (140,227 rows)
       -> Seq Scan on invoice   (96,637 rows)
```

To know which invoices have a balance above zero, the view must first sum *every* invoice's payments. No index can avoid that, because the filter (`balance > 0`) applies to a value that only exists after aggregation. The time moved from 365 to 355 ms, but the plan did not change, so the difference is run-to-run noise.

**Redesign:** store `amount_paid` on the invoice, maintained by a trigger on `payment`. Add a **partial index** on `due_date` covering only unpaid invoices (160 kB). The new plan reads the unpaid invoices in `due_date` order and stops after 52 rows:

```
Limit (rows=50)
  -> Incremental Sort   (Presorted Key: due_date)
       -> Nested Loop
            -> Index Scan using idx_invoice_outstanding on invoice   (rows=52)
```

Both queries end with `invoice_number` as a tie-breaker, so invoices due on the same day always come back in the same order. The index only supplies the `due_date` order, so the planner adds an **Incremental Sort**: it sorts just the invoices that share a due date, and reads two rows past the 50th to finish the last group.

**365 ms → 0.84 ms.** This reverses a Portfolio 1 decision, on purpose. Portfolio 1 said the balance should be computed, not stored, "unless performance requires it", and this is the measured case where it does.

The redesign also had a side benefit. Overpayment was previously policed by a trigger that summed rows. It is now a one-row `CHECK (amount_paid <= total_amount)`, and the trigger was dropped. Portfolio 1 noted the old trigger could be beaten by two simultaneous payments. The new design closes that gap, because the `UPDATE … SET amount_paid = amount_paid + x` takes a row lock. Portfolio 3 tests this.

**One estimation quirk.** The planner estimated 32,218 unpaid invoices; the true number is about 9,700. PostgreSQL has no statistics for a comparison *between two columns* (`amount_paid < total_amount`), so it falls back to a default guess of one third. Here it does no harm, because `LIMIT 50` stops early. Without the `LIMIT`, it could push the planner towards a worse plan.

### Q3 — Partial index for a small, hot subset

Only 0.6% of orders are open, but those are the rows production staff look at all day. The partial index stores only those rows: 16 kB, against 2–3 MB for a full index on the same table. It stays that size however many delivered orders pile up. The predicate in `CREATE INDEX … WHERE status IN (…)` has to match the query's `WHERE` exactly, because the planner only uses a partial index when it can prove the query is covered by it.

### Q4 — Better join plans are not enough

After adding `idx_sales_order_date`, the plan used the index to find 2025's 8,894 orders. It still read all 273,050 order lines with a sequential scan and joined them with a hash join, and the time barely moved (98 → 95 ms).

To test the planner's choice, two alternatives were timed against it, alternating over 15 rounds:
- **forced nested loop:** hash and merge joins were switched off, forcing a nested loop with 8,894 index lookups into `order_item`;
- **two-level grouping:** a rewrite that groups per order first, then per month and category.

| Variant | Median | Range |
|---|---|---|
| Planner's choice (hash join) | 86 ms | 80–95 ms |
| Forced nested loop | 56 ms | 52–71 ms |
| Two-level grouping | 83 ms | 77–98 ms |

The planner's choice was not the fastest: the nested loop was about 35% quicker, and the ranges do not overlap. Even so, none of the variants comes close to what the report needs. Most of the time goes on joining 24,269 order lines and sorting them for `COUNT(DISTINCT)`, and every variant still has to do that work.

**Redesign:** past months never change, so the totals are computed once into `mv_monthly_category_sales` (60 rows a year) and refreshed nightly. The report becomes a 60-row index read: **98 ms → 0.19 ms**.

The costs are:
- **refresh time:** 0.57 s, run nightly with `REFRESH … CONCURRENTLY` so readers aren't blocked;
- **staleness:** the current month lags by up to a day, which is fine for an annual report. A live dashboard would need the current month computed directly and joined with the view.

### Q5 — The same question, three plans

This is the clearest demonstration of query processing in the portfolio.

**Q5a, correlated scalar subquery, no index: 11.9 seconds.**

```
Seq Scan on sales_order o
  Filter: ... (SubPlan 1) < '2026-11-08'
  SubPlan 1
    -> Aggregate                                 (loops=585)
         -> Seq Scan on order_stage_history h    (loops=585)   ← 587,127 rows × 585
```

The planner cannot flatten a correlated `MAX()` subquery into a join. So the subquery re-runs once per open order, and each run scans the whole 587,000-row history table. That is about 343 million rows read. The estimated cost (1.2 billion) shows the planner knew this plan was terrible, but it had no other option.

**Q5b, `NOT EXISTS`, no index: 40 ms.** The query is logically equivalent. However, the planner converts `NOT EXISTS` into a **Hash Right Anti Join**: the history table is scanned once, and the open orders are matched against it in memory. That is **299× faster with no index at all**, purely from how the query is written.

**With `idx_stage_history_order_time`, both are fast** (1.7 ms and 1.0 ms). Each subquery becomes an `Index Only Scan … Limit 1`: jump to the order's newest stage change and read one entry.

**Lessons:**
- Avoid correlated scalar subqueries on large tables.
- `EXISTS`/`NOT EXISTS` gives the planner more freedom.
- A good index makes the difference matter less.

### Q6 — Range scan per material

`idx_stock_movement_material_time` lets a **bitmap index scan** pick out the last 90 days of usage (about 8,800 rows) instead of reading 211,666 movements: 17.5 → 10.8 ms (1.6×). The gain is modest, because roughly 4% of the table still has to be read and aggregated.

### Q7 — Indexes help writes too

Recording one payment took 12.1 ms, and the plan's trigger timing shows why:

```
Trigger prevent_overpayment: time=10.402 calls=1
```

The trigger summed the invoice's existing payments, and with no index on `payment(invoice_id)` that meant scanning all 140,000 payments on **every insert**. After the index, the trigger took 2.2 ms and the whole insert 4.3 ms.

The redesign did not make the insert faster again: 5.2 ms, with the new `sync_amount_paid` trigger taking 1.9 ms. The run ranges overlap (3.8–5.7 ms with the old trigger, 4.6–6.3 ms with the new one), so the redesign costs at most a few milliseconds per payment. For Q7, the speed-up comes from the index. The redesign's benefit here is correctness: it closes the race described under Q2.

PostgreSQL does not index foreign-key columns automatically. Here an unindexed FK slowed down both reads (Q1) and writes (Q7).

---

## 7. The Cost of Optimisation

### Write overhead

[`sql/write-overhead.sql`](sql/write-overhead.sql) inserts 5,000 orders twice: once with the three new `sales_order` indexes, and once with them dropped inside a transaction that is then rolled back. The script measures one run; it was run 9 times and the medians taken (all runs are in [`results/write-overhead-summary.txt`](results/write-overhead-summary.txt)):

| | Insert 5,000 orders |
|---|---|
| Without the 3 extra indexes | 178 ms |
| With them | 206 ms (**+15%**) |

Write timings inside Docker vary between sessions. A second batch of 9 runs, straight after the first, gave +26%. Treat the overhead as roughly 15–26%.

Every index is one more structure to update on every insert. StitchLine enters about 25 orders a day on average and about 80 at the back-to-school peak, against reads every few seconds, so the trade is clearly worth it. A system with heavy write volume would need to be more selective.

### Storage

| Index | Size |
|---|---|
| idx_stage_history_order_time | 18 MB |
| idx_payment_invoice | 2,912 kB |
| idx_stock_movement_material_time | 2,360 kB |
| idx_sales_order_customer_date | 2,168 kB |
| idx_sales_order_date | 776 kB |
| idx_invoice_outstanding *(partial)* | 160 kB |
| idx_sales_order_open_due *(partial)* | 16 kB |

These sizes were measured after `REINDEX`. The size listing at the end of `write-overhead.sql` reads higher for the `sales_order` indexes, because the rolled-back test inserts leave dead entries behind in them.

The history index is the largest, because the history table is the largest. The two partial indexes are tiny, which makes partial indexing the most cost-effective technique used here.

### Consistency risk of denormalisation

`invoice.amount_paid` now duplicates information held in `payment`. If the sync trigger were ever bypassed or disabled, the two could disagree. Three things mitigate this:
- the `CHECK` constraint;
- a reconciliation query (0 mismatches after loading 140,000 payments);
- the fact that every write path goes through the trigger.

---

## 8. Conclusions

1. **Read the plan before adding an index.** Three of the biggest wins came from understanding *why* a plan was slow: aggregating everything (Q2), a re-executed subquery (Q5a), and a per-insert full scan (Q7).
2. **Indexes fix searching, not summarising.** Q2 and Q4 needed changes to what is stored, not more indexes.
3. **Partial indexes suit "small active subset" data**, like open orders and unpaid invoices, which most business systems have.
4. **How a query is written changes the plan.** `NOT EXISTS` beat a correlated `MAX()` by 299× with no index.
5. **Every optimisation has a price:** write overhead (+15–26% on inserts), storage, staleness (the materialised view) and consistency risk (the stored balance). Each one was measured or mitigated, not assumed.

---

## 9. Schema Changes Carried Forward

| Change | Effect on later portfolios |
|---|---|
| Six indexes (`indexes.sql`) | Kept in all later portfolios |
| `invoice.amount_paid` + `sync_amount_paid` trigger + `chk_invoice_not_overpaid` | Portfolio 3 tests concurrent payments against this design |
| `prevent_overpayment` trigger dropped | Replaced by the `CHECK` constraint |
| `mv_monthly_category_sales` | Reporting only |

## 10. Screenshots

| Screenshot | File |
|---|---|
| Data generator summary and integrity checks | `screenshots/01-data-generated.png` |
| Q5a plan before (SubPlan, loops=585) | `screenshots/02-q5a-before.png` |
| Q5a plan after (Index Only Scan) | `screenshots/03-q5a-after.png` |
| Q2 plan before (HashAggregate over all payments) | `screenshots/04-q2-before.png` |
| Q2b plan after (partial index + Limit) | `screenshots/05-q2b-after.png` |
| Benchmark runner output | `screenshots/06-benchmark.png` |
| Write-overhead results | `screenshots/07-write-overhead.png` |
