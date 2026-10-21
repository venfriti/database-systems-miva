-- =====================================================================
-- StitchLine — Index Design (Portfolio 2)
-- Each index is justified by a query in sql/queries/ and its plan in
-- execution-plans/before/. Apply, then refresh statistics:
--   psql -d stitchline -f indexes.sql
-- =====================================================================

SET search_path TO stitchline;

-- Q1 Customer history: "WHERE customer_id = ? ORDER BY order_date DESC".
-- Composite index returns one customer's orders already sorted, replacing
-- a sequential scan of 100,000 orders.
CREATE INDEX idx_sales_order_customer_date
    ON sales_order (customer_id, order_date DESC);

-- Q1, Q2, Q7: payments are always looked up by invoice. PostgreSQL does
-- not index foreign keys automatically, so the overpayment trigger
-- (Q7) was scanning every payment row on every insert.
CREATE INDEX idx_payment_invoice
    ON payment (invoice_id);

-- Q3, Q5: only ~0.6% of orders are still in production. A PARTIAL index
-- covers just those rows, so it stays tiny (a few hundred entries) while
-- the table grows by ~9,000 delivered orders a year.
CREATE INDEX idx_sales_order_open_due
    ON sales_order (due_date)
    WHERE status IN ('received', 'cutting', 'sewing', 'embroidery', 'ready');

-- Q4: date-range reports. order_id rises with order_date, so matching
-- rows sit on neighbouring pages and a range scan reads few pages.
CREATE INDEX idx_sales_order_date
    ON sales_order (order_date);

-- Q5: latest stage change per order. With (order_id, changed_at) the
-- correlated MAX() becomes a single index probe per order instead of
-- a full scan of ~590,000 history rows.
CREATE INDEX idx_stage_history_order_time
    ON order_stage_history (order_id, changed_at DESC);

-- Q6: usage per material over a recent period.
CREATE INDEX idx_stock_movement_material_time
    ON stock_movement (material_id, moved_at);

ANALYZE;
