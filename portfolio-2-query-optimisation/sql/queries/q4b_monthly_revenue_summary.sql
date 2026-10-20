-- Q4b Monthly revenue by category — read from the pre-aggregated summary
-- Same result as Q4, read from mv_monthly_category_sales.
SELECT month, category, orders, units, revenue
FROM mv_monthly_category_sales
WHERE month >= DATE '2025-01-01'
  AND month <  DATE '2026-01-01'
ORDER BY month, category
