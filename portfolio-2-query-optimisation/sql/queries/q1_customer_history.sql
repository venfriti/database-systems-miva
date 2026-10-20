-- Q1  Customer order history
-- Business use: a school calls to reorder; front desk opens its full history
--               with invoice totals and amounts paid.
-- Parameter:    customer_id = 94 (Bayside Primary School, ~110 orders)
SELECT o.order_number,
       o.order_date,
       o.status,
       i.invoice_number,
       i.total_amount,
       COALESCE(SUM(p.amount), 0) AS amount_paid
FROM sales_order o
LEFT JOIN invoice i ON i.order_id   = o.order_id
LEFT JOIN payment p ON p.invoice_id = i.invoice_id
WHERE o.customer_id = 94
GROUP BY o.order_id, i.invoice_id
ORDER BY o.order_date DESC
