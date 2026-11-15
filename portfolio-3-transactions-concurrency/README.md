# Portfolio 3 — Transactions and Concurrency

**Case study:** StitchLine Uniforms & Embroidery
**DBMS:** PostgreSQL 16, on the database as left by Portfolio 2

## Folder Contents

| Path | Contents |
|---|---|
| `sql/00-setup.sql` | Adds credit limits, `place_order()`, `move_order_stage()` and `p3_reset()` |
| `sql/01-commit.sql` | COMMIT demo: one order across six tables |
| `sql/02-rollback.sql` | ROLLBACK demos: explicit, automatic on error, savepoint, sequences |
| `scenarios/s01…s18.sql` | 18 two-session scenarios, each a step-by-step script for sessions A and B |
| `run_scenarios.py` | Runs each scenario on two real connections in a fixed order and records a timeline |
| `test-results/` | Output of every demo and scenario |
| `screenshots/` | Two-terminal screenshots |

---

## 1. Why Transactions Matter at StitchLine

Taking one order writes to six tables: `sales_order`, `order_item`, `order_item_design`, `material` + `stock_movement`, `order_stage_history` and `invoice`. Up to ten staff work at once during the back-to-school rush. Each ACID property maps to something the business needs:

| Property | What it means here | Shown in |
|---|---|---|
| **Atomicity** | An order is saved completely or not at all. A failed stock check must not leave a half-entered order. | §3, §4 Part B |
| **Consistency** | Constraints hold after every transaction: no negative stock, no overpaid invoice | §4, s08, s14 |
| **Isolation** | Two staff working at once must not corrupt each other's work | §5, §6 |
| **Durability** | Once COMMIT returns, the order survives a disconnect or crash | §3 (re-read from a new connection) |

### How PostgreSQL isolates transactions

PostgreSQL uses **MVCC (multi-version concurrency control)**. An `UPDATE` writes a new version of the row instead of overwriting it. Each transaction reads from a *snapshot*, which decides which versions it can see. As a result:

- **readers never block writers, and writers never block readers** (seen in s01, s02 and s04: B reads freely while A has uncommitted changes);
- **two writers to the same row do block each other.** The second waits for the first to commit or roll back (seen in s07, s08, s14 and s16–s18).

| Level | Snapshot taken | Prevents |
|---|---|---|
| READ UNCOMMITTED | Treated as READ COMMITTED in PostgreSQL | dirty reads |
| **READ COMMITTED** *(default)* | At the start of each **statement** | dirty reads |
| REPEATABLE READ | At the start of the **transaction** | + non-repeatable reads, phantoms, lost updates (by aborting) |
| SERIALIZABLE | Transaction snapshot + conflict tracking (SSI) | + write skew. Result equals some serial order. |

---

## 2. How to Run

```bash
psql -d stitchline -f sql/00-setup.sql             # once, after Portfolio 2
psql -d stitchline -e -f sql/01-commit.sql
psql -d stitchline -e -f sql/02-rollback.sql
pip install "psycopg[binary]"
python3 run_scenarios.py                           # all 18 scenarios (~50 s)
python3 run_scenarios.py s06 s07                   # or selected ones
```

On Windows, use `python` instead of `python3`.

**The runner.** `run_scenarios.py` opens two real connections, A and B, and runs the steps in the exact order written, so every result can be reproduced. A step still waiting after 2 seconds is marked **⏳ BLOCKED**; when the other session releases its lock, the runner records **↳ UNBLOCKED** with the result. The times shown include that 2-second detection window. In reality B is released the moment A commits.

**Following a scenario by hand** (for screenshots). Open two `psql` terminals. Run each `-- @A` block in terminal A and each `-- @B` block in terminal B, in file order. Every scenario cleans up after itself through `p3_reset()`, which removes rows tagged `P3-TEST` and resets stock to its ledger total.

### Business routines added in `00-setup.sql`

| Routine | Purpose | Concurrency control inside |
|---|---|---|
| `place_order(customer, staff, due, items, notes)` | The whole order-entry operation in one call | Locks the school row before the credit check, then locks materials **in `material_id` order** before the stock check |
| `move_order_stage(order, expected, new, staff)` | Moves an order between production stages | **Optimistic**: only updates if the order is still at the stage the user saw |
| `school.credit_limit` | Credit rule: unpaid balance + new order ≤ limit | Enforced in `place_order()` |

---

## 3. COMMIT

[`sql/01-commit.sql`](sql/01-commit.sql) enters one order for Bayside Primary School (40 shirts with an embroidered crest) as a single transaction of eight statements across six tables, and then commits it.

```
 order_number   | status   | lines | designs | stock_moves | history | invoice_number  | total_amount
----------------+----------+-------+---------+-------------+---------+-----------------+--------------
 SL-2026-DEMO01 | received |     1 |       1 |           2 |       1 | INV-2026-DEMO01 |       800.00

 material_id | name                  | stock_qty | matches_ledger
-------------+-----------------------+-----------+----------------
           1 | White poplin fabric   |   1017.76 | t
           7 | Buttons (pack of 100) |    699.08 | t
```

All six parts exist, and stock still equals its ledger total. The script then:
- **places the same order through `place_order()`**: one call, one transaction;
- **reconnects (`\connect`) and reads the orders back** from a new session. That shows the commit is durable and visible to other connections.

Full output: [`test-results/01-commit-output.txt`](test-results/01-commit-output.txt)

---

## 4. ROLLBACK

[`sql/02-rollback.sql`](sql/02-rollback.sql), with full output in [`test-results/02-rollback-output.txt`](test-results/02-rollback-output.txt).

| Part | Scenario | Evidence |
|---|---|---|
| **A. Explicit ROLLBACK** | Staff start an order, deduct 35 m of poplin, then abandon it | Inside the transaction: 1 order, poplin 1038.76. After `ROLLBACK`: 0 orders, poplin back to 1073.76. |
| **B. Automatic rollback on error** | `place_order()` for 900 blazers. The function inserts the order header and lines *before* checking stock, then raises `Not enough Blazer wool blend: 679.22 in stock, 1620.00 needed` | The transaction is aborted: even `SELECT 1` is refused (`current transaction is aborted`). After `ROLLBACK`: 0 test orders, wool unchanged. **Atomicity**: the partly-written order vanished. |
| **C. SAVEPOINT** | Staff choose an unsupported placement (`trouser_leg`), which `order_item_design_placement_check` rejects | `ROLLBACK TO SAVEPOINT before_design` undoes only the bad insert. The order and line survive, the corrected `left_chest` placement is added, and the order commits. |
| **D. Sequences are not transactional** | `nextval('order_number_seq')` inside a rolled-back transaction | The sequence moved from 2 to 3 anyway. Order numbers can therefore have gaps. This is deliberate: it lets sequences serve concurrent sessions without locking. |

---

## 5. Isolation Levels

The same small test is run under different levels.

| # | Anomaly | Level | Result | Transcript |
|---|---|---|---|---|
| s01 | **Dirty read** (B reads A's uncommitted write) | READ UNCOMMITTED | ✅ Not possible. A set gold thread to 0 without committing; B still read **50**. | [s01](test-results/s01_dirty_read.txt) |
| s02 | **Non-repeatable read** (same row, two reads, different values) | READ COMMITTED | ⚠️ Occurs. Accounts read `amount_paid` **60**, then **90**, in one transaction. | [s02](test-results/s02_nonrepeatable_read_committed.txt) |
| s03 | Non-repeatable read | REPEATABLE READ | ✅ Prevented. Both reads return **60**. A new transaction sees 90. | [s03](test-results/s03_nonrepeatable_repeatable_read.txt) |
| s04 | **Phantom read** (same query, new rows appear) | READ COMMITTED | ⚠️ Occurs. The open-order count went **585 → 586**. | [s04](test-results/s04_phantom_read_committed.txt) |
| s05 | Phantom read | REPEATABLE READ | ✅ Prevented. **585 → 585.** | [s05](test-results/s05_phantom_repeatable_read.txt) |
| s10 | **Write skew** | REPEATABLE READ | ⚠️ Occurs. See §6.2. | [s10](test-results/s10_write_skew_repeatable_read.txt) |
| s11 | Write skew | SERIALIZABLE | ✅ Prevented. See §6.2. | [s11](test-results/s11_write_skew_serializable.txt) |

**Why it matters here.** A customer statement built under READ COMMITTED could show one balance at the top and a different one at the bottom, if a payment arrived while it was being generated (s02). Reports that read several related figures should run under REPEATABLE READ so they come from one consistent snapshot. That is cheap: it never blocks anyone.

PostgreSQL's REPEATABLE READ also prevents phantoms (s05). The SQL standard only requires that at SERIALIZABLE.

---

## 6. Concurrency Problems and How They Are Controlled

### 6.1 Lost update on material stock

Two staff take orders that both use gold thread. There are 50 cones; A needs 30 and B needs 40. The natural application code is *read stock → check it is enough → write back the new value*.

**s06: the problem (READ COMMITTED, no locking)**

```
  0.16s  [ 2] A  SELECT stock_qty FROM material WHERE material_id = 4;  →  stock_qty=50.00
  0.46s  [ 4] B  SELECT stock_qty FROM material WHERE material_id = 4;  →  stock_qty=50.00
  0.62s  [ 5] A  UPDATE material SET stock_qty = 20 WHERE material_id = 4;  →  UPDATE 1
  0.77s  [ 6] A  COMMIT;  →  COMMIT
  0.93s  [ 7] B  UPDATE material SET stock_qty = 10 WHERE material_id = 4;  →  UPDATE 1
  1.08s  [ 8] B  COMMIT;  →  COMMIT
CHECK   → final_stock=10.00, true_stock=-20
```

Both checks passed against the same stale value of 50. B's write erased A's. The database now claims 10 cones remain, when 70 cones were promised from 50.

**`CHECK (stock_qty >= 0)` did not help**, because every value actually written (20, then 10) was positive. Constraints check the values written, not whether they were based on stale data.

**Three fixes, each tested:**

| Scenario | Mechanism | What happened | Trade-off |
|---|---|---|---|
| [s07](test-results/s07_fix_select_for_update.txt) | **Pessimistic lock:** `SELECT … FOR UPDATE` | B's read **waited** until A committed, then saw **20**. 20 < 40, so B declined. Final stock 20 ✅ | Simple and always correct; B waits while A is busy |
| [s08](test-results/s08_fix_atomic_update.txt) | **Atomic update:** `SET stock_qty = stock_qty - 40` | B's update waited for A's row lock, then **re-applied itself to 20**. -20 broke the `CHECK`, so B failed ✅ | No read–write gap at all; the constraint becomes the safety net |
| [s09](test-results/s09_fix_repeatable_read_retry.txt) | **REPEATABLE READ + retry** | B's write failed with **40001** `could not serialize access due to concurrent update`. The retry read 20 and declined ✅ | No blocking, but the application *must* catch 40001 and retry |

s08 in full:

```
  0.16s  [ 2] A  UPDATE material SET stock_qty = stock_qty - 30 WHERE material_id = 4 …  →  stock_qty=20.00
  0.47s  [ 4] B  UPDATE material SET stock_qty = stock_qty - 40 WHERE material_id = 4 …  →  ⏳ BLOCKED (waiting for a lock)
  2.92s  [ 5] A  COMMIT;  →  COMMIT
  3.07s  [ 4] B  ↳ UNBLOCKED after 2.61s → ERROR [23514] new row for relation "material" violates check constraint "material_stock_qty_check"
```

**Used in StitchLine:** `place_order()` combines s07 and s08. It locks material rows `FOR UPDATE`, checks stock under the lock (so it can give a clear "Not enough …" message), then deducts with an atomic update.

### 6.2 Write skew on the credit limit

**Rule:** a school's unpaid balance plus a new order must not exceed its `credit_limit`. Bayside's headroom was set to 5,000, and two staff each enter a 3,000 order.

Unlike a lost update, the two transactions write **different rows** (each inserts its own order and invoice). No row is shared, so row locks never come into play.

| Scenario | Level | Result |
|---|---|---|
| [s10](test-results/s10_write_skew_repeatable_read.txt) | REPEATABLE READ | ⚠️ Both saw headroom 5,000 and both committed. **Final headroom −1,000**: the limit was broken. |
| [s11](test-results/s11_write_skew_serializable.txt) | SERIALIZABLE | ✅ B's `COMMIT` failed with **40001** `could not serialize access due to read/write dependencies among transactions`. B's retry saw headroom 2,000 and declined. |
| [s12](test-results/s12_credit_check_row_lock.txt) | READ COMMITTED + `place_order()` | ✅ B **waited** on A's lock on the `school` row. It then saw A's invoice: `Credit limit exceeded: outstanding 65584.99 + order 3000.00 > limit 67584.99`. |

s11, Serializable Snapshot Isolation in action:

```
  0.17s  [ 2] A  SELECT credit_limit - (SELECT SUM(...)) …  →  headroom=5000.00
  0.48s  [ 4] B  SELECT credit_limit - (SELECT SUM(...)) …  →  headroom=5000.00
  0.64s  [ 5] A  WITH o AS (INSERT INTO sales_order …) INSERT INTO invoice …  →  INSERT 0 1
  0.80s  [ 6] B  WITH o AS (INSERT INTO sales_order …) INSERT INTO invoice …  →  INSERT 0 1
  0.96s  [ 7] A  COMMIT;  →  COMMIT
  1.11s  [ 8] B  COMMIT;  →  ERROR [40001] could not serialize access due to read/write dependencies among transactions
  1.41s  [10] B  (retry) … → headroom_on_retry=2000.00
```

SERIALIZABLE tracks what each transaction *read* as well as what it wrote. It noticed that A's insert changed data B had read, and B's insert changed data A had read: a cycle that no serial order could produce. It aborted one transaction.

**Two ways to fix it:**
- **SERIALIZABLE:** automatic and general, but every transaction needs retry logic, and false-positive aborts are possible under load.
- **Lock a shared "parent" row** (s12): no retries needed, but the developer has to spot the hidden dependency and lock deliberately.

StitchLine uses the row lock, because order entry already has a natural parent row (the school), and staff shouldn't see "please try again" errors at the front desk.

### 6.3 Two payments at once: closing a gap from Portfolio 1

Portfolio 1 noted that its overpayment trigger could be beaten by two simultaneous payments. Portfolio 2 replaced it with a stored `amount_paid` and a `CHECK`. Both designs were tested with the same race: invoice total 120, already paid 60, and two staff each record 50.

| Scenario | Design | Result |
|---|---|---|
| [s13](test-results/s13_payments_race_p1_trigger.txt) | Portfolio 1: `BEFORE INSERT` trigger sums existing payments | ⚠️ Each trigger saw only committed payments (60) and approved its 50. **Total paid 160 on an invoice of 120. `overpaid=True`.** |
| [s14](test-results/s14_payments_p2_check.txt) | Portfolio 2: `UPDATE invoice SET amount_paid = amount_paid + x` + `CHECK (amount_paid <= total_amount)` | ✅ A's update locked the invoice row. B waited, then applied +50 to the **committed** 110. 160 > 120 broke `chk_invoice_not_overpaid`. **Paid 110.** |

```
s14
  0.15s  [ 2] A  INSERT INTO payment (...) VALUES (4, 50.00, ...)  →  INSERT 0 1
  0.46s  [ 4] B  INSERT INTO payment (...) VALUES (4, 50.00, ...)  →  ⏳ BLOCKED (waiting for a lock)
  2.91s  [ 5] A  COMMIT;  →  COMMIT
  3.07s  [ 4] B  ↳ UNBLOCKED after 2.60s → ERROR [23514] new row for relation "invoice" violates check constraint "chk_invoice_not_overpaid"
CHECK   → invoice_number=INV-2026-0004, total_amount=120.00, amount_paid=110.00
```

**Lesson:** a rule that reads *many* rows (sum of payments) cannot protect itself under concurrency at READ COMMITTED. Turning it into a rule about *one* row (`amount_paid` on the invoice) lets ordinary row locking and a `CHECK` do the job. So the Portfolio 2 change made payments faster *and* safer.

### 6.4 Deadlock and how to prevent it

**[s15](test-results/s15_deadlock.txt): the problem.** A deducts poplin then buttons; B deducts buttons then poplin.

```
  0.15s  [ 2] A  UPDATE material SET stock_qty = stock_qty - 1 WHERE material_id = 1;  →  UPDATE 1
  0.46s  [ 4] B  UPDATE material SET stock_qty = stock_qty - 1 WHERE material_id = 7;  →  UPDATE 1
  0.62s  [ 5] A  UPDATE material SET stock_qty = stock_qty - 1 WHERE material_id = 7;  →  ⏳ BLOCKED
  3.07s  [ 6] B  UPDATE material SET stock_qty = stock_qty - 1 WHERE material_id = 1;  →  ERROR [40P01] deadlock detected
  4.22s  [ 5] A  ↳ UNBLOCKED after 3.60s → UPDATE 1
```

Each session held what the other needed. After `deadlock_timeout` (1 second), PostgreSQL's deadlock detector found the cycle and aborted B, the session whose wait triggered the check. A then carried on. The data stayed correct, but B's work was lost and would have to be redone.

**[s16](test-results/s16_lock_ordering.txt): prevention through lock ordering.** A orders `[shirts, blazers]` and B orders `[blazers, shirts]`. Both need poplin (1), buttons (7) and wool (8). `place_order()` locks materials with `ORDER BY material_id … FOR UPDATE`, so both sessions lock 1 → 7 → 8 whatever order the items were typed in. B simply queued behind A. **Both orders succeeded**, and stock still matched the ledger.

A deadlock needs a cycle. If every transaction takes locks in the same global order, a cycle can't form.

### 6.5 Two staff move the same order: optimistic concurrency

The app lets anyone move an order between stages. Production worker A moves an order from cutting to sewing at the same moment that worker B, whose screen still shows "cutting", cancels it.

| Scenario | Method | Result |
|---|---|---|
| [s17](test-results/s17_stage_move_blind.txt) | Plain `UPDATE … SET status = 'cancelled' WHERE order_id = …` | ⚠️ B waited for A's lock, then **overwrote A's move**. Final status `cancelled`. History: `cutting→sewing, cutting→cancelled`. The order "left cutting twice", so the audit trail is now wrong. |
| [s18](test-results/s18_stage_move_optimistic.txt) | `move_order_stage(order, expected='cutting', new, staff)` | ✅ The update has `WHERE status = 'cutting'`. After waiting for A, B re-checked, found `sewing`, matched 0 rows and was refused: `Order … is no longer at stage "cutting": it was moved by someone else. Refresh and try again.` |

This is **optimistic concurrency control**: nothing is locked while the user looks at the screen. The write only succeeds if the data is still what the user saw. It suits StitchLine because staff may keep a screen open for minutes. Holding a database lock that long (pessimistic locking) would freeze everyone else.

---

## 7. Summary of All Scenarios

| # | Problem | Control | Outcome |
|---|---|---|---|
| s01 | Dirty read | MVCC (any level) | ✅ prevented |
| s02 / s03 | Non-repeatable read | READ COMMITTED / **REPEATABLE READ** | ⚠️ / ✅ |
| s04 / s05 | Phantom read | READ COMMITTED / **REPEATABLE READ** | ⚠️ / ✅ |
| s06 | Lost update (oversold stock) | none | ⚠️ 70 cones promised from 50 |
| s07 | Lost update | `SELECT … FOR UPDATE` | ✅ |
| s08 | Lost update | atomic `UPDATE` + `CHECK` | ✅ |
| s09 | Lost update | REPEATABLE READ + retry | ✅ |
| s10 | Write skew (credit limit) | REPEATABLE READ | ⚠️ limit exceeded by 1,000 |
| s11 | Write skew | **SERIALIZABLE** (SSI) + retry | ✅ |
| s12 | Write skew | lock on the school row in `place_order()` | ✅ |
| s13 | Overpayment race (P1 design) | trigger at READ COMMITTED | ⚠️ 160 paid on 120 |
| s14 | Overpayment race (P2 design) | single-row `CHECK` + row lock | ✅ |
| s15 | Deadlock | PostgreSQL deadlock detector | ✅ detected, one transaction aborted |
| s16 | Deadlock | consistent lock ordering | ✅ prevented, both succeed |
| s17 | Conflicting stage moves | none (blind `UPDATE`) | ⚠️ audit trail corrupted |
| s18 | Conflicting stage moves | optimistic compare-and-set | ✅ |

---

## 8. Design Decisions for StitchLine

1. **Keep READ COMMITTED as the default.** It never makes staff retry, and readers never wait. Each place where it is unsafe is fixed with a specific control (below), rather than paying for SERIALIZABLE everywhere.
2. **Order entry uses explicit row locks in a fixed order** (`place_order()`): the school row first, then materials by `material_id`. That prevents lost updates, write skew on credit and deadlocks, without retries.
3. **Multi-row rules become single-row rules where possible.** The overpayment rule became a `CHECK` on `invoice.amount_paid` (Portfolio 2), which is safe under concurrency for free.
4. **Interactive edits use optimistic checks** (`move_order_stage()`), because locks must never be held while a person is looking at a screen.
5. **Reports run at REPEATABLE READ**, so a statement or month-end report reflects one moment in time.
6. **SERIALIZABLE is kept in reserve** for future rules that span many rows where no natural parent row exists to lock. Any code using it must retry on SQLSTATE `40001`.
7. **Every error the application must handle has a clear SQLSTATE:**

| SQLSTATE | Meaning | Response |
|---|---|---|
| `23514` | check violation: not enough stock, credit exceeded, overpayment | show the message |
| `40001` | serialization failure | retry automatically |
| `40P01` | deadlock | retry automatically |

---

## 9. Screenshots

| Screenshot | File |
|---|---|
| Commit demo: all six parts present | `screenshots/01-commit.png` |
| Rollback Part B: aborted transaction, nothing saved | `screenshots/02-rollback-error.png` |
| Savepoint demo | `screenshots/03-savepoint.png` |
| s06 lost update in two terminals | `screenshots/04-lost-update.png` |
| s08 B blocked, then CHECK violation | `screenshots/05-atomic-update.png` |
| s11 serialization failure at COMMIT | `screenshots/06-serializable.png` |
| s14 concurrent payments rejected | `screenshots/07-payments.png` |
| s15 deadlock detected | `screenshots/08-deadlock.png` |
| `pg_locks` while B is blocked (optional) | `screenshots/09-pg-locks.png` |

To capture `pg_locks` while a session is blocked, run this from a third terminal:

```sql
SELECT pid, application_name, state, wait_event_type, left(query, 60) AS query
FROM pg_stat_activity WHERE datname = 'stitchline' AND pid <> pg_backend_pid();
SELECT pid, locktype, relation::regclass, mode, granted FROM pg_locks WHERE NOT granted;
```
