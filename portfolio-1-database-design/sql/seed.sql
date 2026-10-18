-- =====================================================================
-- StitchLine — Sample Data (small, hand-written)
-- Run AFTER schema.sql on a fresh database (identity values start at 1).
-- Large-volume test data for Portfolios 2–3 is generated separately.
-- =====================================================================

SET search_path TO stitchline;
BEGIN;

-- Staff --------------------------------------------------------------
INSERT INTO staff (full_name, role, email) VALUES
  ('Grace Thompson', 'admin',      'grace@stitchline.example'),
  ('Daniel Mensah',  'front_desk', 'daniel@stitchline.example'),
  ('Aisha Bello',    'production', 'aisha@stitchline.example'),
  ('Liam Carter',    'production', 'liam@stitchline.example'),
  ('Mei Chen',       'accounts',   'mei@stitchline.example');

-- Suppliers & materials ----------------------------------------------
INSERT INTO supplier (name, phone) VALUES
  ('Prime Textiles Ltd',     '+100000000001'),
  ('ThreadWorks Supplies',   '+100000000002'),
  ('Wax Print Fabric House', '+100000000003');

INSERT INTO material (supplier_id, name, unit, stock_qty, reorder_level) VALUES
  (1, 'White poplin fabric',       'metre', 420.00, 100),
  (1, 'Navy gabardine fabric',     'metre', 310.00, 80),
  (1, 'Polyester sports mesh',     'metre', 150.00, 50),
  (2, 'Gold embroidery thread',    'cone',   40.00, 10),
  (2, 'White embroidery thread',   'cone',   55.00, 10),
  (3, 'Ankara wax print (6 yard)', 'piece',  25.00,  5),
  (1, 'Buttons (pack of 100)',     'piece',  60.00, 15);

-- Products & variants ------------------------------------------------
INSERT INTO product (name, category) VALUES
  ('School shirt',         'uniform'),
  ('School trousers',      'uniform'),
  ('Sports jersey',        'sportswear'),
  ('Embroidered badge',    'badge'),
  ('Custom Ankara outfit', 'ankara_custom');

INSERT INTO product_variant (product_id, size, colour, list_price) VALUES
  (1, 'S',  'White', 18.00),   -- 1
  (1, 'M',  'White', 20.00),   -- 2
  (1, 'L',  'White', 22.00),   -- 3
  (2, 'M',  'Navy',  25.00),   -- 4
  (2, 'L',  'Navy',  27.00),   -- 5
  (3, 'M',  'Green', 30.00),   -- 6
  (3, 'L',  'Green', 32.00),   -- 7
  (4, 'STD','Multi',  5.00),   -- 8
  (5, 'CUSTOM','Multi', 120.00); -- 9

-- Bill of materials (quantity of material per one unit of variant)
INSERT INTO product_material (variant_id, material_id, qty_per_unit) VALUES
  (1, 1, 1.200), (1, 7, 0.070),
  (2, 1, 1.400), (2, 7, 0.070),
  (3, 1, 1.600), (3, 7, 0.070),
  (4, 2, 1.300), (5, 2, 1.500),
  (6, 3, 1.100), (7, 3, 1.300),
  (8, 4, 0.050),
  (9, 6, 1.000);

-- Customers (supertype first, then subtype) ---------------------------
INSERT INTO customer (customer_type, phone, email, address) VALUES
  ('school',     '+100000001001', 'office@greenfield.example',  '12 Park Road'),          -- 1
  ('school',     '+100000001002', 'admin@hillcrest.example',    '4 Hill Avenue'),         -- 2
  ('school',     '+100000001003', 'bursar@stmarys.example',     '88 Church Street'),      -- 3
  ('individual', '+100000002001', 'ngozi.a@mail.example',       '7 Palm Close'),          -- 4
  ('individual', '+100000002002', NULL,                         '19 Market Lane'),        -- 5
  ('individual', '+100000002003', 'sofia.r@mail.example',       NULL);                    -- 6

INSERT INTO school (customer_id, school_name, contact_person, contact_phone) VALUES
  (1, 'Greenfield Academy',           'Mr. Paul Adams',   '+100000001101'),
  (2, 'Hillcrest International School','Mrs. Janet Okoro', '+100000001102'),
  (3, 'St. Mary''s College',           'Sr. Helen Brooks', '+100000001103');

INSERT INTO individual_customer (customer_id, first_name, last_name) VALUES
  (4, 'Ngozi', 'Adeyemi'),
  (5, 'James', 'Owusu'),
  (6, 'Sofia', 'Ramirez');

INSERT INTO customer_measurement (customer_id, measure_name, value_cm) VALUES
  (4, 'bust', 92.0), (4, 'waist', 74.0), (4, 'hip', 101.0), (4, 'length', 140.0),
  (5, 'chest', 104.0), (5, 'waist', 88.0), (5, 'sleeve', 64.0),
  (6, 'bust', 86.0), (6, 'waist', 68.0);

-- Embroidery designs ---------------------------------------------------
INSERT INTO embroidery_design (customer_id, name, file_url, stitch_count) VALUES
  (1,    'Greenfield crest',   'designs/greenfield_crest.dst', 8200),   -- 1
  (2,    'Hillcrest logo',     'designs/hillcrest_logo.dst',   6400),   -- 2
  (3,    'St Mary''s badge',   'designs/stmarys_badge.dst',    9100),   -- 3
  (NULL, 'Sports house star',  'designs/house_star.dst',       2100),   -- 4 (in-house)
  (4,    'Name monogram',      'designs/monogram_na.dst',      1500);   -- 5

-- Orders ---------------------------------------------------------------
INSERT INTO sales_order (order_number, customer_id, taken_by, order_date, due_date, status, notes) VALUES
  ('SL-2026-0001', 1, 2, '2026-08-03', '2026-08-28', 'delivered',  'Start-of-term uniforms'),   -- 1
  ('SL-2026-0002', 2, 2, '2026-08-10', '2026-09-05', 'delivered',  NULL),                       -- 2
  ('SL-2026-0003', 3, 1, '2026-10-01', '2026-11-20', 'embroidery', 'Sports day jerseys'),       -- 3
  ('SL-2026-0004', 4, 2, '2026-10-20', '2026-11-10', 'ready',      'Wedding guest outfit'),     -- 4
  ('SL-2026-0005', 5, 2, '2026-11-02', '2026-11-25', 'cutting',    NULL),                       -- 5
  ('SL-2026-0006', 1, 1, '2026-11-10', '2026-12-15', 'received',   'Replacement badges');       -- 6

INSERT INTO order_item (order_id, line_no, variant_id, quantity, unit_price) VALUES
  (1, 1, 1, 40, 18.00), (1, 2, 2, 60, 20.00), (1, 3, 4, 50, 25.00),
  (2, 1, 2, 30, 20.00), (2, 2, 3, 20, 22.00),
  (3, 1, 6, 45, 30.00), (3, 2, 7, 35, 32.00),
  (4, 1, 9,  1, 120.00),
  (5, 1, 9,  1, 120.00),
  (6, 1, 8, 80,  5.00);

INSERT INTO order_item_design (order_id, line_no, design_id, placement, custom_text, thread_colour) VALUES
  (1, 1, 1, 'left_chest', NULL,          'Gold'),
  (1, 2, 1, 'left_chest', NULL,          'Gold'),
  (2, 1, 2, 'left_chest', NULL,          'White'),
  (2, 2, 2, 'left_chest', NULL,          'White'),
  (3, 1, 3, 'left_chest', NULL,          'Gold'),
  (3, 1, 4, 'back',       'ST MARY''S',  'White'),
  (3, 2, 3, 'left_chest', NULL,          'Gold'),
  (3, 2, 4, 'back',       'ST MARY''S',  'White'),
  (4, 1, 5, 'collar',     'NA',          'Gold'),
  (6, 1, 1, 'pocket',     NULL,          'Gold');

-- Stage history (audit trail)
INSERT INTO order_stage_history (order_id, from_stage, to_stage, changed_by, changed_at) VALUES
  (1, NULL,         'received',   2, '2026-08-03 09:15'),
  (1, 'received',   'cutting',    3, '2026-08-05 08:30'),
  (1, 'cutting',    'sewing',     3, '2026-08-11 10:00'),
  (1, 'sewing',     'embroidery', 4, '2026-08-19 14:20'),
  (1, 'embroidery', 'ready',      4, '2026-08-25 16:45'),
  (1, 'ready',      'delivered',  2, '2026-08-27 11:00'),
  (2, NULL,         'received',   2, '2026-08-10 10:05'),
  (2, 'received',   'delivered',  1, '2026-09-04 15:30'),
  (3, NULL,         'received',   1, '2026-10-01 09:00'),
  (3, 'received',   'cutting',    3, '2026-10-06 08:10'),
  (3, 'cutting',    'sewing',     3, '2026-10-20 09:40'),
  (3, 'sewing',     'embroidery', 4, '2026-11-09 13:00'),
  (4, NULL,         'received',   2, '2026-10-20 12:00'),
  (4, 'received',   'cutting',    3, '2026-10-22 09:00'),
  (4, 'cutting',    'sewing',     3, '2026-10-29 09:00'),
  (4, 'sewing',     'ready',      4, '2026-11-07 17:00'),
  (5, NULL,         'received',   2, '2026-11-02 10:30'),
  (5, 'received',   'cutting',    3, '2026-11-04 08:00'),
  (6, NULL,         'received',   1, '2026-11-10 09:20');

-- Invoices (total = sum of order lines at time of issue) ---------------
INSERT INTO invoice (invoice_number, order_id, issue_date, due_date, total_amount) VALUES
  ('INV-2026-0001', 1, '2026-08-03', '2026-08-31', 3170.00),
  ('INV-2026-0002', 2, '2026-08-10', '2026-09-10', 1040.00),
  ('INV-2026-0003', 3, '2026-10-01', '2026-11-30', 2470.00),
  ('INV-2026-0004', 4, '2026-10-20', '2026-11-10',  120.00),
  ('INV-2026-0005', 5, '2026-11-02', '2026-11-25',  120.00),
  ('INV-2026-0006', 6, '2026-11-10', '2026-12-15',  400.00);

-- Payments (deposits and part-payments) --------------------------------
INSERT INTO payment (invoice_id, amount, method, reference, paid_at, received_by) VALUES
  (1, 1500.00, 'bank_transfer', 'TRF-88120', '2026-08-03 10:00', 5),
  (1, 1670.00, 'bank_transfer', 'TRF-90311', '2026-08-27 11:30', 5),
  (2, 1040.00, 'bank_transfer', 'TRF-90544', '2026-09-04 15:45', 5),
  (3, 1200.00, 'bank_transfer', 'TRF-93007', '2026-10-01 11:00', 5),
  (4,   60.00, 'cash',          NULL,        '2026-10-20 12:10', 2),
  (5,   50.00, 'pos',           'POS-1182',  '2026-11-02 10:40', 2);

-- Stock movements --------------------------------------------------------
-- Purchases (restocks) and usage linked to orders.
-- material.stock_qty must always equal the sum of its movements.
INSERT INTO stock_movement (material_id, order_id, staff_id, change_qty, reason, moved_at) VALUES
  (1, NULL, 1,  426.00, 'adjustment',  '2026-07-01 08:00'),   -- opening balances
  (2, NULL, 1,  225.00, 'adjustment',  '2026-07-01 08:00'),
  (3, NULL, 1,  245.00, 'adjustment',  '2026-07-01 08:00'),
  (4, NULL, 1,   45.00, 'adjustment',  '2026-07-01 08:00'),
  (5, NULL, 1,   57.00, 'adjustment',  '2026-07-01 08:00'),
  (6, NULL, 1,   27.00, 'adjustment',  '2026-07-01 08:00'),
  (7, NULL, 1,   60.00, 'adjustment',  '2026-07-01 08:00'),
  (1, NULL, 1,  200.00, 'purchase',    '2026-07-28 09:00'),
  (2, NULL, 1,  150.00, 'purchase',    '2026-07-28 09:00'),
  (1, 1,    3, -132.00, 'order_usage', '2026-08-05 08:45'),   -- 40×1.2 + 60×1.4
  (2, 1,    3,  -65.00, 'order_usage', '2026-08-05 08:45'),   -- 50×1.3
  (4, 1,    4,   -5.00, 'order_usage', '2026-08-19 14:30'),
  (1, 2,    3,  -74.00, 'order_usage', '2026-08-11 09:00'),   -- 30×1.4 + 20×1.6
  (3, 3,    3,  -95.00, 'order_usage', '2026-10-06 08:20'),   -- 45×1.1 + 35×1.3
  (6, 4,    3,   -1.00, 'order_usage', '2026-10-22 09:10'),
  (6, 5,    3,   -1.00, 'order_usage', '2026-11-04 08:10'),
  (5, NULL, 1,   -2.00, 'adjustment',  '2026-10-31 17:00');   -- damaged cones

COMMIT;
