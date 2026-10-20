-- Q5b Stuck orders — same question rewritten with NOT EXISTS
-- Logically equivalent to Q5a. The planner can turn NOT EXISTS into an
-- anti-join, so the history table is scanned once instead of once per order.
SELECT o.order_number,
       o.status,
       o.due_date
FROM sales_order o
WHERE o.status IN ('received', 'cutting', 'sewing', 'embroidery', 'ready')
  AND NOT EXISTS (SELECT 1
                  FROM order_stage_history h
                  WHERE h.order_id = o.order_id
                    AND h.changed_at >= TIMESTAMPTZ '2026-11-08 00:00')
ORDER BY o.due_date
