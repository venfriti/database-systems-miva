# Changelog

Progress log for the portfolio. Newest entries first.

## 2026-11-15 — Portfolio 2: Query Processing and Optimisation

- Seeded data generator: 11 years of history, ~100,000 orders
- Seven business queries plus three rewritten versions
- Benchmark runner capturing `EXPLAIN (ANALYZE, BUFFERS)` plans and median timings
- Round 1: six indexes, including two partial indexes
- Round 2: stored invoice balance (overpayment trigger replaced by `CHECK`) and a materialised monthly sales summary
- Write-overhead and storage measurements; performance analysis

## 2026-11-15 — Portfolio 1: Database Design and Modelling

- Case study selected: StitchLine Uniforms & Embroidery
- Conceptual ER model (Chen notation) and logical model (DBML)
- PostgreSQL schema: 18 tables, an overpayment trigger, and an outstanding-balance view
- Sample data, verification queries and constraint tests
- Normalisation derivation from the paper order sheet (UNF → BCNF)

## 2026-11-14 — Repository set up

- Folder structure for five portfolios and final documentation
