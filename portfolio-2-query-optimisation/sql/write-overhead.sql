-- =====================================================================
-- StitchLine — Cost of Indexes on Writes (Portfolio 2)
-- Indexes speed up reads but every INSERT must also update every index.
-- This script inserts 5,000 orders with and without the Portfolio 2
-- indexes on sales_order. Everything is rolled back: no data changes.
--   psql -d stitchline -f write-overhead.sql
-- =====================================================================

SET search_path TO stitchline;
\timing on

\echo '=== WITH the three extra sales_order indexes ==='
BEGIN;
EXPLAIN (ANALYZE, COSTS OFF, SUMMARY ON)
INSERT INTO sales_order (order_number, customer_id, taken_by, order_date, due_date, status)
SELECT 'SL-TEST-' || g, 1 + g % 3000, 2, DATE '2026-11-15', DATE '2026-12-15', 'received'
FROM generate_series(1, 5000) g;
ROLLBACK;

\echo '=== WITHOUT them (dropped inside the transaction, then restored by ROLLBACK) ==='
BEGIN;
DROP INDEX idx_sales_order_customer_date;
DROP INDEX idx_sales_order_open_due;
DROP INDEX idx_sales_order_date;
EXPLAIN (ANALYZE, COSTS OFF, SUMMARY ON)
INSERT INTO sales_order (order_number, customer_id, taken_by, order_date, due_date, status)
SELECT 'SL-TEST-' || g, 1 + g % 3000, 2, DATE '2026-11-15', DATE '2026-12-15', 'received'
FROM generate_series(1, 5000) g;
ROLLBACK;

\echo '=== Index sizes ==='
SELECT indexrelname AS index_name,
       relname      AS table_name,
       pg_size_pretty(pg_relation_size(indexrelid)) AS size
FROM pg_stat_user_indexes
WHERE schemaname = 'stitchline' AND indexrelname LIKE 'idx_%'
ORDER BY pg_relation_size(indexrelid) DESC;
