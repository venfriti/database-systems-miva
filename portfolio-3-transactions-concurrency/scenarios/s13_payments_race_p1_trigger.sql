-- TITLE: Two payments at once — the Portfolio 1 design (trigger that sums payments)
-- LEVEL: READ COMMITTED
-- EXPECT: PROBLEM. Invoice total 120, already paid 60. Each trigger only sees COMMITTED payments, so each approves a 50 payment. Both commit and the invoice is overpaid (160 paid on 120).
-- Rebuilt in a scratch schema (p1_race), because Portfolio 2 replaced this trigger.
-- @SETUP
DROP SCHEMA IF EXISTS p1_race CASCADE;
CREATE SCHEMA p1_race;
CREATE TABLE p1_race.invoice (invoice_id INT PRIMARY KEY, total_amount NUMERIC(12,2) NOT NULL);
CREATE TABLE p1_race.payment (payment_id SERIAL PRIMARY KEY, invoice_id INT NOT NULL REFERENCES p1_race.invoice, amount NUMERIC(12,2) NOT NULL CHECK (amount > 0));
CREATE FUNCTION p1_race.trg_prevent_overpayment() RETURNS trigger AS $$
DECLARE v_total NUMERIC(12,2); v_paid NUMERIC(12,2);
BEGIN
  SELECT total_amount INTO v_total FROM p1_race.invoice WHERE invoice_id = NEW.invoice_id;
  SELECT COALESCE(SUM(amount), 0) INTO v_paid FROM p1_race.payment WHERE invoice_id = NEW.invoice_id;
  IF v_paid + NEW.amount > v_total THEN
    RAISE EXCEPTION 'Payment of % exceeds outstanding balance of %', NEW.amount, v_total - v_paid;
  END IF;
  RETURN NEW;
END; $$ LANGUAGE plpgsql;
CREATE TRIGGER prevent_overpayment BEFORE INSERT ON p1_race.payment FOR EACH ROW EXECUTE FUNCTION p1_race.trg_prevent_overpayment();
INSERT INTO p1_race.invoice VALUES (1, 120.00);
INSERT INTO p1_race.payment (invoice_id, amount) VALUES (1, 60.00);
-- @A
BEGIN;
-- @A
INSERT INTO p1_race.payment (invoice_id, amount) VALUES (1, 50.00);
-- @B
BEGIN;
-- @B
INSERT INTO p1_race.payment (invoice_id, amount) VALUES (1, 50.00);
-- @A
COMMIT;
-- @B
COMMIT;
-- @CHECK
SELECT i.total_amount, SUM(p.amount) AS total_paid, SUM(p.amount) > i.total_amount AS overpaid FROM p1_race.invoice i JOIN p1_race.payment p USING (invoice_id) GROUP BY i.invoice_id;
-- @TEARDOWN
DROP SCHEMA p1_race CASCADE;
