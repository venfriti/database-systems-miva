-- Q6  Material reorder report
-- Business use: what to restock — current stock, last 90 days of usage,
--               and how many days the remaining stock will last.
SELECT m.name,
       m.unit,
       m.stock_qty,
       m.reorder_level,
       -SUM(sm.change_qty)                                          AS used_last_90_days,
       round(m.stock_qty / NULLIF(-SUM(sm.change_qty) / 90.0, 0), 1) AS days_of_cover
FROM material m
LEFT JOIN stock_movement sm
       ON sm.material_id = m.material_id
      AND sm.reason      = 'order_usage'
      AND sm.moved_at   >= TIMESTAMPTZ '2026-08-17 00:00'
GROUP BY m.material_id
ORDER BY days_of_cover NULLS LAST
