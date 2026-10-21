-- =====================================================================
-- StitchLine — Schema Changes for Queries that Indexes Could Not Fix
-- Portfolio 2, optimisation round 2.  Apply after indexes.sql:
--   psql -d stitchline -f redesign.sql
--
-- Q2 (Outstanding tab) and Q4 (annual revenue report) barely improved
-- with indexes, because both must aggregate a large share of the data
-- every time they run. The fix is to stop recomputing those totals.
-- =====================================================================

SET search_path TO stitchline;

-- ---------------------------------------------------------------------
-- A. Q2 — Store amount_paid on the invoice (controlled denormalisation)
-- ---------------------------------------------------------------------
-- Portfolio 1 deliberately computed the balance in a view. With ~140,000
-- payments, that view aggregates every payment on every request
-- (~330 ms), and the Outstanding tab is opened constantly.

ALTER TABLE invoice
    ADD COLUMN amount_paid NUMERIC(12,2) NOT NULL DEFAULT 0;

UPDATE invoice i
SET amount_paid = p.paid
FROM (SELECT invoice_id, SUM(amount) AS paid FROM payment GROUP BY invoice_id) p
WHERE p.invoice_id = i.invoice_id;

-- Overpayment is now a single-row rule, so a CHECK can enforce it.
ALTER TABLE invoice
    ADD CONSTRAINT chk_invoice_not_overpaid
    CHECK (amount_paid >= 0 AND amount_paid <= total_amount);

-- Keep amount_paid in step with the payment table. The UPDATE uses
-- "amount_paid = amount_paid + delta", which PostgreSQL applies under a
-- row lock, so two simultaneous payments cannot overwrite each other.
CREATE FUNCTION trg_sync_amount_paid() RETURNS trigger AS $$
BEGIN
    IF TG_OP IN ('UPDATE', 'DELETE') THEN
        UPDATE invoice SET amount_paid = amount_paid - OLD.amount
        WHERE invoice_id = OLD.invoice_id;
    END IF;
    IF TG_OP IN ('INSERT', 'UPDATE') THEN
        UPDATE invoice SET amount_paid = amount_paid + NEW.amount
        WHERE invoice_id = NEW.invoice_id;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER sync_amount_paid
AFTER INSERT OR UPDATE OF amount, invoice_id OR DELETE ON payment
FOR EACH ROW EXECUTE FUNCTION trg_sync_amount_paid();

-- The Portfolio 1 trigger is now redundant: the CHECK above does the
-- same job, and unlike the trigger it cannot be bypassed by a race.
DROP TRIGGER prevent_overpayment ON payment;

-- Only ~10% of invoices are unpaid. A partial index holds just those.
CREATE INDEX idx_invoice_outstanding
    ON invoice (due_date)
    WHERE amount_paid < total_amount;

-- ---------------------------------------------------------------------
-- B. Q4 — Pre-aggregated monthly sales (materialised view)
-- ---------------------------------------------------------------------
-- Past months never change, yet the report re-joins ~270,000 order
-- lines each time. The summary is computed once and refreshed nightly.

CREATE MATERIALIZED VIEW mv_monthly_category_sales AS
SELECT date_trunc('month', o.order_date)::date AS month,
       p.category,
       COUNT(DISTINCT o.order_id)              AS orders,
       SUM(oi.quantity)                        AS units,
       SUM(oi.quantity * oi.unit_price)        AS revenue
FROM sales_order o
JOIN order_item oi      ON oi.order_id  = o.order_id
JOIN product_variant v  ON v.variant_id = oi.variant_id
JOIN product p          ON p.product_id = v.product_id
WHERE o.status <> 'cancelled'
GROUP BY 1, 2;

-- A unique index is required for REFRESH ... CONCURRENTLY, which
-- rebuilds the view without blocking readers.
CREATE UNIQUE INDEX idx_mv_monthly_sales ON mv_monthly_category_sales (month, category);

ANALYZE;

-- Nightly job:
--   REFRESH MATERIALIZED VIEW CONCURRENTLY mv_monthly_category_sales;
