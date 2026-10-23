-- Q2  Overdue balances (the app's "Outstanding" tab)
-- Business use: accounts chases the 50 most overdue unpaid invoices.
-- Reference date fixed at 2026-11-15 so results are reproducible.
SELECT b.invoice_number,
       b.order_number,
       c.phone,
       b.total_amount,
       b.amount_paid,
       b.balance,
       DATE '2026-11-15' - b.due_date AS days_overdue
FROM v_invoice_balance b
JOIN customer c ON c.customer_id = b.customer_id
WHERE b.balance > 0
  AND b.due_date < DATE '2026-11-15'
ORDER BY days_overdue DESC, b.invoice_number
LIMIT 50
