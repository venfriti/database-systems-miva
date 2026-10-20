-- Q5a Stuck orders — written with a correlated scalar subquery
-- Business use: find open orders that nobody has moved for 7+ days.
-- The subquery is re-executed once for every open order.
SELECT o.order_number,
       o.status,
       o.due_date
FROM sales_order o
WHERE o.status IN ('received', 'cutting', 'sewing', 'embroidery', 'ready')
  AND (SELECT MAX(h.changed_at)
       FROM order_stage_history h
       WHERE h.order_id = o.order_id) < TIMESTAMPTZ '2026-11-08 00:00'
ORDER BY o.due_date
