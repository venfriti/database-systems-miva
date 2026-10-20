-- Q3  Production board
-- Business use: production staff see every order still in the workshop,
--               most urgent first.
SELECT o.order_number,
       COALESCE(s.school_name, ic.first_name || ' ' || ic.last_name) AS customer,
       o.status,
       o.due_date,
       o.due_date - DATE '2026-11-15' AS days_left
FROM sales_order o
JOIN customer c                  ON c.customer_id  = o.customer_id
LEFT JOIN school s               ON s.customer_id  = c.customer_id
LEFT JOIN individual_customer ic ON ic.customer_id = c.customer_id
WHERE o.status IN ('received', 'cutting', 'sewing', 'embroidery', 'ready')
ORDER BY o.due_date
