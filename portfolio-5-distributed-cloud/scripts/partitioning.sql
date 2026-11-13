-- =====================================================================
-- StitchLine — Range partitioning of orders by year (Portfolio 5)
-- Partitioning splits ONE logical table into pieces on the SAME server.
-- It is the single-node step before sharding (pieces on DIFFERENT servers).
--
--   psql -h /tmp/stitchline-cluster/sock -p 5440 -d stitchline -e -f partitioning.sql
-- =====================================================================

SET search_path TO stitchline;
\timing off
DROP TABLE IF EXISTS sales_order_part CASCADE;

-- The partition key (order_date) must be part of the primary key.
CREATE TABLE sales_order_part (
    order_id     INT         NOT NULL,
    order_number VARCHAR(20) NOT NULL,
    customer_id  INT         NOT NULL,
    taken_by     INT         NOT NULL,
    order_date   DATE        NOT NULL,
    due_date     DATE        NOT NULL,
    status       VARCHAR(12) NOT NULL,
    notes        TEXT,
    PRIMARY KEY (order_id, order_date)
) PARTITION BY RANGE (order_date);

-- One partition per year, 2016–2027, plus a default for anything else
DO $$
BEGIN
  FOR y IN 2016..2027 LOOP
    EXECUTE format('CREATE TABLE sales_order_part_%s PARTITION OF sales_order_part
                    FOR VALUES FROM (%L) TO (%L)', y, make_date(y, 1, 1), make_date(y + 1, 1, 1));
  END LOOP;
END $$;
CREATE TABLE sales_order_part_default PARTITION OF sales_order_part DEFAULT;

-- An index on the parent is created on every partition automatically
CREATE INDEX ON sales_order_part (customer_id, order_date DESC);

INSERT INTO sales_order_part
SELECT order_id, order_number, customer_id, taken_by, order_date, due_date, status, notes FROM sales_order;
ANALYZE sales_order_part;

\echo '=== 1. Rows per partition (each INSERT was routed by order_date) ==='
SELECT tableoid::regclass AS partition, COUNT(*) AS orders,
       pg_size_pretty(pg_relation_size(tableoid)) AS size
FROM sales_order_part GROUP BY tableoid ORDER BY 1;

\echo '=== 2. Partition pruning: a 2025 query touches ONE partition ==='
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF, SUMMARY OFF)
SELECT status, COUNT(*) FROM sales_order_part
WHERE order_date >= DATE '2025-01-01' AND order_date < DATE '2026-01-01'
GROUP BY status;

\echo '=== 3. No partition key in the WHERE clause: EVERY partition is searched ==='
EXPLAIN (COSTS OFF)
SELECT order_number, order_date FROM sales_order_part WHERE customer_id = 94;

\echo '=== 4. Data lifecycle: archiving 2016 ==='
\timing on
BEGIN;
DELETE FROM sales_order_part_2016;          -- row by row (for comparison only)
ROLLBACK;
BEGIN;
ALTER TABLE sales_order_part DETACH PARTITION sales_order_part_2016;   -- metadata only
ROLLBACK;
\timing off
\echo '--- DETACH removes a whole year from the live table almost instantly; the detached'
\echo '--- table can be dumped to cheap storage and dropped. Both demos were rolled back.'

DROP TABLE sales_order_part CASCADE;
