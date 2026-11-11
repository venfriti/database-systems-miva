# Changelog

Progress log for the portfolio. Newest entries first.

## 2026-11-11 — Portfolio 4: NoSQL and Advanced Data Models

- MongoDB document model: 18 tables → 6 collections, with embed/reference decisions and patterns (polymorphic, extended reference, computed, bucket)
- `setup.js` validators (including per-style Ankara specs and the overpayment rule) and indexes
- `migrate.py` (PostgreSQL → MongoDB) and queries D1–D13, run on MongoDB 7.0 as a replica set and cross-checked against PostgreSQL
- Redis key-value examples R1–R4: board cache, WATCH/MULTI, idempotency keys, Lua stock reservation
- Suitability analysis and polyglot architecture
- Portfolio 3: `p3_reset()` now also restores school credit limits

## 2026-11-07 — Portfolio 3: Transactions and Concurrency

- `place_order()` (atomic order entry with ordered row locks), `move_order_stage()` (optimistic concurrency), school credit limits
- COMMIT and ROLLBACK demos, including savepoints and non-transactional sequences
- Two-session scenario runner and 18 reproducible scenarios: isolation anomalies, lost update and three fixes, write skew vs SERIALIZABLE, payment race (P1 vs P2 design), deadlock and lock ordering, optimistic stage moves

## 2026-11-01 — Portfolio 2 data generator adjusted

- Monthly restocking now matches usage, so material stock stays near its opening level instead of piling up over 11 years

## 2026-10-22 — Portfolio 2: Query Processing and Optimisation

- Seeded data generator: 11 years of history, ~100,000 orders
- Seven business queries plus three rewritten versions
- Benchmark runner capturing `EXPLAIN (ANALYZE, BUFFERS)` plans and median timings
- Round 1: six indexes, including two partial indexes
- Round 2: stored invoice balance (overpayment trigger replaced by `CHECK`) and a materialised monthly sales summary
- Write-overhead and storage measurements; performance analysis
- Q2 and Q2b sort ties by `invoice_number`, so their results come back in a fixed order

## 2026-10-18 — Portfolio 1: Database Design and Modelling

- Case study selected: StitchLine Uniforms & Embroidery
- Conceptual ER model (Chen notation) and logical model (DBML)
- PostgreSQL schema: 18 tables, an overpayment trigger, and an outstanding-balance view
- Sample data, verification queries and constraint tests
- Normalisation derivation from the paper order sheet (UNF → BCNF)

## 2026-10-14 — Repository set up

- Folder structure for five portfolios and final documentation
