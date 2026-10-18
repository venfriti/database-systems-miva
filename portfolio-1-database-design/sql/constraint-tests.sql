-- =====================================================================
-- StitchLine — Constraint Tests
-- Each statement below SHOULD FAIL. The error message is the evidence
-- that the constraint is enforced by the database itself.
-- Run with psql (errors do not stop the script):
--   psql -d stitchline -f constraint-tests.sql
-- =====================================================================

SET search_path TO stitchline;

\echo '=== T1  PRIMARY KEY: duplicate order line ==='
INSERT INTO order_item (order_id, line_no, variant_id, quantity, unit_price)
VALUES (1, 1, 2, 5, 20.00);

\echo '=== T2  UNIQUE: duplicate customer phone ==='
INSERT INTO customer (customer_type, phone) VALUES ('individual', '+100000002001');

\echo '=== T3  FOREIGN KEY: order for a customer that does not exist ==='
INSERT INTO sales_order (order_number, customer_id, taken_by, due_date)
VALUES ('SL-TEST-0001', 999, 1, CURRENT_DATE + 7);

\echo '=== T4  CHECK: quantity must be positive ==='
INSERT INTO order_item (order_id, line_no, variant_id, quantity, unit_price)
VALUES (6, 2, 8, 0, 5.00);

\echo '=== T5  CHECK: stock cannot go negative ==='
UPDATE material SET stock_qty = stock_qty - 10000 WHERE material_id = 1;

\echo '=== T6  CHECK: status must be a valid production stage ==='
UPDATE sales_order SET status = 'lost' WHERE order_id = 6;

\echo '=== T7  CHECK: due date before order date ==='
INSERT INTO sales_order (order_number, customer_id, taken_by, order_date, due_date)
VALUES ('SL-TEST-0002', 1, 1, '2026-11-10', '2026-11-01');

\echo '=== T8  DISJOINT SUBTYPE: a school customer cannot also be an individual ==='
INSERT INTO individual_customer (customer_id, first_name, last_name)
VALUES (1, 'Wrong', 'Subtype');

\echo '=== T9  SUBTYPE RULE: only individuals can have body measurements ==='
INSERT INTO customer_measurement (customer_id, measure_name, value_cm)
VALUES (2, 'waist', 80);

\echo '=== T10 1:1 RELATIONSHIP: second invoice for the same order ==='
INSERT INTO invoice (invoice_number, order_id, due_date, total_amount)
VALUES ('INV-TEST-0001', 1, CURRENT_DATE + 30, 100.00);

\echo '=== T11 CHECK: stock usage must reference an order ==='
INSERT INTO stock_movement (material_id, staff_id, change_qty, reason)
VALUES (1, 3, -5, 'order_usage');

\echo '=== T12 ON DELETE RESTRICT: cannot delete a customer that has history ==='
DELETE FROM customer WHERE customer_id = 1;

\echo '=== T13 TRIGGER: payment larger than the outstanding balance ==='
-- Invoice 4: total 120.00, already paid 60.00 -> balance 60.00
INSERT INTO payment (invoice_id, amount, method, received_by)
VALUES (4, 100.00, 'cash', 2);

\echo '=== T14 CONTROL: a valid payment that clears the balance SUCCEEDS ==='
BEGIN;
INSERT INTO payment (invoice_id, amount, method, received_by)
VALUES (4, 60.00, 'cash', 2);
SELECT invoice_number, total_amount, amount_paid, balance
FROM v_invoice_balance WHERE invoice_id = 4;
ROLLBACK;   -- keep the sample data unchanged
