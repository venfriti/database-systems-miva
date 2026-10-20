-- Q2b Overdue balances — after storing amount_paid on the invoice
-- Same result as Q2, but reads the stored balance and the partial index
-- idx_invoice_outstanding instead of aggregating every payment.
SELECT i.invoice_number,
       o.order_number,
       c.phone,
       i.total_amount,
       i.amount_paid,
       i.total_amount - i.amount_paid AS balance,
       DATE '2026-11-15' - i.due_date AS days_overdue
FROM invoice i
JOIN sales_order o ON o.order_id    = i.order_id
JOIN customer c    ON c.customer_id = o.customer_id
WHERE i.amount_paid < i.total_amount
  AND i.due_date < DATE '2026-11-15'
ORDER BY i.due_date
LIMIT 50
