-- Q4  Monthly revenue by product category for one year
-- Business use: owner's annual sales report.
SELECT date_trunc('month', o.order_date)::date AS month,
       p.category,
       COUNT(DISTINCT o.order_id)              AS orders,
       SUM(oi.quantity)                        AS units,
       SUM(oi.quantity * oi.unit_price)        AS revenue
FROM sales_order o
JOIN order_item oi      ON oi.order_id  = o.order_id
JOIN product_variant v  ON v.variant_id = oi.variant_id
JOIN product p          ON p.product_id = v.product_id
WHERE o.order_date >= DATE '2025-01-01'
  AND o.order_date <  DATE '2026-01-01'
  AND o.status <> 'cancelled'
GROUP BY 1, 2
ORDER BY 1, 2
