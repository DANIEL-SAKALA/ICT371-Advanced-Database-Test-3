
/*
============================================================
QUESTION 7: WATER METER READINGS AND BILLING
============================================================
*/


-- ==========================================================
-- QUESTION 7 (A): DATABASE AND SEED DATA [6 MARKS]
-- Create four tables:
-- customers, readings, bills and receivable_snapshot.
-- Insert three customers and six meter readings.
-- ==========================================================

-- Create a separate schema for Question 7
CREATE SCHEMA IF NOT EXISTS q7;

SET search_path TO q7, public;


-- 1. CUSTOMERS TABLE
CREATE TABLE customers (
    customer_id SERIAL PRIMARY KEY,
    full_name VARCHAR(100) NOT NULL
);


-- 2. READINGS TABLE
CREATE TABLE readings (
    reading_id SERIAL PRIMARY KEY,
    customer_id INTEGER NOT NULL,
    reading_month DATE NOT NULL,
    previous_reading NUMERIC(12,2) NOT NULL,
    current_reading NUMERIC(12,2) NOT NULL,

    FOREIGN KEY (customer_id)
    REFERENCES customers(customer_id),

    -- Meter readings cannot be negative
    CHECK (previous_reading >= 0),
    CHECK (current_reading >= 0),

    -- Reading month must be the first day
    -- of a calendar month
    CHECK (
        EXTRACT(DAY FROM reading_month) = 1
    ),

    -- One reading per customer per month
    UNIQUE (customer_id, reading_month)
);


-- 3. BILLS TABLE
CREATE TABLE bills (
    bill_id SERIAL PRIMARY KEY,
    reading_id INTEGER NOT NULL UNIQUE,
    charge NUMERIC(12,2) NOT NULL,
    amount_paid NUMERIC(12,2) NOT NULL DEFAULT 0,
    due_on DATE NOT NULL,

    FOREIGN KEY (reading_id)
    REFERENCES readings(reading_id),

    -- Charge cannot be negative
    CHECK (charge >= 0),

    -- Amount paid cannot be negative
    CHECK (amount_paid >= 0),

    -- Amount paid cannot exceed the bill charge
    CHECK (amount_paid <= charge)
);


-- 4. RECEIVABLE SNAPSHOT TABLE
CREATE TABLE receivable_snapshot (
    snapshot_date DATE PRIMARY KEY,
    total_due NUMERIC(14,2) NOT NULL
);


-- Insert three customers
INSERT INTO customers (full_name)
VALUES
('John Banda'),
('Mary Phiri'),
('Peter Zulu');


-- Insert six water meter readings
INSERT INTO readings (
    customer_id,
    reading_month,
    previous_reading,
    current_reading
)
VALUES

-- Customer 1: Zero consumption
(1, DATE '2026-09-01', 100, 100),

-- Customer 1: Exactly 10 units
(1, DATE '2026-10-01', 100, 110),

-- Customer 2: Above 10 units (15 units)
(2, DATE '2026-09-01', 200, 215),

-- Customer 2: Five units
(2, DATE '2026-10-01', 215, 220),

-- Customer 3: Above 10 units (12 units)
(3, DATE '2026-09-01', 300, 312),

-- Customer 3: Above 10 units (20 units)
(3, DATE '2026-10-01', 312, 332);



-- ==========================================================
-- QUESTION 7 (B): FUNCTION [6 MARKS]
-- Function: fn_water_charge
--
-- Calculates water charges using two tariff bands.
--
-- First 10 units = K5 per unit.
-- Units above 10 = K8 per unit.
-- Zero consumption = K0.
--
-- Rejects NULL and negative consumption.
-- Returns an exact two-decimal charge.
-- ==========================================================

CREATE OR REPLACE FUNCTION fn_water_charge(
    p_units NUMERIC
)
RETURNS NUMERIC(12,2)
LANGUAGE plpgsql
AS $$
DECLARE
    v_charge NUMERIC(12,2);
BEGIN

    -- Reject NULL consumption
    IF p_units IS NULL THEN
        RAISE EXCEPTION
        'Water consumption cannot be NULL';
    END IF;

    -- Reject negative consumption
    IF p_units < 0 THEN
        RAISE EXCEPTION
        'Water consumption cannot be negative';
    END IF;

    -- Zero consumption costs zero
    IF p_units = 0 THEN

        v_charge := 0;

    -- First tariff band: up to 10 units
    ELSIF p_units <= 10 THEN

        v_charge := p_units * 5;

    -- Second tariff band: above 10 units
    ELSE

        v_charge :=
            (10 * 5)
            + ((p_units - 10) * 8);

    END IF;

    -- Return exact two-decimal amount
    RETURN ROUND(v_charge, 2);

END;
$$;



-- ==========================================================
-- QUESTION 7 (C): PROCEDURE [8 MARKS]
-- Procedure: pr_generate_bill
--
-- Accepts a reading ID and due date.
-- Derives consumption from current and previous readings.
-- Calls fn_water_charge to calculate the bill.
-- Inserts a bill with amount_paid equal to zero.
--
-- Rejects unknown readings and readings that
-- already have a bill.
-- ==========================================================

CREATE OR REPLACE PROCEDURE pr_generate_bill(
    p_reading_id INTEGER,
    p_due_on DATE
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_previous_reading NUMERIC(12,2);
    v_current_reading NUMERIC(12,2);
    v_units NUMERIC(12,2);
    v_charge NUMERIC(12,2);
BEGIN

    -- Validate reading ID
    IF p_reading_id IS NULL THEN
        RAISE EXCEPTION
        'Reading ID cannot be NULL';
    END IF;

    -- Validate due date
    IF p_due_on IS NULL THEN
        RAISE EXCEPTION
        'Due date cannot be NULL';
    END IF;

    -- Retrieve meter readings
    SELECT
        previous_reading,
        current_reading

    INTO
        v_previous_reading,
        v_current_reading

    FROM readings
    WHERE reading_id = p_reading_id;

    -- Reject unknown reading
    IF NOT FOUND THEN
        RAISE EXCEPTION
        'Reading ID % does not exist',
        p_reading_id;
    END IF;

    -- Reject a reading that already has a bill
    IF EXISTS (
        SELECT 1
        FROM bills
        WHERE reading_id = p_reading_id
    ) THEN

        RAISE EXCEPTION
        'A bill already exists for reading ID %',
        p_reading_id;

    END IF;

    -- Calculate water consumption
    v_units :=
        v_current_reading - v_previous_reading;

    -- Calculate charge using the function
    v_charge := fn_water_charge(v_units);

    -- Insert the bill
    INSERT INTO bills (
        reading_id,
        charge,
        amount_paid,
        due_on
    )
    VALUES (
        p_reading_id,
        v_charge,
        0,
        p_due_on
    );

END;
$$;



-- ==========================================================
-- QUESTION 7 (D): TRIGGER [8 MARKS]
-- Trigger: trg_validate_meter_reading
--
-- BEFORE INSERT OR UPDATE trigger on readings.
--
-- Rejects a current meter reading that is below
-- the previous meter reading.
--
-- Protects the database even when readings are
-- inserted directly through SQL imports.
-- ==========================================================

-- Create trigger function
CREATE OR REPLACE FUNCTION fn_validate_meter_reading()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN

    -- Check that current reading is not below
    -- the previous reading.
    IF NEW.current_reading < NEW.previous_reading THEN

        RAISE EXCEPTION
        'Invalid meter reading: Current reading (%) cannot be less than previous reading (%)',
        NEW.current_reading,
        NEW.previous_reading;

    END IF;

    -- Allow valid reading
    RETURN NEW;

END;
$$;


-- Create BEFORE INSERT OR UPDATE trigger
CREATE TRIGGER trg_validate_meter_reading
BEFORE INSERT OR UPDATE ON readings
FOR EACH ROW
EXECUTE FUNCTION fn_validate_meter_reading();



-- ==========================================================
-- QUESTION 7 (A): SEED DATA CONTINUED
-- Generate six bills from the six meter readings.
-- Each bill has an initial payment of zero.
-- ==========================================================

-- Generate bill for reading 1
-- Consumption: 0 units
-- Expected charge: K0
CALL pr_generate_bill(
    1,
    DATE '2026-09-15'
);


-- Generate bill for reading 2
-- Consumption: 10 units
-- Expected charge: K50
CALL pr_generate_bill(
    2,
    DATE '2026-10-15'
);


-- Generate bill for reading 3
-- Consumption: 15 units
-- Expected charge: K90
CALL pr_generate_bill(
    3,
    DATE '2026-09-15'
);


-- Generate bill for reading 4
-- Consumption: 5 units
-- Expected charge: K25
CALL pr_generate_bill(
    4,
    DATE '2026-10-15'
);


-- Generate bill for reading 5
-- Consumption: 12 units
-- Expected charge: K66
CALL pr_generate_bill(
    5,
    DATE '2026-09-15'
);


-- Generate bill for reading 6
-- Consumption: 20 units
-- Expected charge: K130
CALL pr_generate_bill(
    6,
    DATE '2026-10-15'
);


-- Make sample payments for testing.
-- Bill 2: Partially paid K20.
UPDATE bills
SET amount_paid = 20
WHERE bill_id = 2;


-- Bill 3: Fully paid K90.
UPDATE bills
SET amount_paid = 90
WHERE bill_id = 3;


-- Bill 5: Partially paid K30.
UPDATE bills
SET amount_paid = 30
WHERE bill_id = 5;



-- ==========================================================
-- QUESTION 7 (E): VIEW [5 MARKS]
-- View: v_overdue_bills
--
-- Displays:
-- Customer name.
-- Due date.
-- Outstanding amount.
--
-- Only displays bills that:
-- 1. Have a due date before CURRENT_DATE.
-- 2. Have not been fully paid.
-- ==========================================================

CREATE OR REPLACE VIEW v_overdue_bills AS
SELECT
    c.full_name AS customer_name,
    b.due_on,

    (b.charge - b.amount_paid)
        AS outstanding_amount

FROM bills b

JOIN readings r
    ON b.reading_id = r.reading_id

JOIN customers c
    ON r.customer_id = c.customer_id

WHERE b.due_on < CURRENT_DATE
AND b.amount_paid < b.charge;


-- Display overdue bills
SELECT *
FROM v_overdue_bills
ORDER BY due_on;



-- ==========================================================
-- QUESTION 7 (F): INDEX [5 MARKS]
-- Index: idx_bills_overdue
--
-- Supports date-based searches for overdue
-- bills that have outstanding balances.
-- ==========================================================

-- Create a partial index on due_on.
-- Only bills that are not fully paid are indexed.

CREATE INDEX idx_bills_overdue
ON bills (due_on)
WHERE amount_paid < charge;


-- Matching unpaid-bill query
SELECT
    bill_id,
    reading_id,
    charge,
    amount_paid,
    due_on,
    (charge - amount_paid) AS outstanding_amount

FROM bills

WHERE due_on < CURRENT_DATE
AND amount_paid < charge;


-- Display execution plan
EXPLAIN
SELECT
    bill_id,
    reading_id,
    charge,
    amount_paid,
    due_on

FROM bills

WHERE due_on < CURRENT_DATE
AND amount_paid < charge;


-- INDEX JUSTIFICATION:
--
-- The index is created on due_on because
-- the query searches for bills with due dates
-- before the current date.
--
-- The partial index includes only bills where
-- amount_paid is less than charge.
--
-- Fully paid bills are excluded.
--
-- This reduces index size and supports
-- date-based searches for outstanding bills.



-- ==========================================================
-- QUESTION 7 (G): SCHEDULED JOB [6 MARKS]
-- Procedure: pr_refresh_receivables
--
-- Calculates today's total unpaid bill balances.
-- Stores the total in receivable_snapshot.
--
-- If the procedure runs again on the same date,
-- it replaces the previous total instead of
-- inserting a duplicate snapshot.
-- ==========================================================

CREATE OR REPLACE PROCEDURE pr_refresh_receivables()
LANGUAGE plpgsql
AS $$
DECLARE
    v_total_due NUMERIC(14,2);
BEGIN

    -- Calculate total outstanding balances
    -- Only bills with an outstanding balance
    -- are included.

    SELECT
        COALESCE(
            SUM(charge - amount_paid),
            0
        )

    INTO v_total_due

    FROM bills

    WHERE amount_paid < charge;


    -- Insert today's receivable snapshot
    INSERT INTO receivable_snapshot (
        snapshot_date,
        total_due
    )
    VALUES (
        CURRENT_DATE,
        v_total_due
    )

    -- Replace the existing total if today's
    -- snapshot already exists.
    ON CONFLICT (snapshot_date)

    DO UPDATE SET
        total_due = EXCLUDED.total_due;

END;
$$;


-- Manually test the procedure
CALL pr_refresh_receivables();


-- Display receivable snapshot
SELECT *
FROM receivable_snapshot;



-- ==========================================================
-- QUESTION 7 (G): SCHEDULED JOB USING PG_CRON
-- Schedule daily execution at 00:30.
-- Requires pg_cron installation and configuration.
-- ==========================================================

-- Enable pg_cron extension
CREATE EXTENSION IF NOT EXISTS pg_cron;


-- Schedule receivables refresh every day at 00:30
SELECT cron.schedule(
    'refresh_water_receivables',
    '30 0 * * *',
    'CALL q7.pr_refresh_receivables();'
);


-- Display scheduled jobs
SELECT *
FROM cron.job;



-- ==========================================================
-- FINAL TESTING: QUESTION 7
-- ==========================================================


-- 1. Display all customers
SELECT *
FROM customers;


-- 2. Display all meter readings
SELECT *
FROM readings
ORDER BY reading_id;


-- 3. Display all generated bills
SELECT *
FROM bills
ORDER BY bill_id;


-- 4. Test zero consumption
-- Expected result: K0.00
SELECT fn_water_charge(0);


-- 5. Test exactly 10 units
-- Expected result: K50.00
SELECT fn_water_charge(10);


-- 6. Test 15 units
-- Expected result: K90.00
SELECT fn_water_charge(15);


-- 7. Test 20 units
-- Expected result: K130.00
SELECT fn_water_charge(20);


-- 8. Display overdue bills
SELECT *
FROM v_overdue_bills;


-- 9. Display receivable snapshot
SELECT *
FROM receivable_snapshot;


-- 10. Refresh receivable snapshot again
CALL pr_refresh_receivables();


-- 11. Display updated snapshot
-- There should still be only one record for today.
SELECT *
FROM receivable_snapshot;


-- 12. Test the matching index query
EXPLAIN
SELECT *
FROM bills
WHERE due_on < CURRENT_DATE
AND amount_paid < charge;


-- 13. Display scheduled jobs
SELECT *
FROM cron.job;


-- ==========================================================
-- END OF QUESTION 7
-- ==========================================================
