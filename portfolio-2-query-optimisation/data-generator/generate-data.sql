-- =====================================================================
-- StitchLine — Large-Volume Test Data Generator
-- Portfolio 2: Query Processing and Optimisation
--
-- Run AFTER portfolio-1 schema.sql and seed.sql:
--   psql -d stitchline -f generate-data.sql
--
-- Produces ~11 years of trading history (2016 – Nov 2026):
--   150 schools, 3,000 individuals, ~100,000 orders, ~273,000 order lines,
--   ~587,000 stage changes, ~97,000 invoices, ~140,000 payments,
--   ~212,000 stock movements.
--
-- Pure SQL (no external tools). setseed() makes every run identical,
-- so timings can be reproduced.
--
-- Realism built in, because it affects query plans:
--   * 40% of orders fall in the Aug–Sep back-to-school peak
--   * a few large schools place most school orders (skewed distribution)
--   * order_id increases with order_date (orders are entered in time order)
--   * older orders were priced lower (unit_price ≠ today's list_price)
--   * only orders from the last ~60 days are still in production
-- =====================================================================

\set ON_ERROR_STOP on
SET search_path TO stitchline;
SELECT setseed(0.42);

BEGIN;

-- ---------------------------------------------------------------------
-- 1. Staff (10 more, total 15)
-- ---------------------------------------------------------------------
INSERT INTO staff (full_name, role, email)
SELECT fn || ' ' || ln, role, lower(fn) || '.' || lower(ln) || '@stitchline.example'
FROM (
  SELECT (ARRAY['Ama','Ben','Chloe','David','Elena','Farid','Hana','Ivan','Joy','Kofi'])[g] AS fn,
         (ARRAY['Lopez','Mensah','Novak','Okafor','Patel','Quinn','Rossi','Sato','Turner','Ude'])[g] AS ln,
         (ARRAY['front_desk','production','production','production','accounts',
                'front_desk','production','production','accounts','production'])[g] AS role
  FROM generate_series(1, 10) g
) s;

-- ---------------------------------------------------------------------
-- 2. Extra materials and products
-- ---------------------------------------------------------------------
INSERT INTO material (supplier_id, name, unit, stock_qty, reorder_level) VALUES
  (1, 'Blazer wool blend',  'metre', 0, 60),
  (1, 'Cotton knit fabric', 'metre', 0, 80);

INSERT INTO product (name, category) VALUES
  ('School skirt',   'uniform'),
  ('Pinafore dress', 'uniform'),
  ('Blazer',         'uniform'),
  ('Sports shorts',  'sportswear'),
  ('PE T-shirt',     'sportswear'),
  ('Cap',            'accessory'),
  ('Tie',            'accessory'),
  ('Socks (pair)',   'accessory');

CREATE TEMP TABLE size_mult (size VARCHAR(10) PRIMARY KEY, m NUMERIC) ON COMMIT DROP;
INSERT INTO size_mult VALUES
  ('XS',0.85),('S',0.90),('M',1.00),('L',1.10),('XL',1.20),('XXL',1.30),('STD',1.00);

-- Size/colour variants (existing seed variants are kept)
WITH spec(pname, colours, sizes, base) AS (VALUES
  ('School shirt',    ARRAY['White','Light blue'],           ARRAY['XS','S','M','L','XL','XXL'], 20.0),
  ('School trousers', ARRAY['Navy','Grey','Black'],          ARRAY['XS','S','M','L','XL','XXL'], 25.0),
  ('Sports jersey',   ARRAY['Green','Red','Blue','Yellow'],  ARRAY['XS','S','M','L','XL','XXL'], 30.0),
  ('School skirt',    ARRAY['Navy','Grey','Maroon'],         ARRAY['XS','S','M','L','XL','XXL'], 22.0),
  ('Pinafore dress',  ARRAY['Navy','Maroon','Green'],        ARRAY['XS','S','M','L','XL','XXL'], 28.0),
  ('Blazer',          ARRAY['Navy','Black','Maroon'],        ARRAY['XS','S','M','L','XL','XXL'], 60.0),
  ('Sports shorts',   ARRAY['Green','Red','Blue','Yellow'],  ARRAY['XS','S','M','L','XL','XXL'], 15.0),
  ('PE T-shirt',      ARRAY['White'],                        ARRAY['XS','S','M','L','XL','XXL'], 12.0),
  ('Cap',             ARRAY['Navy','Red'],                   ARRAY['STD'],                        8.0),
  ('Tie',             ARRAY['Navy','Maroon','Green'],        ARRAY['STD'],                        6.0),
  ('Socks (pair)',    ARRAY['White','Grey'],                 ARRAY['S','M','L'],                  3.0)
)
INSERT INTO product_variant (product_id, size, colour, list_price)
SELECT p.product_id, s.size, c.colour, round(spec.base * sm.m, 2)
FROM spec
JOIN product p                         ON p.name = spec.pname
CROSS JOIN LATERAL unnest(spec.colours) c(colour)
CROSS JOIN LATERAL unnest(spec.sizes)   s(size)
JOIN size_mult sm                      ON sm.size = s.size
ON CONFLICT (product_id, size, colour) DO NOTHING;

-- Bill of materials for every variant that does not have one yet
WITH bom(pname, material, base_qty, scales) AS (VALUES
  ('School shirt',    'White poplin fabric',   1.40, true),
  ('School shirt',    'Buttons (pack of 100)', 0.07, false),
  ('School trousers', 'Navy gabardine fabric', 1.40, true),
  ('School trousers', 'Buttons (pack of 100)', 0.02, false),
  ('School skirt',    'Navy gabardine fabric', 1.20, true),
  ('Pinafore dress',  'Navy gabardine fabric', 1.60, true),
  ('Blazer',          'Blazer wool blend',     1.80, true),
  ('Blazer',          'Buttons (pack of 100)', 0.04, false),
  ('Sports jersey',   'Polyester sports mesh', 1.20, true),
  ('Sports shorts',   'Polyester sports mesh', 0.80, true),
  ('PE T-shirt',      'Cotton knit fabric',    1.00, true),
  ('Cap',             'Polyester sports mesh', 0.30, false),
  ('Tie',             'Navy gabardine fabric', 0.40, false),
  ('Socks (pair)',    'Cotton knit fabric',    0.20, false)
)
INSERT INTO product_material (variant_id, material_id, qty_per_unit)
SELECT v.variant_id, m.material_id,
       round(b.base_qty * CASE WHEN b.scales THEN sm.m ELSE 1 END, 3)
FROM bom b
JOIN product p          ON p.name = b.pname
JOIN product_variant v  ON v.product_id = p.product_id
JOIN material m         ON m.name = b.material
JOIN size_mult sm       ON sm.size = v.size
WHERE NOT EXISTS (SELECT 1 FROM product_material pm WHERE pm.variant_id = v.variant_id);

-- ---------------------------------------------------------------------
-- 3. Customers: 147 more schools (150 total), 2,997 individuals (3,000)
-- ---------------------------------------------------------------------
CREATE TEMP TABLE gen_school ON COMMIT DROP AS
SELECT g,
  (ARRAY['Riverside','Oakwood','Kingsway','Lakeview','Westbrook','Maple Grove','Sunrise',
         'Cedar Ridge','Northfield','Bright Future','Harmony','Victory','Unity','Crestwood',
         'Bayside','Pinecrest','Meadowbrook','Silver Oak','Royal Heights','Golden Gate',
         'Evergreen','Fairview','Springfield','Brookside','Summit','Heritage','Beacon',
         'Excel','Ridgeway','Starlight'])[1 + (g / 6) % 30]
  || ' ' ||
  (ARRAY['Academy','College','High School','Primary School','International School',
         'Grammar School'])[1 + g % 6]                                       AS school_name,
  (ARRAY['Mr.','Mrs.','Ms.','Dr.'])[1 + g % 4] || ' ' ||
  (ARRAY['Adams','Baker','Clarke','Diallo','Evans','Fischer','Garcia','Hughes','Ibrahim',
         'Jones','Kim','Lewis','Moreno','Nkosi','Owen'])[1 + g % 15]         AS contact_person
FROM generate_series(0, 146) g;

INSERT INTO customer (customer_type, phone, email, address, created_at)
SELECT 'school', '+2000' || lpad(g::text, 6, '0'), 'office' || g || '@school.example',
       (1 + g % 200) || ' ' || (ARRAY['Park Road','High Street','Church Street','Station Road','Mill Lane'])[1 + g % 5],
       timestamp '2015-06-01' + g * interval '20 days'
FROM gen_school;

INSERT INTO school (customer_id, school_name, contact_person, contact_phone)
SELECT c.customer_id, gs.school_name, gs.contact_person, '+2100' || lpad(gs.g::text, 6, '0')
FROM gen_school gs
JOIN customer c ON c.phone = '+2000' || lpad(gs.g::text, 6, '0');

CREATE TEMP TABLE gen_ind ON COMMIT DROP AS
SELECT g,
  (ARRAY['Adaeze','Bola','Chidi','Dami','Efe','Femi','Grace','Hassan','Ife','Jide',
         'Kemi','Lara','Musa','Nneka','Ola','Peter','Rita','Sade','Tunde','Uche',
         'Ana','Ben','Carla','Dmitri','Eva','Felix','Hiro','Isla','Jamal','Lena'])[1 + g % 30]  AS first_name,
  (ARRAY['Adeyemi','Bello','Chukwu','Danjuma','Eze','Fashola','Garba','Hassan','Ibe','Johnson',
         'Kalu','Lawal','Mohammed','Nwosu','Obi','Peters','Quadri','Rahman','Salami','Taiwo',
         'Brown','Costa','Dubois','Ivanova','Kowalski','Larsen','Martin','Nakamura','Silva','Weber'])[1 + (g / 30) % 30] AS last_name
FROM generate_series(0, 2996) g;

INSERT INTO customer (customer_type, phone, email, address, created_at)
SELECT 'individual', '+3000' || lpad(g::text, 6, '0'),
       CASE WHEN random() < 0.6 THEN 'cust' || g || '@mail.example' END,
       CASE WHEN random() < 0.8 THEN (1 + g % 90) || ' ' || (ARRAY['Palm Close','Market Lane','River Road','Hill Crescent'])[1 + g % 4] END,
       timestamp '2015-09-01' + g * interval '1 day 6 hours'
FROM gen_ind;

INSERT INTO individual_customer (customer_id, first_name, last_name)
SELECT c.customer_id, gi.first_name, gi.last_name
FROM gen_ind gi
JOIN customer c ON c.phone = '+3000' || lpad(gi.g::text, 6, '0');

-- Body measurements: each measure recorded for ~70% of individuals
INSERT INTO customer_measurement (customer_id, measure_name, value_cm)
SELECT ic.customer_id, m.name, round((m.lo + random() * (m.hi - m.lo))::numeric, 1)
FROM individual_customer ic
CROSS JOIN (VALUES ('bust_chest', 78, 118), ('waist', 60, 105), ('hip', 85, 125),
                   ('length', 95, 150), ('sleeve', 55, 68), ('shoulder', 36, 50)) m(name, lo, hi)
WHERE NOT EXISTS (SELECT 1 FROM customer_measurement x WHERE x.customer_id = ic.customer_id)
  AND random() < 0.7;

-- ---------------------------------------------------------------------
-- 4. Embroidery designs
-- ---------------------------------------------------------------------
INSERT INTO embroidery_design (customer_id, name, file_url, stitch_count)
SELECT s.customer_id, 'School crest', 'designs/crest_' || s.customer_id || '.dst', 5000 + floor(random() * 6000)::int
FROM school s
WHERE NOT EXISTS (SELECT 1 FROM embroidery_design d WHERE d.customer_id = s.customer_id);

INSERT INTO embroidery_design (customer_id, name, file_url, stitch_count)
SELECT s.customer_id, 'Sports logo', 'designs/sports_' || s.customer_id || '.dst', 2000 + floor(random() * 3000)::int
FROM school s WHERE random() < 0.5;

INSERT INTO embroidery_design (customer_id, name, file_url, stitch_count)
SELECT ic.customer_id, 'Monogram', 'designs/monogram_' || ic.customer_id || '.dst', 800 + floor(random() * 1200)::int
FROM individual_customer ic
WHERE random() < 0.15
  AND NOT EXISTS (SELECT 1 FROM embroidery_design d WHERE d.customer_id = ic.customer_id);

INSERT INTO embroidery_design (customer_id, name, file_url, stitch_count) VALUES
  (NULL, 'House shield',    'designs/house_shield.dst',    1800),
  (NULL, 'Prefect badge',   'designs/prefect_badge.dst',   2400),
  (NULL, 'Number template', 'designs/number_template.dst', 900);

-- ---------------------------------------------------------------------
-- 5. Orders (~100,000)
-- ---------------------------------------------------------------------
CREATE TEMP TABLE pools ON COMMIT DROP AS
SELECT
  (SELECT array_agg(customer_id ORDER BY customer_id) FROM school)               AS schools,
  (SELECT array_agg(customer_id ORDER BY customer_id) FROM individual_customer)  AS inds,
  (SELECT array_agg(staff_id ORDER BY staff_id) FROM staff WHERE role IN ('front_desk','admin')) AS desk,
  (SELECT array_agg(staff_id ORDER BY staff_id) FROM staff WHERE role = 'production')           AS prod,
  (SELECT array_agg(staff_id ORDER BY staff_id) FROM staff WHERE role IN ('accounts','front_desk')) AS cashiers,
  (SELECT array_agg(v.variant_id ORDER BY v.variant_id) FROM product_variant v JOIN product p USING (product_id)
     WHERE p.category <> 'ankara_custom')                                          AS school_variants,
  (SELECT array_agg(v.variant_id ORDER BY v.variant_id) FROM product_variant v JOIN product p USING (product_id)
     WHERE p.category IN ('uniform','accessory'))                                  AS ind_variants,
  (SELECT min(v.variant_id) FROM product_variant v JOIN product p USING (product_id)
     WHERE p.category = 'ankara_custom')                                           AS ankara_variant;

CREATE TEMP TABLE gen_order ON COMMIT DROP AS
SELECT x.g, x.is_school, x.order_date,
       CASE WHEN x.is_school
            THEN p.schools[1 + floor(power(random(), 2.5) * cardinality(p.schools))::int]   -- skewed
            ELSE p.inds[1 + floor(random() * cardinality(p.inds))::int] END            AS customer_id,
       p.desk[1 + floor(random() * cardinality(p.desk))::int]                        AS taken_by,
       x.order_date + 14 + floor(random() * 31)::int                                 AS due_date,
       date '2026-11-15' - x.order_date                                              AS age_days,
       random()                                                                      AS r_status
FROM (
  SELECT g,
         random() < 0.35 AS is_school,
         CASE WHEN random() < 0.40
              THEN make_date(2016 + floor(random() * 11)::int, 8, 1) + floor(random() * 46)::int
              ELSE date '2016-01-01' + floor(random() * (date '2026-11-14' - date '2016-01-01'))::int
         END AS order_date
  FROM generate_series(1, 100000) g
) x CROSS JOIN pools p;

ALTER TABLE gen_order ADD COLUMN status VARCHAR(12);
UPDATE gen_order SET status = CASE
  WHEN age_days > 60 THEN CASE WHEN r_status < 0.03 THEN 'cancelled' ELSE 'delivered' END
  WHEN age_days > 30 THEN CASE WHEN r_status < 0.70 THEN 'delivered'
                               WHEN r_status < 0.90 THEN 'ready' ELSE 'embroidery' END
  WHEN r_status < 0.01 THEN 'cancelled'
  WHEN age_days < 3  THEN 'received'
  WHEN age_days < 8  THEN 'cutting'
  WHEN age_days < 15 THEN 'sewing'
  WHEN age_days < 22 THEN 'embroidery'
  ELSE 'ready' END;

-- Inserted in date order, so order_id rises with order_date.
INSERT INTO sales_order (order_number, customer_id, taken_by, order_date, due_date, status)
SELECT 'SL-' || to_char(order_date, 'YYYY') || '-' || lpad(g::text, 6, '0'),
       customer_id, taken_by, order_date, due_date, status
FROM gen_order
ORDER BY order_date, g;

CREATE TEMP TABLE go ON COMMIT DROP AS
SELECT o.*, so.order_id
FROM gen_order o
JOIN sales_order so ON so.order_number = 'SL-' || to_char(o.order_date, 'YYYY') || '-' || lpad(o.g::text, 6, '0');

-- ---------------------------------------------------------------------
-- 6. Order lines
--    schools: 2–6 lines of 20–150 units; individuals: 1–2 lines of 1–3 units
-- ---------------------------------------------------------------------
CREATE TEMP TABLE gen_item ON COMMIT DROP AS
SELECT o.order_id, l.line_no, o.is_school, o.customer_id, o.order_date,
       CASE WHEN o.is_school      THEN p.school_variants[1 + floor(random() * cardinality(p.school_variants))::int]
            WHEN random() < 0.7   THEN p.ankara_variant
            ELSE p.ind_variants[1 + floor(random() * cardinality(p.ind_variants))::int] END AS variant_id,
       CASE WHEN o.is_school THEN 20 + floor(random() * 131)::int
            ELSE 1 + floor(random() * 3)::int END                                       AS quantity
FROM go o
CROSS JOIN pools p
CROSS JOIN LATERAL generate_series(1, CASE WHEN o.is_school THEN 2 + floor(random() * 5)::int
                                           ELSE 1 + floor(random() * 2)::int END) l(line_no);

-- Historic price: 2016 orders at 55% of today's list price, rising to 100% in 2026
INSERT INTO order_item (order_id, line_no, variant_id, quantity, unit_price)
SELECT gi.order_id, gi.line_no, gi.variant_id, gi.quantity,
       round(v.list_price * (0.55 + 0.45 * (extract(year FROM gi.order_date) - 2016) / 10.0), 2)
FROM gen_item gi
JOIN product_variant v ON v.variant_id = gi.variant_id;

-- ---------------------------------------------------------------------
-- 7. Embroidery placements
-- ---------------------------------------------------------------------
CREATE TEMP TABLE crest ON COMMIT DROP AS
SELECT customer_id, min(design_id) AS design_id
FROM embroidery_design WHERE customer_id IS NOT NULL
GROUP BY customer_id;

-- School crest on chest / cap front / badge
INSERT INTO order_item_design (order_id, line_no, design_id, placement, thread_colour)
SELECT gi.order_id, gi.line_no, c.design_id,
       CASE p.name WHEN 'Cap' THEN 'cap_front' WHEN 'Embroidered badge' THEN 'pocket' ELSE 'left_chest' END,
       (ARRAY['Gold','White','Navy','Silver','Maroon'])[1 + floor(random() * 5)::int]
FROM gen_item gi
JOIN crest c           ON c.customer_id = gi.customer_id
JOIN product_variant v ON v.variant_id = gi.variant_id
JOIN product p         ON p.product_id = v.product_id
WHERE gi.is_school
  AND p.name IN ('School shirt','Blazer','Sports jersey','PE T-shirt','Pinafore dress','Cap','Embroidered badge')
  AND random() < 0.9;

-- In-house design on the back of sports kit, with the school's short name
INSERT INTO order_item_design (order_id, line_no, design_id, placement, custom_text, thread_colour)
SELECT gi.order_id, gi.line_no,
       (SELECT design_id FROM embroidery_design WHERE customer_id IS NULL AND name = 'House shield'),
       'back', upper(left(s.school_name, 12)), 'White'
FROM gen_item gi
JOIN school s          ON s.customer_id = gi.customer_id
JOIN product_variant v ON v.variant_id = gi.variant_id
JOIN product p         ON p.product_id = v.product_id
WHERE p.name IN ('Sports jersey','PE T-shirt') AND random() < 0.3;

-- Monogram on the collar of individual garments
INSERT INTO order_item_design (order_id, line_no, design_id, placement, custom_text, thread_colour)
SELECT gi.order_id, gi.line_no, c.design_id, 'collar',
       upper(left(ic.first_name, 1) || left(ic.last_name, 1)),
       (ARRAY['Gold','Silver','Black'])[1 + floor(random() * 3)::int]
FROM gen_item gi
JOIN crest c                    ON c.customer_id = gi.customer_id
JOIN individual_customer ic     ON ic.customer_id = gi.customer_id
WHERE NOT gi.is_school AND random() < 0.3;

-- ---------------------------------------------------------------------
-- 8. Stage history: one row per stage the order has passed through
-- ---------------------------------------------------------------------
INSERT INTO order_stage_history (order_id, from_stage, to_stage, changed_by, changed_at)
SELECT o.order_id,
       st.stages[i - 1],
       st.stages[i],
       CASE WHEN i = 1 THEN o.taken_by
            WHEN st.stages[i] = 'delivered' THEN p.desk[1 + (o.order_id + i) % cardinality(p.desk)]
            ELSE p.prod[1 + floor(random() * cardinality(p.prod))::int] END,
       o.order_date + interval '9 hours' + ((i - 1) * 3 + random() * 2) * interval '1 day'
FROM go o
CROSS JOIN pools p
CROSS JOIN (SELECT ARRAY['received','cutting','sewing','embroidery','ready','delivered']::varchar[] AS stages) st
CROSS JOIN LATERAL generate_series(1, array_position(st.stages, o.status::varchar)) i
WHERE o.status <> 'cancelled';

INSERT INTO order_stage_history (order_id, from_stage, to_stage, changed_by, changed_at)
SELECT o.order_id, s.from_stage, s.to_stage, o.taken_by, o.order_date + s.offs
FROM go o
CROSS JOIN (VALUES (NULL, 'received', interval '9 hours'),
                   ('received', 'cancelled', interval '1 day 11 hours')) s(from_stage, to_stage, offs)
WHERE o.status = 'cancelled';

-- ---------------------------------------------------------------------
-- 9. Invoices (one per non-cancelled order)
-- ---------------------------------------------------------------------
INSERT INTO invoice (invoice_number, order_id, issue_date, due_date, total_amount)
SELECT 'INV-' || to_char(o.order_date, 'YYYY') || '-' || lpad(o.g::text, 6, '0'),
       o.order_id, o.order_date, o.order_date + 30, SUM(oi.quantity * oi.unit_price)
FROM go o
JOIN order_item oi ON oi.order_id = o.order_id
WHERE o.status <> 'cancelled'
GROUP BY o.order_id, o.g, o.order_date;

-- ---------------------------------------------------------------------
-- 10. Payments
--     Delivered: 90% fully paid (in 1 or 2 payments), 10% part-paid (debtors)
--     In progress: 75% have paid a 50% deposit
--     The overpayment trigger is disabled for the bulk load only; the
--     final check at the bottom proves no invoice was overpaid.
-- ---------------------------------------------------------------------
ALTER TABLE payment DISABLE TRIGGER prevent_overpayment;

CREATE TEMP TABLE gen_inv ON COMMIT DROP AS
SELECT i.invoice_id, i.issue_date, i.total_amount, o.order_id,
       CASE WHEN o.status = 'delivered' THEN
              CASE WHEN r < 0.45 THEN 'full1' WHEN r < 0.90 THEN 'full2' ELSE 'deposit' END
            ELSE CASE WHEN r < 0.75 THEN 'deposit' ELSE 'none' END
       END AS plan
FROM invoice i
JOIN go o ON o.order_id = i.order_id
CROSS JOIN LATERAL (SELECT random() + 0 * o.order_id AS r) rr;

INSERT INTO payment (invoice_id, amount, method, reference, paid_at, received_by)
SELECT gi.invoice_id, x.amount,
       (ARRAY['bank_transfer','bank_transfer','pos','cash','card'])[1 + floor(random() * 5)::int],
       'TRF-' || gi.invoice_id || '-' || x.seq,
       gi.issue_date + x.offs,
       p.cashiers[1 + floor(random() * cardinality(p.cashiers))::int]
FROM gen_inv gi
CROSS JOIN pools p
CROSS JOIN LATERAL (
  SELECT 1 AS seq, gi.total_amount AS amount, interval '10 hours' AS offs WHERE gi.plan = 'full1'
  UNION ALL
  SELECT 1, round(gi.total_amount * 0.5, 2), interval '10 hours' WHERE gi.plan IN ('full2','deposit')
  UNION ALL
  SELECT 2, gi.total_amount - round(gi.total_amount * 0.5, 2), interval '20 days 14 hours' WHERE gi.plan = 'full2'
) x
WHERE x.amount > 0;

ALTER TABLE payment ENABLE TRIGGER prevent_overpayment;

-- ---------------------------------------------------------------------
-- 11. Stock ledger: material usage per order, monthly restocks
-- ---------------------------------------------------------------------
INSERT INTO stock_movement (material_id, order_id, staff_id, change_qty, reason, moved_at)
SELECT pm.material_id, o.order_id,
       (SELECT prod[1 + o.order_id % cardinality(prod)] FROM pools),
       -round(SUM(oi.quantity * pm.qty_per_unit), 2),
       'order_usage',
       o.order_date + interval '3 days 8 hours'
FROM go o
JOIN order_item oi       ON oi.order_id = o.order_id
JOIN product_material pm ON pm.variant_id = oi.variant_id
WHERE o.status NOT IN ('received', 'cancelled')
GROUP BY pm.material_id, o.order_id, o.order_date
HAVING round(SUM(oi.quantity * pm.qty_per_unit), 2) > 0;

-- Restock at the start of each month: that month's usage, rounded up to
-- whole 10-unit lots. Stock therefore stays near its opening level instead
-- of piling up over 11 years.
INSERT INTO stock_movement (material_id, order_id, staff_id, change_qty, reason, moved_at)
SELECT material_id, NULL, 1,
       ceil(-SUM(change_qty) / 10) * 10,
       'purchase',
       date_trunc('month', moved_at)
FROM stock_movement
WHERE reason = 'order_usage' AND moved_at >= '2016-01-01' AND order_id > 6
GROUP BY material_id, date_trunc('month', moved_at);

-- Stored stock = ledger total (the invariant checked in Portfolio 1)
UPDATE material m
SET stock_qty = COALESCE((SELECT SUM(change_qty) FROM stock_movement sm WHERE sm.material_id = m.material_id), 0);

COMMIT;

-- Fresh planner statistics and visibility map
VACUUM ANALYZE;

-- ---------------------------------------------------------------------
-- Summary and integrity checks
-- ---------------------------------------------------------------------
\echo '--- Row counts ---'
SELECT relname AS table_name, n_live_tup AS rows
FROM pg_stat_user_tables WHERE schemaname = 'stitchline'
ORDER BY n_live_tup DESC;

\echo '--- Integrity: overpaid invoices (expect 0) ---'
SELECT COUNT(*) AS overpaid FROM v_invoice_balance WHERE balance < 0;

\echo '--- Integrity: materials not matching ledger (expect 0) ---'
SELECT COUNT(*) AS mismatched FROM material m
WHERE m.stock_qty <> (SELECT SUM(change_qty) FROM stock_movement s WHERE s.material_id = m.material_id);

\echo '--- Integrity: invoice totals not matching lines (expect 0) ---'
SELECT COUNT(*) AS mismatched FROM invoice i
WHERE i.total_amount <> (SELECT SUM(quantity * unit_price) FROM order_item oi WHERE oi.order_id = i.order_id);
